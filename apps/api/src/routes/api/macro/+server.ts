import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateText, generateObject } from 'ai';
import { z } from 'zod';
import { resolveModel } from '$lib/server/ai';
import { sql, nowISO } from '$lib/server/db';
import {
  AI_METRICS, briefTable, derive, loadFredMetrics, regime, trim,
  type Metric, type Point
} from '$lib/server/macro';

/**
 * Macro Intelligence — one dated snapshot of the macro picture.
 *
 * `GET /api/macro?date=YYYY-MM-DD` (default: today)
 *
 * Verified metrics are reconstructed from FRED's series for ANY date, because
 * the series has the history. Estimated metrics (India, gold) exist only for
 * dates we have already snapshotted — asking for last March returns them as
 * `unavailable` rather than a number nobody measured.
 */

const AiMetric = z.object({
  id: z.enum(['repo', 'indiacpi', 'india10y', 'nifty', 'indiavix', 'gold']),
  value: z.number().nullable(),
  asOf: z.string().nullable(),
  source: z.string().nullable(),
  sourceUrl: z.string().nullable()
});
const AiMetrics = z.object({ metrics: z.array(AiMetric) });

const Brief = z.object({
  changed: z.array(z.object({ metric: z.string(), move: z.string() })).max(5),
  why: z.string(),
  matters: z.string(),
  watch: z.array(z.string()).max(5),
  speculative: z.boolean()
});

async function ensureTable() {
  await sql`create table if not exists macro_day (
    user_id integer not null,
    date    text not null,
    payload text not null,
    created_at text not null,
    primary key (user_id, date)
  )`;
}

const today = () => new Date().toISOString().slice(0, 10);

