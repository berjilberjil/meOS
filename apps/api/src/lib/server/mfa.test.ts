import { describe, expect, it } from 'vitest';
import { newTotpSecret, normalizeRecoveryCode, verifyTotp } from './mfa';

// RFC 6238 test secret for SHA-1: ASCII "12345678901234567890".
const RFC_SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

describe('TOTP', () => {
  it('matches the RFC 6238 SHA-1 vector (6-digit truncation)', async () => {
    // At Unix time 59 the RFC's 8-digit code is 94287082; the 6-digit form is 287082.
    expect(await verifyTotp(RFC_SECRET, '287082', 59_000)).toBe(true);
    expect(await verifyTotp(RFC_SECRET, '287083', 59_000)).toBe(false);
  });

  it('accepts one 30-second step of clock skew in either direction', async () => {
    expect(await verifyTotp(RFC_SECRET, '287082', 89_000)).toBe(true);
    expect(await verifyTotp(RFC_SECRET, '287082', 29_000)).toBe(true);
    expect(await verifyTotp(RFC_SECRET, '287082', 200_000)).toBe(false);
  });

  it('issues 20 random bytes as base32 and normalizes recovery codes', () => {
    const a = newTotpSecret();
    const b = newTotpSecret();
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[A-Z2-7]{32}$/);
    expect(normalizeRecoveryCode('abcd-efgh')).toBe('ABCDEFGH');
    expect(normalizeRecoveryCode('O0I1L')).toBe('00111');
  });
});
