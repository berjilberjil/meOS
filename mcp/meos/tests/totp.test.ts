import test from 'node:test';
import assert from 'node:assert/strict';
import { totp } from '../src/auth/totp.ts';

// RFC 6238 SHA-1 vector: ASCII "12345678901234567890", 8-digit output is
// 94287082 at time 59; the 6-digit truncation is 287082.
const SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

test('gateway TOTP matches the RFC 6238 vector', () => {
  assert.equal(totp(SECRET, 59_000), '287082');
  assert.notEqual(totp(SECRET, 89_000), '000000');
});

test('gateway TOTP changes every 30 seconds', () => {
  assert.notEqual(totp(SECRET, 59_000), totp(SECRET, 119_000));
});
