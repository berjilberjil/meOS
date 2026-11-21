import { describe, expect, it } from 'vitest';
import { base64DecodedBytes, decodeBase64Capped, isMediaId } from './media';

describe('media ids', () => {
  it('accepts the ids the app generates', () => {
    expect(isMediaId('2026-08-15__manual-123')).toBe(true);
    expect(isMediaId('a1b2c3d4-e5f6')).toBe(true);
  });

  it('rejects traversal and separators', () => {
    expect(isMediaId('.')).toBe(false);
    expect(isMediaId('..')).toBe(false);
    expect(isMediaId('../secret')).toBe(false);
    expect(isMediaId('a/b')).toBe(false);
    expect(isMediaId('')).toBe(false);
  });
});

describe('base64 caps', () => {
  it('computes decoded length without allocating', () => {
    expect(base64DecodedBytes(Buffer.from('hello').toString('base64'))).toBe(5);
    expect(base64DecodedBytes('')).toBeNull();
    expect(base64DecodedBytes('not base64!')).toBeNull();
  });

  it('refuses before decoding when the result would be too large', () => {
    const tenBytes = Buffer.from('0123456789').toString('base64');
    expect(decodeBase64Capped(tenBytes, 9)).toBeNull();
    expect(decodeBase64Capped(tenBytes, 10)?.toString()).toBe('0123456789');
  });
});
