import { env } from '$env/dynamic/private';
import type { LanguageModel } from 'ai';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { createAnthropic } from '@ai-sdk/anthropic';
import { createOpenAI } from '@ai-sdk/openai';
import { sql } from './db';
import { decryptSecret } from './secrets';
import type { ProviderId } from './modelCatalog';

/**
 * Resolves which model an AI route should use for the logged-in user. Routing lives
 * in app_state (myos.ai.routes) as a per-feature map of {keyId, model}; the secret
 * is decrypted from ai_credentials. Anything unrouted — or any failure — falls back
 * to the server's env Gemini config, so the app keeps working with zero setup.
 */

export type Feature = 'chat' | 'analysis' | 'vision' | 'parse' | 'suggest' | 'plan' | 'news';

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
// prod already has it via db/schema.sql. Memoized to one DDL per server process.
let ensured: Promise<void> | null = null;
export function ensureAiTable(): Promise<void> {
  if (!ensured) {
    ensured = (async () => {
      await sql`
        create table if not exists ai_credentials (
          id         serial primary key,
          user_id    integer not null references users(id) on delete cascade,
          provider   text not null,
          label      text not null,
          secret     text not null,
          masked     text not null,
          enabled    boolean not null default true,
          models     jsonb not null default '[]'::jsonb,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )`;
      await sql`create index if not exists ai_credentials_user_idx on ai_credentials(user_id)`;
    })().catch((e) => {
      ensured = null; // let a later request retry if this one lost the race / failed
      throw e;
    });
  }
  return ensured;
}

async function loadRouting(userId: number): Promise<Routing> {
  const rows = await sql`select value from app_state where user_id = ${userId} and key = 'myos.ai.routes'`;
  return rows.length ? (rows[0].value as Routing) : {};
}

function buildModel(provider: ProviderId, apiKey: string, model: string): Resolved {
  if (provider === 'anthropic') {
    return { model: createAnthropic({ apiKey })(model), providerId: 'anthropic' };
  }
  if (provider === 'openai') {
    return { model: createOpenAI({ apiKey })(model), providerId: 'openai' };
  }
  const google = createGoogleGenerativeAI({ apiKey });
  return { model: google(model), providerId: 'gemini', google };
}

/** The env-configured Gemini fallback — mirrors each route's prior default. */
function envFallback(feature: Feature): Resolved {
  const key = feature === 'chat' ? env.GEMINI_CHAT_API_KEY ?? env.GEMINI_API_KEY : env.GEMINI_API_KEY;
  if (!key) throw new Error('AI is not configured on the server');
  let model: string;
  if (feature === 'chat') {
    model = env.GEMINI_CHAT_MODEL ?? 'gemini-flash-latest';
  } else if (feature === 'analysis' || feature === 'plan') {
    model = env.GEMINI_REASONING_MODEL ?? env.GEMINI_MODEL ?? 'gemini-flash-latest';
  } else {
    model = env.GEMINI_MODEL ?? 'gemini-flash-latest';
  }
  return buildModel('gemini', key, model);
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

  return envFallback(feature);
}
