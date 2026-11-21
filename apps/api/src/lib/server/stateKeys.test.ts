import { describe, expect, it } from 'vitest';
import {
  CURRENT_STATE_KEYS,
  LEGACY_STATE_KEYS,
  MAX_STATE_VALUE_BYTES,
  STATE_KEYS,
  isAllowedStateKey
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
