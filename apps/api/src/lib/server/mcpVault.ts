/**
 * The crypto behind MCP connections: how a bearer token unlocks a user's
 * notes without the server ever storing anything that can.
 *
 * The app mints a random token, derives a wrapping key from it with HKDF, seals
 * the vault DEK under that key and uploads only `sha256(token)` and the sealed
 * DEK. So the database alone opens nothing; a request has to carry the token.
 * The token is 256 random bits, which is why HKDF is enough here and the
 * 600k-round PBKDF2 the passphrase needs (far past the 10ms CPU cap) is not.
 *
 * Must stay byte-compatible with Core/MCPConnections.swift and with the vault's
 * own format (Core/Crypto): AES-256-GCM boxes as base64(nonce(12) ‖ ct ‖ tag(16)),
 * state envelopes `{ v: 1, ct }` sealed with the state key name as AAD.
 */

const enc = new TextEncoder();

const TOKEN_PREFIX = 'meos_';
const HKDF_SALT = enc.encode('meos.mcp.v1');
const HKDF_INFO = enc.encode('wrap:mcp');
export const WRAP_AAD = 'wrap:mcp';

function fromBase64(s: string): Uint8Array<ArrayBuffer> {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Token → the bytes HKDF uses. `meos_` + base64url of 32 random bytes. */
function tokenBytes(token: string): Uint8Array<ArrayBuffer> | null {
  if (!token.startsWith(TOKEN_PREFIX)) return null;
  const b64 = token.slice(TOKEN_PREFIX.length).replace(/-/g, '+').replace(/_/g, '/');
  try {
    const raw = fromBase64(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
    return raw.length === 32 ? raw : null;
  } catch {
    return null;
  }
}

/** Lookup id stored in the database: hex sha256 of the token string. */
export async function tokenHash(token: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', enc.encode(token));
  return Array.from(new Uint8Array(d), (b) => b.toString(16).padStart(2, '0')).join('');
}

async function wrapKey(token: string): Promise<CryptoKey | null> {
  const ikm = tokenBytes(token);
  if (!ikm) return null;
  const base = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: HKDF_SALT, info: HKDF_INFO },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['decrypt']
  );
}

async function openBox(b64: string, key: CryptoKey, aad: string): Promise<Uint8Array<ArrayBuffer>> {
  const box = fromBase64(b64);
  if (box.length < 28) throw new Error('decrypt failed');
  const pt = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: box.subarray(0, 12), additionalData: enc.encode(aad) },
    key,
    box.subarray(12)
  );
  return new Uint8Array(pt);
}

/** Unseal the DEK a connection holds. Null when the token does not open it. */
export async function unwrapDek(token: string, wrappedDek: string): Promise<CryptoKey | null> {
  const kek = await wrapKey(token);
  if (!kek) return null;
  try {
    const raw = await openBox(wrappedDek, kek, WRAP_AAD);
    if (raw.length !== 32) return null;
    return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['decrypt']);
  } catch {
    return null;
  }
}

/** Open one encrypted `app_state` value (the `{ v, ct }` envelope) to its JSON. */
export async function openState(envelope: unknown, dek: CryptoKey, stateKey: string): Promise<unknown> {
  const env = envelope as { v?: unknown; ct?: unknown } | null;
  if (!env || typeof env.ct !== 'string') throw new Error('not an encrypted value');
  const pt = await openBox(env.ct, dek, stateKey);
  return JSON.parse(new TextDecoder().decode(pt));
}
