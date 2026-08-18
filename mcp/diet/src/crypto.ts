import { createCipheriv, createDecipheriv, pbkdf2, randomBytes } from 'node:crypto';
import { promisify } from 'node:util';

const pbkdf2Async = promisify(pbkdf2);

export const FORMAT_VERSION = 1;
export const KDF_NAME = 'pbkdf2-sha256';
export const PBKDF2_ITERATIONS = 600_000;
export const SALT_BYTES = 16;
export const KEY_BYTES = 32;
export const IV_BYTES = 12;
export const TAG_BYTES = 16;

export function newSalt(): Buffer {
	return randomBytes(SALT_BYTES);
}

export async function deriveKey(secret: string, salt: Buffer, iterations = PBKDF2_ITERATIONS): Promise<Buffer> {
	const normalized = secret.normalize('NFC');
	return pbkdf2Async(normalized, salt, iterations, KEY_BYTES, 'sha256');
}

/** AES-256-GCM combined box as base64(nonce ‖ ciphertext ‖ tag). */
export function seal(plaintext: Buffer, key: Buffer, aad: Buffer = Buffer.alloc(0)): string {
	const iv = randomBytes(IV_BYTES);
	const cipher = createCipheriv('aes-256-gcm', key, iv);
	if (aad.length) cipher.setAAD(aad);
	const ct = Buffer.concat([cipher.update(plaintext), cipher.final()]);
	const tag = cipher.getAuthTag();
	return Buffer.concat([iv, ct, tag]).toString('base64');
}

export function open(base64: string, key: Buffer, aad: Buffer = Buffer.alloc(0)): Buffer {
	const combined = Buffer.from(base64, 'base64');
	if (combined.length < IV_BYTES + TAG_BYTES) throw new Error('decrypt failed');
	const iv = combined.subarray(0, IV_BYTES);
	const tag = combined.subarray(combined.length - TAG_BYTES);
	const ct = combined.subarray(IV_BYTES, combined.length - TAG_BYTES);
	const decipher = createDecipheriv('aes-256-gcm', key, iv);
	if (aad.length) decipher.setAAD(aad);
	decipher.setAuthTag(tag);
	try {
		return Buffer.concat([decipher.update(ct), decipher.final()]);
	} catch {
		throw new Error('decrypt failed');
	}
}

export type CryptoMeta = {
	v: number;
	kdf: string;
	iterations: number;
	passSalt: string;
	recoverySalt: string;
	wrappedByPass: string;
	wrappedByRecovery: string;
	check: string;
};

export type SealedEnvelope = { v: number; ct: string };

const CHECK_TOKEN = Buffer.from('myos.vault.check.v1');

export function isEnvelope(value: unknown): value is SealedEnvelope {
	return !!value && typeof value === 'object' && typeof (value as SealedEnvelope).ct === 'string' && (value as SealedEnvelope).v != null;
}

export async function unlockDek(meta: CryptoMeta, passphrase: string): Promise<Buffer> {
	const kek = await deriveKey(passphrase, Buffer.from(meta.passSalt, 'base64'), meta.iterations);
	const dek = open(meta.wrappedByPass, kek, Buffer.from('wrap:pass'));
	const check = open(meta.check, dek, Buffer.from('check'));
	if (!check.equals(CHECK_TOKEN)) throw new Error('decrypt failed');
	return dek;
}

export async function unlockDekWithRecovery(meta: CryptoMeta, recoveryCode: string): Promise<Buffer> {
	const normalized = normalizeRecoveryCode(recoveryCode);
	const kek = await deriveKey(normalized, Buffer.from(meta.recoverySalt, 'base64'), meta.iterations);
	const dek = open(meta.wrappedByRecovery, kek, Buffer.from('wrap:recovery'));
	const check = open(meta.check, dek, Buffer.from('check'));
	if (!check.equals(CHECK_TOKEN)) throw new Error('decrypt failed');
	return dek;
}

const B32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function normalizeRecoveryCode(code: string): string {
	let s = code.toUpperCase().replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
	return [...s].filter((ch) => B32.includes(ch)).join('');
}

export function sealValue(plaintextJson: Buffer, dek: Buffer, key: string): SealedEnvelope {
	return { v: FORMAT_VERSION, ct: seal(plaintextJson, dek, Buffer.from(key)) };
}

export function openValue(envelope: SealedEnvelope, dek: Buffer, key: string): Buffer {
	return open(envelope.ct, dek, Buffer.from(key));
}
