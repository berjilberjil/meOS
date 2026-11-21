import { describe, expect, it } from 'vitest';
import {
  CURRENT_STATE_KEYS,
  LEGACY_STATE_KEYS,
  MAX_STATE_VALUE_BYTES,
  STATE_KEYS,
  isAllowedStateKey,
  isSealedEnvelope,
  validateCryptoMeta
} from './stateKeys';

describe('state key allowlist', () => {
  it('accepts every current module key', () => {
    for (const key of CURRENT_STATE_KEYS) expect(isAllowedStateKey(key)).toBe(true);
  });

  it('accepts legacy keys so older installed builds keep syncing', () => {
    for (const key of LEGACY_STATE_KEYS) expect(isAllowedStateKey(key)).toBe(true);
  });

  it('includes the recycle bin and the reserved finance key', () => {
    // `meos.trash` was written by the app while missing from the route-level
    // allowlist, so every bin push failed with 400 and silently stopped sync.
    expect(STATE_KEYS.has('meos.trash')).toBe(true);
    expect(STATE_KEYS.has('meos.finance')).toBe(true);
  });

  it('accepts finance history shards but nothing else with a suffix', () => {
    expect(isAllowedStateKey('meos.finance.tx.2024')).toBe(true);
    expect(isAllowedStateKey('meos.finance.tx.2024.2')).toBe(true);
    expect(isAllowedStateKey('meos.finance.audit.2024')).toBe(true);
    expect(isAllowedStateKey('meos.finance.import.a1b2')).toBe(true);
    expect(isAllowedStateKey('meos.finance..tx')).toBe(false);
    expect(isAllowedStateKey('meos.notes.2024')).toBe(false);
  });

  it('rejects unknown and path-like keys', () => {
    expect(isAllowedStateKey('meos.unknown')).toBe(false);
    expect(isAllowedStateKey('../meos.notes')).toBe(false);
    expect(isAllowedStateKey('')).toBe(false);
  });

  it('keeps the cap below D1’s 2 MB row limit', () => {
    expect(MAX_STATE_VALUE_BYTES).toBeLessThan(2_000_000);
  });
});

describe('encrypted-state shape checks', () => {
  const salt = Buffer.alloc(16, 7).toString('base64');
  const wrap = Buffer.alloc(32, 9).toString('base64');
  const validMeta = {
    v: 1,
    kdf: 'pbkdf2-sha256',
    iterations: 600_000,
    passSalt: salt,
    recoverySalt: salt,
    wrappedByPass: wrap,
    wrappedByRecovery: wrap,
    check: wrap,
    dataVersion: 2
  };

  it('accepts a well-formed vault metadata object', () => {
    expect(validateCryptoMeta(validMeta)).toBeNull();
  });

  it('rejects plaintext, unknown KDFs, absurd work factors and junk', () => {
    expect(validateCryptoMeta('hello')).toMatch(/object/);
    expect(validateCryptoMeta({ ...validMeta, kdf: 'md5' })).toMatch(/pbkdf2/);
    expect(validateCryptoMeta({ ...validMeta, iterations: 1 })).toMatch(/iterations/);
    expect(validateCryptoMeta({ ...validMeta, iterations: 99_000_000 })).toMatch(/iterations/);
    expect(validateCryptoMeta({ ...validMeta, passSalt: 'not base64' })).toMatch(/passSalt/);
    expect(validateCryptoMeta({ ...validMeta, wrappedByPass: 'AA==' })).toMatch(/wrappedByPass/);
    expect(validateCryptoMeta({ ...validMeta, dataVersion: 999 })).toMatch(/dataVersion/);
  });

  it('accepts only a base64 sealed envelope of plausible length', () => {
    expect(isSealedEnvelope({ v: 1, ct: Buffer.alloc(64).toString('base64') })).toBe(true);
    expect(isSealedEnvelope({ v: 2, ct: Buffer.alloc(64).toString('base64') })).toBe(true);
    expect(isSealedEnvelope({ v: 1, ct: 'short' })).toBe(false);
    expect(isSealedEnvelope({ v: 99, ct: Buffer.alloc(64).toString('base64') })).toBe(false);
    expect(isSealedEnvelope({ ct: Buffer.alloc(64).toString('base64') })).toBe(false);
    expect(isSealedEnvelope('plaintext')).toBe(false);
  });
});
