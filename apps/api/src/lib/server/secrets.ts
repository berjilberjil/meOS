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
 *
 * WHY THIS FILE WAS REWRITTEN (Oct 2026, Workers free-tier CPU fix):
 * node:crypto's createCipheriv/createDecipheriv/createHash run through a slow
 * polyfill on Workers — 15-45ms CPU per encrypt/decrypt, over the 10ms free
 * cap, so AI requests died mid-flight. crypto.subtle is native on Workers and
 * fast. The CryptoKey is now derived once and cached in module scope (it used
 * to re-hash the raw key on every single call).
 *
 * Wire format is UNCHANGED: base64(iv(12) ‖ tag(16) ‖ ciphertext), so anything
 * encrypted with the old code still decrypts. Both functions are now async —
 * call sites must await them.
 */

let cachedKeyPromise: Promise<CryptoKey> | null = null;
let cachedRaw: string | null = null;

async function masterKey(): Promise<CryptoKey> {
  const raw = env.MEOS_SECRETS_KEY || env.MYOS_SECRETS_KEY;
  if (!raw) throw new Error('MEOS_SECRETS_KEY is not set on the server');
  if (cachedKeyPromise && cachedRaw === raw) return cachedKeyPromise;
  cachedRaw = raw;
  cachedKeyPromise = (async () => {
    const decoded = Buffer.from(raw, 'base64');
    // typed Uint8Array<ArrayBuffer>, not Buffer: crypto.subtle's BufferSource
    // rejects Buffer's ArrayBufferLike (SharedArrayBuffer can sneak in)
    let keyBytes: Uint8Array<ArrayBuffer>;
    if (decoded.length === 32) {
      keyBytes = new Uint8Array(decoded); // copies into a fresh ArrayBuffer
    } else {
      keyBytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(raw)));
    }
    return crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
  })().catch((e) => {
    cachedKeyPromise = null; // never cache a failed derivation
    cachedRaw = null;
    throw e;
  });
  return cachedKeyPromise;
}

/** Returns base64 of iv(12) ‖ authTag(16) ‖ ciphertext. */
export async function encryptSecret(plain: string): Promise<string> {
  const key = await masterKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  // WebCrypto appends the 16-byte auth tag to the ciphertext — the same layout
  // the old node:crypto code assembled by hand.
  const packed = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(plain))
  );
  const out = new Uint8Array(iv.length + packed.length);
  out.set(iv, 0);
  out.set(packed, iv.length);
  return Buffer.from(out).toString('base64');
}

export async function decryptSecret(blob: string): Promise<string> {
  const key = await masterKey();
  const buf = Buffer.from(blob, 'base64');
  const iv = buf.subarray(0, 12);
  const packed = buf.subarray(12); // ciphertext ‖ tag
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, packed);
  return new TextDecoder().decode(plain);
}

/** Display form for the UI — never send the raw key back to the client. */
export function maskKey(plain: string): string {
  const t = plain.trim();
  if (t.length <= 8) return '••••';
  return `${t.slice(0, 4)}…${t.slice(-4)}`;
}