export const GET: RequestHandler = async ({ url, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const date = (url.searchParams.get('date') ?? today()).slice(0, 10);
  const refresh = url.searchParams.get('refresh') === '1';
  const isToday = date === today();
  await ensureTable();

  const [cached] = await sql`select payload from macro_day where user_id = ${locals.user.id} and date = ${date}`;
  if (cached && !refresh) return json(JSON.parse(String(cached.payload)));

  // Verified half. Always available for any date the series covers.
  const fred = await loadFredMetrics(date);
  const byId: Record<string, Metric> = Object.fromEntries(fred.map((m) => [m.id, m]));

  // Estimated half. Only ever fetched for today — a model asked what the NIFTY
  // closed at on a random past date is guessing, and this dashboard does not.
  let estimated: Metric[] = [];
  let brief: unknown = null;
  if (isToday) {
    const prior = await priorSnapshots(locals.user.id, date);
    estimated = await loadEstimated(locals.user.id, date, prior);
    brief = await writeBrief(locals.user.id, [...fred, ...estimated]);
  } else {
    estimated = AI_METRICS.map((spec) => blank(spec, 'No snapshot was taken on this date.'));
  }

  const metrics = [...fred, ...estimated];
  const payload = {
    date,
    generatedAt: nowISO(),
    metrics,
    regime: regime(Object.fromEntries(metrics.map((m) => [m.id, m])) as Record<string, Metric>),
    brief
  };

  // Only today's snapshot is kept — a reconstructed past day is cheap to redo
  // and would otherwise pin one afternoon's view of history forever.
  if (isToday) {
    await sql`insert or replace into macro_day (user_id, date, payload, created_at)
              values (${locals.user.id}, ${date}, ${JSON.stringify(payload)}, ${nowISO()})`;
  }
  return json(payload);
};

function blank(spec: (typeof AI_METRICS)[number], note: string): Metric {
  return {
    id: spec.id, name: spec.name, category: spec.category, country: spec.country,
    unit: spec.unit, kind: spec.kind, frequency: spec.frequency,
    source: '—', sourceUrl: '', priority: spec.priority,
    value: null, asOf: null,
    change1D: null, change7D: null, change30D: null, changeYTD: null, change1Y: null,
    history: [], quality: 'unavailable', note
  };
}

/** Past snapshots give the estimated metrics their own history and changes. */
async function priorSnapshots(userId: number, before: string): Promise<Record<string, Point[]>> {
  const rows = await sql`select date, payload from macro_day
                         where user_id = ${userId} and date < ${before}
                         order by date asc limit 400`;
  const series: Record<string, Point[]> = {};
  for (const row of rows) {
    let parsed: { metrics?: Metric[] };
    try { parsed = JSON.parse(String(row.payload)); } catch { continue; }
    for (const m of parsed.metrics ?? []) {
      if (m.quality !== 'estimated' || m.value === null) continue;
      (series[m.id] ??= []).push({ d: String(row.date), v: m.value });
    }
  }
  return series;
}

async function loadEstimated(userId: number, date: string, prior: Record<string, Point[]>): Promise<Metric[]> {
  let resolved;
  try { resolved = await resolveModel('news', userId); } catch { resolved = null; }
  if (!resolved?.google) {
    return AI_METRICS.map((s) => blank(s, 'Needs a Gemini key — these are read from the web with Google Search.'));
  }

  let found: z.infer<typeof AiMetrics> | null = null;
  try {
    const { text } = await generateText({
      model: resolved.model,
      tools: { google_search: resolved.google.tools.googleSearch({}) },
      prompt:
        `Find the latest published values for each, with the date each figure is for and the source:\n` +
        `1. RBI repo rate (%)\n2. India CPI inflation, year-on-year (%)\n` +
        `3. India 10-year government bond yield (%)\n4. NIFTY 50 index close\n` +
        `5. India VIX\n6. Gold spot price in USD per troy ounce\n` +
        `Give the actual number and the date it refers to. If you cannot find a current figure for one, say so.`
    });
    const { object } = await generateObject({
      model: resolved.model,
      schema: AiMetrics,
      prompt:
        `Extract the six figures from these search results. value = the number only (no % sign, no commas). ` +
        `asOf = the date that figure is for, as YYYY-MM-DD. source = the publication or institution. ` +
        `sourceUrl = the page it came from, else null. If a figure was not found, value must be null — ` +
        `never estimate, never carry forward an old number as if it were current.\n\n${text}`
    });
    found = object;
  } catch {
    return AI_METRICS.map((s) => blank(s, 'The web lookup failed. Nothing was substituted.'));
  }

  return AI_METRICS.map((spec) => {
    const hit = found?.metrics.find((m) => m.id === spec.id);
    if (!hit || hit.value === null) return blank(spec, 'No current figure was found.');
    // Its own past snapshots are the only honest source of change for these.
    const series = [...(prior[spec.id] ?? []), { d: date, v: hit.value }];
    const d = derive(series, date);
    return {
      id: spec.id, name: spec.name, category: spec.category, country: spec.country,
      unit: spec.unit, kind: spec.kind, frequency: spec.frequency,
      source: hit.source ?? 'Web', sourceUrl: hit.sourceUrl ?? '',
      priority: spec.priority,
      ...d,
      value: hit.value,
      asOf: hit.asOf ?? date,
      history: trim(series),
      quality: 'estimated' as const,
      note: series.length < 2 ? 'Changes start once this has been snapshotted for more than one day.' : undefined
    };
  });
}

async function writeBrief(userId: number, metrics: Metric[]) {
  let resolved;
  try { resolved = await resolveModel('news', userId); } catch { return null; }
  try {
    const { object } = await generateObject({
      model: resolved.model,
      schema: Brief,
      prompt:
        `You are Catherine, writing a macro brief for one person who follows Indian markets.\n` +
        `These are the ONLY numbers you have. Every claim must trace to a row here — if the table ` +
        `does not support it, do not write it.\n\n${briefTable(metrics)}\n\n` +
        `changed: up to 5 genuinely notable moves, biggest first. "move" states the number and the change.\n` +
        `why: plausible drivers, in plain words. Say "likely" or "consistent with" — you are reading ` +
        `numbers, not sources, and you must not present a guess at causation as fact.\n` +
        `matters: what this means for an Indian household and portfolio — imports, inflation, rates, equities.\n` +
        `watch: 3-5 specific indicators or events worth watching next.\n` +
        `speculative: true if your "why" is inference rather than something the numbers show directly.\n` +
        `Rows marked [estimated] were read off the web and may be stale — never lean a conclusion on one alone.`
    });
    return object;
  } catch {
    return null;
  }
}
