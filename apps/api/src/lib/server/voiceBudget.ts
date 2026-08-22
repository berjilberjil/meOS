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
 */
export const VOICE_DAILY_CHAR_CAP = 7000;

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
let ensured: Promise<void> | null = null;
function ensureVoiceTable(): Promise<void> {
  if (!ensured) {
    ensured = (async () => {
      await sql`
        create table if not exists voice_budget (
          user_id    integer not null,
          day        text not null,
          chars      integer not null default 0,
          updated_at text not null,
          primary key (user_id, day)
        )`;
    })().catch((e) => {
      ensured = null; // let a later request retry
      throw e;
    });
  }
  return ensured;
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

  const rows = await sql`
    select chars from voice_budget where user_id = ${userId} and day = ${day}`;
  const used = rows.length ? Number(rows[0].chars) : 0;

  const decision = budgetDecision(used, chars);
  if (!decision.allowed) return decision;

  await sql`
    insert into voice_budget (user_id, day, chars, updated_at)
    values (${userId}, ${day}, ${used + chars}, ${now})
    on conflict (user_id, day) do update set chars = excluded.chars, updated_at = excluded.updated_at`;

  return decision;
}
