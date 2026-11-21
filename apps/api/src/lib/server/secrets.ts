import { env } from '$env/dynamic/private';

/**
 * Symmetric encryption for user-added AI provider keys and the TOTP secret, so
 * they can live in the database without being readable from a database dump
 * alone.
 *
 * AES-256-GCM (authenticated). The master key comes from a key ring:
 *
 *   MEOS_SECRETS_KEYS='{"v1":"<base64 32 bytes>","v2":"<base64 32 bytes>"}'
 *   MEOS_SECRETS_KEY_ID=v2
 *
 * or the single-key form:
 *
 *   MEOS_SECRETS_KEY=<base64 32 bytes>
 *
 * New ciphertext is `v2:<key-id>:<base64(iv ‖ ciphertext ‖ tag)>`. Legacy
 * ciphertext (raw base64, no key id, no AAD) is still decrypted so a rotation
 * does not lose data; it is re-encrypted lazily by the rotate endpoint.
 *
 * Threat model, honestly: this protects against a DB-only leak (backup, stray
 * SELECT, read replica). It does NOT protect against a full server compromise —
 * the master key is in env, and the server must decrypt to call the providers.
 * Designated vault data is separately end-to-end encrypted on the client; this
 * key never touches it.
 *
 * A non-32-byte `MEOS_SECRETS_KEY` is accepted only for *decryption* of legacy
 * data. New encryption fails closed unless `MEOS_ALLOW_WEAK_SECRETS_KEY=true`,
 * so a passphrase cannot quietly become the long-term key again.
 */

const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;

type KeyEntry = { id: string; raw: string; key: Promise<CryptoKey>; strong: boolean };

let cache: { signature: string; entries: Map<string, KeyEntry>; active: string } | null = null;

function keyConfig(): { active: string; values: Map<string, string> } {
  const rawRing = env.MEOS_SECRETS_KEYS?.trim();
  if (rawRing) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawRing);
    } catch {
      throw new Error('MEOS_SECRETS_KEYS must be a JSON object of key-id → base64 key');
    }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('MEOS_SECRETS_KEYS must be a JSON object of key-id → base64 key');
    }
    const values = new Map<string, string>();
    for (const [id, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (!/^[a-z0-9_-]{1,32}$/i.test(id)) throw new Error(`Invalid secrets key id "${id}"`);
      if (typeof value !== 'string' || !value.trim()) throw new Error(`Secrets key "${id}" is empty`);
      values.set(id, value.trim());
    }
    if (!values.size) throw new Error('MEOS_SECRETS_KEYS has no keys');
    const active = env.MEOS_SECRETS_KEY_ID?.trim() || values.keys().next().value!;
    if (!values.has(active)) throw new Error(`MEOS_SECRETS_KEY_ID "${active}" is not in MEOS_SECRETS_KEYS`);
    return { active, values };
  }

  const single = env.MEOS_SECRETS_KEY || env.MYOS_SECRETS_KEY;
  if (!single) throw new Error('MEOS_SECRETS_KEY is not set on the server');
  return { active: env.MEOS_SECRETS_KEY_ID?.trim() || 'v1', values: new Map([['v1', single]]) };
}

async function importKey(raw: string): Promise<{ key: CryptoKey; strong: boolean }> {
  const decoded = Buffer.from(raw, 'base64');
  if (decoded.length === KEY_BYTES) {
    return {
      key: await crypto.subtle.importKey('raw', new Uint8Array(decoded), 'AES-GCM', false, ['encrypt', 'decrypt']),
      strong: true
    };
  }
  // Legacy passphrase: sha256 it exactly as the old code did, so old ciphertext
  // still opens. This is never used for new encryption unless explicitly allowed.
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(raw));
  return {
    key: await crypto.subtle.importKey('raw', new Uint8Array(digest), 'AES-GCM', false, ['encrypt', 'decrypt']),
    strong: false
  };
}

