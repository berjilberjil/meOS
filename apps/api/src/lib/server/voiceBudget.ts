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
