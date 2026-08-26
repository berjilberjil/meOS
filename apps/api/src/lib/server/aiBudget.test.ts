import { describe, expect, it } from 'vitest';
import {
  AI_ACCOUNT_DAILY_CALLS,
  AI_USER_DAILY_CALLS,
  callDecision,
  utcDayKey
} from './aiBudget';

describe('the shared AI key ceilings', () => {
  // The quota belongs to the key, not to a person, so a per-user cap alone
  // protects nothing once there is more than one user. Any registered account
  // could loop /api/news — no request body needed — and drain the owner's
  // Gemini quota for everybody.
  it("keeps one account's share under the account-wide allowance", () => {
    expect(AI_USER_DAILY_CALLS).toBeLessThanOrEqual(AI_ACCOUNT_DAILY_CALLS);
  });

  it('allows a call while there is room', () => {
    expect(callDecision(0, AI_USER_DAILY_CALLS)).toEqual({
      allowed: true,
      remaining: AI_USER_DAILY_CALLS
    });
  });

  it('refuses the call that would exceed the cap', () => {
    expect(callDecision(AI_USER_DAILY_CALLS, AI_USER_DAILY_CALLS)).toEqual({
      allowed: false,
      remaining: 0
    });
  });

  it('never reports negative remaining if usage somehow overshot', () => {
    expect(callDecision(AI_USER_DAILY_CALLS + 50, AI_USER_DAILY_CALLS)).toEqual({
      allowed: false,
      remaining: 0
    });
  });

  it('refuses on the account ceiling even when this user has room', () => {
    const mine = callDecision(0, AI_USER_DAILY_CALLS);
    const account = callDecision(AI_ACCOUNT_DAILY_CALLS, AI_ACCOUNT_DAILY_CALLS);
    expect(mine.allowed).toBe(true);
    expect(mine.allowed && account.allowed).toBe(false);
  });
});

describe('utcDayKey', () => {
  it('rolls at midnight UTC, not local midnight', () => {
    expect(utcDayKey('2026-08-22T23:30:00.000Z')).toBe('2026-08-22');
    expect(utcDayKey('2026-08-23T00:00:00.000Z')).toBe('2026-08-23');
  });
});