function ring(): { entries: Map<string, KeyEntry>; active: string; activeEntry: KeyEntry } {
  const cfg = keyConfig();
  const signature = JSON.stringify([cfg.active, [...cfg.values.entries()]]);
  if (!cache || cache.signature !== signature) {
    const entries = new Map<string, KeyEntry>();
    for (const [id, raw] of cfg.values) {
      const strong = Buffer.from(raw, 'base64').length === KEY_BYTES;
      entries.set(id, { id, raw, key: importKey(raw).then((k) => k.key), strong });
    }
    cache = { signature, entries, active: cfg.active };
  }
  const activeEntry = cache.entries.get(cfg.active);
  if (!activeEntry) throw new Error('Active secrets key is missing');
  return { entries: cache.entries, active: cfg.active, activeEntry };
}

export function activeSecretsKeyId(): string {
  return ring().active;
}

function aad(keyId: string): Uint8Array<ArrayBuffer> {
  return new Uint8Array(new TextEncoder().encode(`meos.secret.v2:${keyId}`));
}

/** Returns `v2:<key-id>:<base64(iv ‖ ciphertext ‖ tag)>`. */
export async function encryptSecret(plain: string): Promise<string> {
  const { active, activeEntry } = ring();
  if (!activeEntry.strong && env.MEOS_ALLOW_WEAK_SECRETS_KEY !== 'true') {
    throw new Error(
      'MEOS_SECRETS_KEY must decode to exactly 32 bytes for new encryption. Generate one with: openssl rand -base64 32'
    );
  }
  const key = await activeEntry.key;
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const packed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv, additionalData: aad(active) },
      key,
      new TextEncoder().encode(plain)
    )
  );
  const out = new Uint8Array(iv.length + packed.length);
  out.set(iv, 0);
  out.set(packed, iv.length);
  return `v2:${active}:${Buffer.from(out).toString('base64')}`;
}

function parseV2(blob: string): { keyId: string; body: string } | null {
  const match = /^v2:([a-z0-9_-]{1,32}):(.+)$/i.exec(blob);
  return match ? { keyId: match[1]!, body: match[2]! } : null;
}

export async function decryptSecret(blob: string): Promise<string> {
  const { entries, activeEntry } = ring();
  const parsed = parseV2(blob);
  if (parsed) {
    const entry = entries.get(parsed.keyId);
    if (!entry) throw new Error(`Unknown secrets key id "${parsed.keyId}" — add it to MEOS_SECRETS_KEYS`);
    const buf = Buffer.from(parsed.body, 'base64');
    const plain = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: new Uint8Array(buf.subarray(0, IV_BYTES)),
        additionalData: aad(parsed.keyId)
      },
      await entry.key,
      new Uint8Array(buf.subarray(IV_BYTES))
    );
    return new TextDecoder().decode(plain);
  }

  // Legacy raw base64(iv ‖ ciphertext ‖ tag), no key id, no AAD. Try the active
  // key first, then every other key in the ring so a rotation is reversible.
  const buf = Buffer.from(blob, 'base64');
  const candidates = [activeEntry, ...[...entries.values()].filter((e) => e.id !== activeEntry.id)];
  for (const entry of candidates) {
    try {
      const plain = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: new Uint8Array(buf.subarray(0, IV_BYTES)) },
        await entry.key,
        new Uint8Array(buf.subarray(IV_BYTES))
      );
      return new TextDecoder().decode(plain);
    } catch {
      /* try the next key */
    }
  }
  throw new Error('Could not decrypt the stored secret with any configured key');
}

/** Display form for the UI — never send the raw key back to the client. */
export function maskKey(plain: string): string {
  const t = plain.trim();
  if (t.length <= 8) return '••••';
  return `${t.slice(0, 4)}…${t.slice(-4)}`;
}

/** Re-encrypt one stored secret under the active key. */
export async function rotateSecret(blob: string): Promise<string> {
  const plain = await decryptSecret(blob);
  const next = await encryptSecret(plain);
  return next;
}
