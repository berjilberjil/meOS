import { describe, expect, it } from 'vitest';
import { scryptSync } from 'node:crypto';
import {
  attemptsAllowed,
  hashPassword,
  LOGIN_MAX_ATTEMPTS,
  signupAllowed,
  verifyPassword
} from './auth';

describe('signup gate', () => {
  it('allows the first owner on an empty database', () => {
    expect(signupAllowed(0, undefined)).toBe(true);
  });

  it('closes signup once an account exists', () => {
    expect(signupAllowed(1, undefined)).toBe(false);
  });

  it('allows an explicit operator override only for the exact string true', () => {
    expect(signupAllowed(1, 'true')).toBe(true);
    expect(signupAllowed(1, 'TRUE')).toBe(false);
    expect(signupAllowed(1, 'yes')).toBe(false);
  });
});

describe('login throttle arithmetic', () => {
  it('judges each scope independently', () => {
    expect(attemptsAllowed(0, LOGIN_MAX_ATTEMPTS - 1)).toBe(true);
    expect(attemptsAllowed(LOGIN_MAX_ATTEMPTS - 1, 0)).toBe(true);
    expect(attemptsAllowed(LOGIN_MAX_ATTEMPTS, 0)).toBe(false);
    expect(attemptsAllowed(0, LOGIN_MAX_ATTEMPTS)).toBe(false);
  });
});

describe('password hashing', () => {
  it('round-trips a v2 PBKDF2 hash', async () => {
    const stored = await hashPassword('correct horse battery staple');
    expect(stored.startsWith('v2:')).toBe(true);
    expect(await verifyPassword('correct horse battery staple', stored)).toBe(true);
    expect(await verifyPassword('wrong', stored)).toBe(false);
  });

  it('still verifies a legacy scrypt hash', async () => {
    // Format written by the pre-Workers backend: `<saltHex>:<hashHex>`.
    const salt = '00112233445566778899aabbccddeeff';
    const legacy = `${salt}:${scryptSync('legacy-pass', salt, 64).toString('hex')}`;
    expect(await verifyPassword('legacy-pass', legacy)).toBe(true);
    expect(await verifyPassword('wrong', legacy)).toBe(false);
  });

  it('rejects a malformed hash instead of throwing', async () => {
    expect(await verifyPassword('x', 'not-a-hash')).toBe(false);
  });
});
