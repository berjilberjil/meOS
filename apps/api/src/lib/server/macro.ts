/**
 * Macro Intelligence — the data half.
 *
 * Two kinds of number end up on that dashboard and they are never mixed up:
 *
 *  - `verified`  — pulled from FRED's public CSV endpoint (no API key), which
 *                  gives a real series with real dates. Changes are computed
 *                  from that series, not asserted by anyone.
 *  - `estimated` — read off the web by a search-grounded model, because there
 *                  is no free feed for RBI's repo rate, India CPI, the India
 *                  10Y, NIFTY, India VIX or spot gold. Always carries a source
 *                  and an as-of date, and is never badged verified.
 *
 * Nothing here invents a value. A metric with no data is `unavailable`.
 */

export type Point = { d: string; v: number };
export type Quality = 'verified' | 'estimated' | 'delayed' | 'unavailable';
export type Delta = { abs: number; pct: number } | null;

export type Metric = {
  id: string;
  name: string;
  category: string;
  country: string;
  unit: string;
  /** How the UI should read a change: a rate moves in points, a price in percent. */
  kind: 'rate' | 'price' | 'index';
  frequency: string;
  source: string;
  sourceUrl: string;
  priority: 0 | 1 | 2;
  value: number | null;
  asOf: string | null;
  change1D: Delta;
  change7D: Delta;
  change30D: Delta;
  changeYTD: Delta;
  change1Y: Delta;
  history: Point[];
  quality: Quality;
  note?: string;
};

type SeriesSpec = {
  id: string; fred: string; name: string; category: string; country: string;
  unit: string; kind: Metric['kind']; frequency: string; priority: 0 | 1 | 2;
  /** CPI is published as an index; what anyone means by "CPI" is the YoY. */
  yoy?: boolean;
};

/** Everything FRED can give us without a key. Ordered by how much it matters. */
export const FRED_SERIES: SeriesSpec[] = [
  { id: 'usdinr', fred: 'DEXINUS', name: 'USD / INR', category: 'FX', country: 'IN', unit: '₹', kind: 'price', frequency: 'Daily', priority: 0 },
  { id: 'us10y', fred: 'DGS10', name: 'US 10Y Treasury', category: 'Rates', country: 'US', unit: '%', kind: 'rate', frequency: 'Daily', priority: 0 },
  { id: 'fedfunds', fred: 'DFF', name: 'Fed Funds Rate', category: 'Rates', country: 'US', unit: '%', kind: 'rate', frequency: 'Daily', priority: 0 },
  { id: 'uscpi', fred: 'CPIAUCSL', name: 'US CPI (YoY)', category: 'Inflation', country: 'US', unit: '%', kind: 'rate', frequency: 'Monthly', priority: 0, yoy: true },
  { id: 'dxy', fred: 'DTWEXBGS', name: 'US Dollar Index', category: 'FX', country: 'US', unit: '', kind: 'index', frequency: 'Daily', priority: 0 },
  { id: 'spx', fred: 'SP500', name: 'S&P 500', category: 'Equities', country: 'US', unit: '', kind: 'index', frequency: 'Daily', priority: 0 },
  { id: 'vix', fred: 'VIXCLS', name: 'VIX', category: 'Equities', country: 'US', unit: '', kind: 'index', frequency: 'Daily', priority: 0 },
  { id: 'brent', fred: 'DCOILBRENTEU', name: 'Brent Crude', category: 'Commodities', country: 'GL', unit: '$', kind: 'price', frequency: 'Daily', priority: 0 },
  { id: 'us2y', fred: 'DGS2', name: 'US 2Y Treasury', category: 'Rates', country: 'US', unit: '%', kind: 'rate', frequency: 'Daily', priority: 1 },
  { id: 'us10y2y', fred: 'T10Y2Y', name: 'US 10Y – 2Y', category: 'Rates', country: 'US', unit: '%', kind: 'rate', frequency: 'Daily', priority: 1 },
  { id: 'wti', fred: 'DCOILWTICO', name: 'WTI Crude', category: 'Commodities', country: 'GL', unit: '$', kind: 'price', frequency: 'Daily', priority: 1 },
  { id: 'usunemp', fred: 'UNRATE', name: 'US Unemployment', category: 'Employment', country: 'US', unit: '%', kind: 'rate', frequency: 'Monthly', priority: 1 }
];

