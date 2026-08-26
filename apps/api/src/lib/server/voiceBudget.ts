import { nowISO, sql } from './db';

/**
 * The hard stop that keeps voice free.
 *
 * Cloudflare's 10,000 free neurons/day already cap this on the Workers Free
 * plan, but the account may be on Workers Paid for D1/R2 — where overage bills
 * rather than fails. So the Worker enforces its own ceiling and refuses before
 * ever reaching a billable neuron. Two independent stops, deliberately.
 *
 * @cf/deepgram/aura-2-en costs 1363.64 neurons per 1,000 characters, so the
 * free 10,000 neurons buy ~7,333 characters. 7,000 leaves headroom.
 *
 * The neuron allowance belongs to the ACCOUNT, not to a person. A per-user cap
 * alone therefore protects nothing the moment there is more than one user:
 * two accounts each spending their own 7,000 characters is 19,090 neurons, and
 * the second one is billed. So the account-wide ceiling is the real stop, and
 * the per-user cap sits underneath it purely so one talkative account cannot
 * drink the whole day before anyone else wakes up.
 */
export const VOICE_ACCOUNT_DAILY_CHAR_CAP = 7000;

/** One account's share of the day. Never above the account-wide ceiling. */
export const VOICE_DAILY_CHAR_CAP = 4000;

/** The UTC calendar day an instant falls in. Workers AI resets at 00:00 UTC. */
export function utcDayKey(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10);
}

/**
 * Whether one synthesis request fits in what is left of the day.
 *
 * All-or-nothing: a request that would overshoot spends nothing rather than
 * being clipped, because half a spoken sentence is worse than none.
 */
export function budgetDecision(
  used: number,
  request: number,
  cap: number = VOICE_DAILY_CHAR_CAP
): { allowed: boolean; remaining: number } {
  const left = Math.max(0, cap - used);
  if (request > left) return { allowed: false, remaining: left };
  return { allowed: true, remaining: left - request };
}


// One idempotent DDL per server process, mirroring `ensureAiTable` in ai.ts —
// so a fresh local D1 works without a manual migration step.
// A boolean, NOT a shared promise. Memoizing the promise meant a second
// concurrent request could await I/O belonging to the first, which the Workers
// runtime refuses outright ("Cannot perform I/O on behalf of a different
// request") — and because the inner promise had not rejected, the catch never
// reset the guard, so the failure stuck for the life of the isolate. Each
// request now awaits its own DDL; `create table if not exists` is idempotent
// and costs nothing once the table is there.
let ensured = false;
async function ensureVoiceTable(): Promise<void> {
  if (ensured) return;
  await sql`
    create table if not exists voice_budget (
      user_id    integer not null,
      day        text not null,
      chars      integer not null default 0,
      updated_at text not null,
      primary key (user_id, day)
    )`;
  ensured = true;
}

/**
 * Spend `chars` of today's allowance, or refuse.
 *
 * Read-then-write rather than a single atomic statement: this is a single-user
 * app and the caller is one phone speaking one sentence at a time, so the race
 * window is theoretical. The all-or-nothing rule in `budgetDecision` means the
 * worst case of a lost update is a few hundred characters of overspend against
 * a cap that already sits below the free allowance.
 */
export async function reserveVoiceChars(
  userId: number,
  chars: number
): Promise<{ allowed: boolean; remaining: number }> {
  await ensureVoiceTable();
  const now = nowISO();
  const day = utcDayKey(now);

  // Both ledgers for the day in one read: this account's spend, and everyone's.
  const rows = await sql`
    select
      coalesce(sum(case when user_id = ${userId} then chars end), 0) as mine,
      coalesce(sum(chars), 0)                                        as everyone
    from voice_budget where day = ${day}`;
  const used = Number(rows[0]?.mine ?? 0);
  const usedByAll = Number(rows[0]?.everyone ?? 0);

  // Refuse on whichever ceiling binds first, and report the tighter remainder
  // so the client is told the truth about what it can still ask for.
  const mine = budgetDecision(used, chars);
  const account = budgetDecision(usedByAll, chars, VOICE_ACCOUNT_DAILY_CHAR_CAP);
  const decision = {
    allowed: mine.allowed && account.allowed,
    remaining: Math.min(mine.remaining, account.remaining)
  };
  if (!decision.allowed) return decision;

  await sql`
    insert into voice_budget (user_id, day, chars, updated_at)
    values (${userId}, ${day}, ${used + chars}, ${now})
    on conflict (user_id, day) do update set chars = excluded.chars, updated_at = excluded.updated_at`;

  return decision;
}
