import { env } from '$env/dynamic/private';
import type { LanguageModel } from 'ai';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { createAnthropic } from '@ai-sdk/anthropic';
import { createOpenAI } from '@ai-sdk/openai';
import { reserveAICall } from './aiBudget';
import { sql, nowISO } from './db';
import { decryptSecret } from './secrets';
import type { ProviderId } from './modelCatalog';

/**
 * Resolves which model an AI route should use for the logged-in user. Routing lives
 * in app_state (meos.ai.routes, formerly myos.ai.routes) as a per-feature map of
 * {keyId, model}; the secret is decrypted from ai_credentials. Anything unrouted —
 * or any failure — falls back to the server's env Gemini config, so the app keeps
 * working with zero setup.
 */

export type Feature = 'chat' | 'vision' | 'parse' | 'suggest' | 'plan' | 'news';

export interface Resolved {
  model: LanguageModel;
  providerId: ProviderId;
  /** Present only for Gemini — the news route needs it for google.tools.googleSearch. */
  google?: ReturnType<typeof createGoogleGenerativeAI>;
}

interface RouteRef {
  keyId: number;
  model: string;
}
interface Routing {
  default?: RouteRef;
  features?: Partial<Record<Feature, RouteRef>>;
}

// One-time idempotent table guard so dev (localhost) works without a manual psql;
// prod already has it via db/schema.sql.
// A boolean, NOT a shared promise. Memoizing the promise meant a second
// concurrent request could await I/O belonging to the first, which the Workers
// runtime refuses outright ("Cannot perform I/O on behalf of a different
// request") — and because the inner promise had not rejected, the catch never
// reset the guard, so the failure stuck for the life of the isolate. Each
// request now awaits its own DDL; `create table if not exists` is idempotent
// and costs nothing once the table is there.
let ensured = false;
export async function ensureAiTable(): Promise<void> {
  if (ensured) return;
  await sql`
    create table if not exists ai_credentials (
      id         integer primary key autoincrement,
      user_id    integer not null references users(id) on delete cascade,
      provider   text not null,
      label      text not null,
      secret     text not null,
      masked     text not null,
      enabled    integer not null default 1,
      models     text not null default '[]',
      created_at text not null default (datetime('now')),
      updated_at text not null default (datetime('now'))
    )`;
  await sql`create index if not exists ai_credentials_user_idx on ai_credentials(user_id)`;
  ensured = true;
}

async function loadRouting(userId: number): Promise<Routing> {
  const rows = await sql`select value from app_state where user_id = ${userId} and key = 'meos.ai.routes'`;
  if (rows.length) return rows[0].value as Routing;
  // Legacy MyOS key — read once, copy forward, keep serving.
  const legacy = await sql`select value from app_state where user_id = ${userId} and key = 'myos.ai.routes'`;
  if (!legacy.length) return {};
  await sql`insert into app_state (user_id, key, value, updated_at)
    values (${userId}, 'meos.ai.routes', ${legacy[0].value}, ${nowISO()})
    on conflict (user_id, key) do nothing`;
  return legacy[0].value as Routing;
}

/** Google retired the Gemini 1.x and 2.0 families — map any of them (from env or a
 *  user's saved route) to the rolling latest flash so the app self-heals without
 *  per-user reconfiguration. Current models pass through untouched. */
function normalizeGemini(model: string): string {
  const m = model.trim().replace(/^models\//, '');
  if (/^gemini-(1\.0|1\.5|2\.0)/.test(m) || m === 'gemini-pro') return 'gemini-flash-latest';
  return m;
}

function buildModel(provider: ProviderId, apiKey: string, model: string): Resolved {
  if (provider === 'anthropic') {
    return { model: createAnthropic({ apiKey })(model), providerId: 'anthropic' };
  }
  if (provider === 'openai') {
    return { model: createOpenAI({ apiKey })(model), providerId: 'openai' };
  }
  const google = createGoogleGenerativeAI({ apiKey });
  return { model: google(normalizeGemini(model)), providerId: 'gemini', google };
}

/** The env-configured Gemini fallback — mirrors each route's prior default. */
function envFallback(feature: Feature): Resolved {
  const key = feature === 'chat' ? env.GEMINI_CHAT_API_KEY ?? env.GEMINI_API_KEY : env.GEMINI_API_KEY;
  if (!key) throw new Error('AI is not configured on the server');
  let model: string;
  if (feature === 'chat') {
    // Chat deliberately does NOT inherit GEMINI_MODEL (the cheap classification
    // default). It is the one feature where reasoning quality is the product —
    // and with tools in play, picking the right tool is itself a reasoning task
    // that the -lite tier is measurably bad at. Still free tier, still Gemini.
    // Set GEMINI_CHAT_MODEL to override.
    model = env.GEMINI_CHAT_MODEL ?? 'gemini-flash-latest';
  } else if (feature === 'plan') {
    model = env.GEMINI_REASONING_MODEL ?? env.GEMINI_MODEL ?? 'gemini-flash-latest';
  } else {
    model = env.GEMINI_MODEL ?? 'gemini-3.1-flash-lite';
  }
  return buildModel('gemini', key, model);
}

export class AIBudgetExhausted extends Error {
  constructor() {
    super("The shared AI allowance for today is used up. Add your own key in Settings → AI providers.");
    this.name = 'AIBudgetExhausted';
  }
}

export async function resolveModel(feature: Feature, userId: number): Promise<Resolved> {
  await ensureAiTable();

  let ref: RouteRef | undefined;
  try {
    const routing = await loadRouting(userId);
    ref = routing.features?.[feature] ?? routing.default;
  } catch {
    ref = undefined;
  }

  if (ref?.keyId && ref.model) {
    const rows = await sql`
      select provider, secret, enabled from ai_credentials
      where id = ${ref.keyId} and user_id = ${userId}`;
    if (rows.length && rows[0].enabled) {
      const provider = rows[0].provider as ProviderId;
      // News depends on Google Search grounding — only Gemini can do it. If routed to
      // another provider, ignore the route and use the Gemini env fallback instead.
      const grounded = feature === 'news' && provider !== 'gemini';
      if (!grounded) {
        try {
          const apiKey = decryptSecret(rows[0].secret as string);
          return buildModel(provider, apiKey, ref.model);
        } catch {
          /* decrypt failed (master key changed?) — fall through to env */
        }
      }
    }
  }

  // Falling back to the SERVER's key — so this call is metered. A user running
  // on their own key above never reaches here and is never charged against it.
  const budget = await reserveAICall(userId);
  if (!budget.allowed) throw new AIBudgetExhausted();
  return envFallback(feature);
}
