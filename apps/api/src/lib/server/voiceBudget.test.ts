import { describe, expect, it } from 'vitest';
import {
  VOICE_ACCOUNT_DAILY_CHAR_CAP,
  VOICE_DAILY_CHAR_CAP,
  budgetDecision,
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
  // The neuron allowance belongs to the Cloudflare account, not to a person, so
  // a per-user cap alone stopped protecting anything the moment a second user
  // existed: two accounts spending 7,000 characters each is 19,090 neurons
  // against a free 10,000, and the overage bills.
  it("keeps one account's share at or under the account-wide allowance", () => {
    expect(VOICE_DAILY_CHAR_CAP).toBeLessThanOrEqual(VOICE_ACCOUNT_DAILY_CHAR_CAP);
  });

  it('refuses on the account ceiling even when this user has room left', () => {
    const mine = budgetDecision(0, 500);
    const account = budgetDecision(VOICE_ACCOUNT_DAILY_CHAR_CAP - 100, 500, VOICE_ACCOUNT_DAILY_CHAR_CAP);
    expect(mine.allowed).toBe(true);
    expect(account.allowed).toBe(false);
    // reserveVoiceChars combines them: refused, and reporting the tighter figure.
    expect(mine.allowed && account.allowed).toBe(false);
    expect(Math.min(mine.remaining, account.remaining)).toBe(100);
  });

  it('still allows a normal request when neither ceiling binds', () => {
    const mine = budgetDecision(0, 500);
    const account = budgetDecision(1000, 500, VOICE_ACCOUNT_DAILY_CHAR_CAP);
    expect(mine.allowed && account.allowed).toBe(true);
    expect(Math.min(mine.remaining, account.remaining))
      .toBe(Math.min(VOICE_DAILY_CHAR_CAP - 500, VOICE_ACCOUNT_DAILY_CHAR_CAP - 1500));
  });
});
