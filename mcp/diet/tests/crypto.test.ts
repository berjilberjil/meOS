import { describe, expect, test } from 'bun:test';
import { deriveKey, newSalt, open, openValue, seal, sealValue } from '../src/crypto';

const plain = Buffer.from('{"txns":[{"amount":200,"cat":"auto"}]}');

describe('vault crypto', () => {
	test('seal hides plaintext and open restores it', async () => {
		const key = await deriveKey('correct-pass-123', newSalt(), 10_000);
		const ct = seal(plain, key, Buffer.from('myos.finance'));
		expect(ct.includes('auto')).toBe(false);
		expect(ct.includes('200')).toBe(false);
		const back = open(ct, key, Buffer.from('myos.finance'));
		expect(back.equals(plain)).toBe(true);
	});

	test('wrong AAD / key fails', async () => {
		const key = await deriveKey('pass-pass-pass', newSalt(), 10_000);
		const ct = seal(plain, key, Buffer.from('myos.finance'));
		expect(() => open(ct, key, Buffer.from('myos.journal'))).toThrow();
		const other = await deriveKey('other-pass-word', newSalt(), 10_000);
		expect(() => open(ct, other, Buffer.from('myos.finance'))).toThrow();
	});

	test('same secret+salt+iterations is deterministic', async () => {
		const salt = newSalt();
		const a = await deriveKey('abc', salt, 10_000);
		const b = await deriveKey('abc', salt, 10_000);
		expect(a.equals(b)).toBe(true);
	});

	test('v2 envelopes use a per-key subkey and reject v1 cross-reads', async () => {
		const dek = Buffer.alloc(32, 3);
		const env = sealValue(plain, dek, 'meos.notes', 2);
		expect(env.v).toBe(2);
		expect(openValue(env, dek, 'meos.notes').equals(plain)).toBe(true);
		expect(() => openValue(env, dek, 'meos.events')).toThrow();

		const legacy = sealValue(plain, dek, 'meos.notes', 1);
		expect(legacy.v).toBe(1);
		expect(openValue(legacy, dek, 'meos.notes').equals(plain)).toBe(true);
	});
});