/** The ones with no free feed. The model fills these in, badged `estimated`. */
export const AI_METRICS = [
  { id: 'repo', name: 'RBI Repo Rate', category: 'Rates', country: 'IN', unit: '%', kind: 'rate' as const, frequency: 'Per policy', priority: 0 as const },
  { id: 'indiacpi', name: 'India CPI (YoY)', category: 'Inflation', country: 'IN', unit: '%', kind: 'rate' as const, frequency: 'Monthly', priority: 0 as const },
  { id: 'india10y', name: 'India 10Y G-Sec', category: 'Rates', country: 'IN', unit: '%', kind: 'rate' as const, frequency: 'Daily', priority: 0 as const },
  { id: 'nifty', name: 'NIFTY 50', category: 'Equities', country: 'IN', unit: '', kind: 'index' as const, frequency: 'Daily', priority: 0 as const },
  { id: 'indiavix', name: 'India VIX', category: 'Equities', country: 'IN', unit: '', kind: 'index' as const, frequency: 'Daily', priority: 0 as const },
  { id: 'gold', name: 'Gold', category: 'Commodities', country: 'GL', unit: '$/oz', kind: 'price' as const, frequency: 'Daily', priority: 0 as const },
  { id: 'silver', name: 'Silver', category: 'Commodities', country: 'GL', unit: '$/oz', kind: 'price' as const, frequency: 'Daily', priority: 0 as const }
];

/** A troy ounce in grams. Bullion is quoted per ounce and bought per gram. */
export const GRAMS_PER_TROY_OUNCE = 31.1034768;

/**
 * Dollars an ounce is the quote; rupees a gram is the thing you actually pay.
 * Returns null when there is no USD/INR to convert with — a half-converted
 * price is worse than no price.
 */
export function perGramINR(usdPerOunce: number | null, usdinr: number | null): number | null {
  if (usdPerOunce === null || usdinr === null || !usdinr) return null;
  return Math.round(((usdPerOunce * usdinr) / GRAMS_PER_TROY_OUNCE) * 100) / 100;
}

// ---------------------------------------------------------------- FRED

const FRED_CSV = 'https://fred.stlouisfed.org/graph/fredgraph.csv?id=';

/** FRED writes a missing observation as ".", which parses as NaN if you let it. */
export function parseFredCsv(text: string): Point[] {
  const out: Point[] = [];
  for (const line of text.split('\n').slice(1)) {
    const [d, raw] = line.trim().split(',');
    if (!d || !raw || raw === '.') continue;
    const v = Number(raw);
    if (!Number.isFinite(v)) continue;
    out.push({ d, v });
  }
  return out;
}

async function fetchSeries(spec: SeriesSpec): Promise<Point[]> {
  const res = await fetch(FRED_CSV + spec.fred, { cf: { cacheTtl: 3600 } } as RequestInit);
  if (!res.ok) return [];
  return parseFredCsv(await res.text());
}

// ---------------------------------------------------------------- maths

/** The last observation on or before a date — how a series is read historically. */
export function at(points: Point[], onOrBefore: string): Point | null {
  let found: Point | null = null;
  for (const p of points) {
    if (p.d <= onOrBefore) found = p;
    else break;
  }
  return found;
}

