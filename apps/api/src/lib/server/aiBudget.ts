import { nowISO, sql } from './db';

/**
 * The stop that keeps the shared AI key free.
 *
 * Most users bring no key of their own, so `resolveModel` falls back to the
 * server's `GEMINI_API_KEY` — and nothing bounded that. One registered account
 * looping `POST /api/news` (which needs no request body, and makes two Gemini
 * calls, one Google-Search-grounded) exhausted the owner's quota for everybody,
 * and billed it if that key sat on a billing-enabled project. `/api/macro` is
 * worse: three model calls plus twelve FRED fetches per refresh.
 *
 * Two ceilings, for the same reason `voiceBudget` has two: the per-account share
 * stops one talkative user drinking the day before anyone else wakes up, and the
 * account-wide ceiling is what actually protects the quota, because the quota
 * belongs to the key, not to a person.
 */
export const AI_ACCOUNT_DAILY_CALLS = 1200;
export const AI_USER_DAILY_CALLS = 300;

/** The UTC calendar day an instant falls in — provider quotas reset at 00:00 UTC. */
export function utcDayKey(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10);
}

/** Whether one more call fits under a ceiling. */
export function callDecision(
  used: number,
  cap: number
): { allowed: boolean; remaining: number } {
  const left = Math.max(0, cap - used);
  return { allowed: left > 0, remaining: left };
}

let ensured = false;
async function ensureTable(): Promise<void> {
  if (ensured) return;
  await sql`
    create table if not exists ai_budget (
      user_id    integer not null,
      day        text not null,
      calls      integer not null default 0,
      updated_at text not null,
      primary key (user_id, day)
    )`;
  ensured = true;
}

/**
 * Spend one call of today's shared-key allowance, or refuse.
 *
 * Only called when the request is about to use the SERVER's key. A user who has
 * configured their own key is spending their own quota and is not metered here.
 *
 * Read-then-write, like `reserveVoiceChars`: the race window costs at most a
 * handful of calls against a ceiling set well below the real limit.
 */
export async function reserveAICall(
  userId: number
): Promise<{ allowed: boolean; remaining: number }> {
  await ensureTable();
  const now = nowISO();
  const day = utcDayKey(now);

  const rows = await sql`
    select
      coalesce(sum(case when user_id = ${userId} then calls end), 0) as mine,
      coalesce(sum(calls), 0)                                       as everyone
    from ai_budget where day = ${day}`;
  const mine = Number(rows[0]?.mine ?? 0);
  const everyone = Number(rows[0]?.everyone ?? 0);

  const perUser = callDecision(mine, AI_USER_DAILY_CALLS);
  const account = callDecision(everyone, AI_ACCOUNT_DAILY_CALLS);
  const decision = {
    allowed: perUser.allowed && account.allowed,
    remaining: Math.min(perUser.remaining, account.remaining)
  };
  if (!decision.allowed) return decision;

  await sql`
    insert into ai_budget (user_id, day, calls, updated_at)
    values (${userId}, ${day}, ${mine + 1}, ${now})
    on conflict (user_id, day) do update set calls = excluded.calls, updated_at = excluded.updated_at`;

  return { allowed: true, remaining: decision.remaining - 1 };
}
