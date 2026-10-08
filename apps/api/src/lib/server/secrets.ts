import { randomBytes, createCipheriv, createDecipheriv, createHash } from 'node:crypto';
import { env } from '$env/dynamic/private';

/**
 * Symmetric encryption for user-added AI provider keys, so they can live in the DB
 * (and sync across devices) without being readable from a database dump alone.
 *
 * AES-256-GCM (authenticated). The master key comes from MEOS_SECRETS_KEY
 * (legacy MYOS_SECRETS_KEY still works as a fallback):
 *   - a base64 string that decodes to exactly 32 bytes is used directly, or
 *   - any other string is sha256'd into 32 bytes (so a plain passphrase works too).
 *
 * Threat model, honestly: this protects against a DB-only leak (backup, stray
 * SELECT, read replica). It does NOT protect against a full server compromise —
 * the master key is in env, and the server must decrypt to call the providers.
 * If the master key is lost or changed, stored keys become undecryptable and the
 * user re-enters them.
 */

function masterKey(): Buffer {
  const raw = env.MEOS_SECRETS_KEY || env.MYOS_SECRETS_KEY;
  if (!raw) throw new Error('MEOS_SECRETS_KEY is not set on the server');
  const decoded = Buffer.from(raw, 'base64');
  if (decoded.length === 32) return decoded;
  return createHash('sha256').update(raw, 'utf8').digest();
}

/** Returns base64 of iv(12) ‖ authTag(16) ‖ ciphertext. */
export function encryptSecret(plain: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', masterKey(), iv);
  const ct = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, ct]).toString('base64');
}

export function decryptSecret(blob: string): string {
  const buf = Buffer.from(blob, 'base64');
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const ct = buf.subarray(28);
  const decipher = createDecipheriv('aes-256-gcm', masterKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8');
}

/** Display form for the UI — never send the raw key back to the client. */
export function maskKey(plain: string): string {
  const t = plain.trim();
  if (t.length <= 8) return '••••';
  return `${t.slice(0, 4)}…${t.slice(-4)}`;
}