export function shiftDays(date: string, days: number): string {
  const d = new Date(date + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function delta(now: number, then: number | null): Delta {
  if (then === null || !Number.isFinite(then) || then === 0) return null;
  return { abs: round(now - then, 4), pct: round(((now - then) / Math.abs(then)) * 100, 3) };
}

function round(n: number, dp: number): number {
  const f = Math.pow(10, dp);
  return Math.round(n * f) / f;
}

/** Year-on-year of an index series, which is what "CPI" means in conversation. */
export function toYoY(points: Point[]): Point[] {
  const out: Point[] = [];
  for (let i = 12; i < points.length; i++) {
    const prev = points[i - 12].v;
    if (!prev) continue;
    out.push({ d: points[i].d, v: round(((points[i].v - prev) / prev) * 100, 2) });
  }
  return out;
}

/** All five changes, read off the series itself. */
export function derive(points: Point[], asOf: string): Pick<Metric,
  'value' | 'asOf' | 'change1D' | 'change7D' | 'change30D' | 'changeYTD' | 'change1Y'> {
  const cur = at(points, asOf);
  if (!cur) return { value: null, asOf: null, change1D: null, change7D: null, change30D: null, changeYTD: null, change1Y: null };
  const back = (days: number) => at(points, shiftDays(cur.d, -days))?.v ?? null;
  const jan1 = at(points, cur.d.slice(0, 4) + '-01-01')?.v ?? null;
  // The previous *observation*, not yesterday: a monthly series has no yesterday.
  const idx = points.findIndex((p) => p.d === cur.d);
  const prev = idx > 0 ? points[idx - 1].v : null;
  return {
    value: cur.v,
    asOf: cur.d,
    change1D: delta(cur.v, prev),
    change7D: delta(cur.v, back(7)),
    change30D: delta(cur.v, back(30)),
    changeYTD: delta(cur.v, jan1),
    change1Y: delta(cur.v, back(365))
  };
}

/** Trimmed for transport: five years of daily data is not a sparkline. */
export function trim(points: Point[], max = 400): Point[] {
  if (points.length <= max) return points;
  const step = points.length / max;
  const out: Point[] = [];
  for (let i = 0; i < max; i++) out.push(points[Math.floor(i * step)]);
  const last = points[points.length - 1];
  if (out[out.length - 1].d !== last.d) out.push(last);
  return out;
}

export async function loadFredMetrics(asOf: string): Promise<Metric[]> {
  const results = await Promise.all(
    FRED_SERIES.map(async (spec): Promise<Metric> => {
      let points: Point[] = [];
      try {
        points = await fetchSeries(spec);
      } catch {
        /* leave empty — the metric reports unavailable rather than guessing */
      }
      if (spec.yoy) points = toYoY(points);
      const d = derive(points, asOf);
      return {
        id: spec.id, name: spec.name, category: spec.category, country: spec.country,
        unit: spec.unit, kind: spec.kind, frequency: spec.frequency,
        source: 'FRED · St. Louis Fed',
        sourceUrl: `https://fred.stlouisfed.org/series/${spec.fred}`,
        priority: spec.priority,
        ...d,
        history: trim(points.filter((p) => p.d <= asOf)),
        quality: d.value === null ? 'unavailable' : 'verified'
      };
    })
  );
  return results;
}

// ---------------------------------------------------------------- regime

export type Score = { id: string; label: string; score: number; state: 'good' | 'watch' | 'risk' | 'info'; inputs: string[] };

function clamp(n: number): number { return Math.max(0, Math.min(100, Math.round(n))); }
function scale(v: number, lo: number, hi: number): number { return clamp(((v - lo) / (hi - lo)) * 100); }

/**
 * Analytical readings, not advice — every one names the numbers it came from so
 * the score can be argued with. Higher always means "more of the thing named".
 */
export function regime(byId: Record<string, Metric>): Score[] {
  const out: Score[] = [];
  const v = (id: string) => byId[id]?.value ?? null;
  const m30 = (id: string) => byId[id]?.change30D?.pct ?? null;

  const vix = v('vix');
  if (vix !== null) {
    out.push({
      id: 'globalRisk', label: 'Global risk', score: scale(vix, 11, 34),
      state: vix > 25 ? 'risk' : vix > 17 ? 'watch' : 'good',
      inputs: [`VIX ${vix.toFixed(2)}`]
    });
  }

  const usdinr30 = m30('usdinr');
  const dxy30 = m30('dxy');
  if (usdinr30 !== null || dxy30 !== null) {
    const s = clamp(50 + (usdinr30 ?? 0) * 12 + (dxy30 ?? 0) * 6);
    out.push({
      id: 'rupeePressure', label: 'Rupee pressure', score: s,
      state: s > 65 ? 'risk' : s > 55 ? 'watch' : 'good',
      inputs: [
        usdinr30 !== null ? `USD/INR ${usdinr30 > 0 ? '+' : ''}${usdinr30.toFixed(2)}% 1M` : '',
        dxy30 !== null ? `Dollar index ${dxy30 > 0 ? '+' : ''}${dxy30.toFixed(2)}% 1M` : ''
      ].filter(Boolean)
    });
  }

  const brent30 = m30('brent');
  const uscpi = v('uscpi');
  if (brent30 !== null || uscpi !== null) {
    const s = clamp(((uscpi ?? 2) / 6) * 60 + (brent30 ?? 0) * 1.5 + 20);
    out.push({
      id: 'inflation', label: 'Inflation pressure', score: s,
      state: s > 65 ? 'risk' : s > 50 ? 'watch' : 'good',
      inputs: [
        uscpi !== null ? `US CPI ${uscpi.toFixed(1)}% YoY` : '',
        brent30 !== null ? `Brent ${brent30 > 0 ? '+' : ''}${brent30.toFixed(1)}% 1M` : ''
      ].filter(Boolean)
    });
  }

  const spx30 = m30('spx');
  const spread = v('us10y2y');
  if (spx30 !== null || spread !== null) {
    const s = clamp(50 - (spx30 ?? 0) * 3 + (spread !== null && spread < 0 ? 25 : 0));
    out.push({
      id: 'marketRisk', label: 'Market stress', score: s,
      state: s > 65 ? 'risk' : s > 52 ? 'watch' : 'good',
      inputs: [
        spx30 !== null ? `S&P 500 ${spx30 > 0 ? '+' : ''}${spx30.toFixed(1)}% 1M` : '',
        spread !== null ? `10Y–2Y ${spread.toFixed(2)}${spread < 0 ? ' (inverted)' : ''}` : ''
      ].filter(Boolean)
    });
  }

  return out;
}

/** The compact table the brief is written from, so every claim traces to a row. */
export function briefTable(metrics: Metric[]): string {
  return metrics
    .filter((m) => m.value !== null)
    .map((m) => {
      const d1 = m.change1D ? `${m.change1D.pct > 0 ? '+' : ''}${m.change1D.pct.toFixed(2)}% 1D` : 'no 1D';
      const d30 = m.change30D ? `${m.change30D.pct > 0 ? '+' : ''}${m.change30D.pct.toFixed(2)}% 1M` : 'no 1M';
      return `${m.name}: ${m.value}${m.unit} (${d1}, ${d30}) [${m.quality}, as of ${m.asOf}]`;
    })
    .join('\n');
}
