import { describe, expect, it } from 'vitest';
import {
  VOICE_ACCOUNT_DAILY_CHAR_CAP,
  VOICE_DAILY_CHAR_CAP,
  budgetDecision,
  combineCeilings,
  utcDayKey
} from './voiceBudget';

describe('utcDayKey', () => {
  it('takes the UTC calendar day, not the local one', () => {
    expect(utcDayKey('2026-08-22T00:15:00.000Z')).toBe('2026-08-22');
    expect(utcDayKey('2026-08-22T23:59:59.999Z')).toBe('2026-08-22');
    expect(utcDayKey('2026-08-23T00:00:00.000Z')).toBe('2026-08-23');
  });

  it('rolls at midnight UTC even when IST is already tomorrow', () => {
    // 05:00 IST on the 23rd is 23:30 UTC on the 22nd — still the 22nd's budget.
    expect(utcDayKey('2026-08-22T23:30:00.000Z')).toBe('2026-08-22');
  });
});

describe('budgetDecision', () => {
  it('allows a request that fits', () => {
    expect(budgetDecision(0, 100)).toEqual({ allowed: true, remaining: VOICE_DAILY_CHAR_CAP - 100 });
  });

  it('allows a request that exactly exhausts the cap', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP - 50, 50)).toEqual({ allowed: true, remaining: 0 });
  });

  it('refuses a request that would overshoot, and spends nothing', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP - 10, 50)).toEqual({ allowed: false, remaining: 10 });
  });

  it('refuses once the cap is already gone', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP, 1)).toEqual({ allowed: false, remaining: 0 });
  });

  it('never reports negative remaining even if usage somehow overshot', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP + 500, 1)).toEqual({ allowed: false, remaining: 0 });
  });

  it('honours an explicit cap', () => {
    expect(budgetDecision(0, 100, 120)).toEqual({ allowed: true, remaining: 20 });
  });
});

describe('the account-wide ceiling', () => {
  // These call combineCeilings — the rule reserveVoiceChars actually applies.
  // The previous versions rebuilt the arithmetic inside the test, so they would
  // have passed unchanged against the code that had no account ceiling at all.
  it("keeps one account's share at or under the account-wide allowance", () => {
    expect(VOICE_DAILY_CHAR_CAP).toBeLessThanOrEqual(VOICE_ACCOUNT_DAILY_CHAR_CAP);
  });

  it('refuses on the account ceiling even when this user has spent nothing', () => {
    const d = combineCeilings(0, VOICE_ACCOUNT_DAILY_CHAR_CAP - 100, 500);
    expect(d.allowed).toBe(false);
    expect(d.remaining).toBe(100);
  });

  it('refuses on the per-user ceiling even when the account has room', () => {
    const d = combineCeilings(VOICE_DAILY_CHAR_CAP, 0, 1);
    expect(d.allowed).toBe(false);
  });

  it('allows a request when neither ceiling binds', () => {
    const d = combineCeilings(0, 1000, 500);
    expect(d.allowed).toBe(true);
    expect(d.remaining).toBe(
      Math.min(VOICE_DAILY_CHAR_CAP - 500, VOICE_ACCOUNT_DAILY_CHAR_CAP - 1500)
    );
  });

  it('reports the tighter of the two remainders', () => {
    const d = combineCeilings(0, VOICE_ACCOUNT_DAILY_CHAR_CAP - 600, 100);
    expect(d.remaining).toBe(500);
  });
});
