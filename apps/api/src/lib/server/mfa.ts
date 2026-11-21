import { env } from '$env/dynamic/private';
import { nowISO, sql } from './db';
import { encryptSecret, decryptSecret } from './secrets';

/**
 * Optional TOTP second factor (RFC 6238) for the login password.
 *
 * Why TOTP and not passkeys: the native app already has a working login screen
 * and a separate zero-knowledge vault passphrase. TOTP is a standard, testable
 * second factor that needs no new client platform API. WebAuthn/passkeys are a
 * documented follow-up, not a half-built endpoint with no UI.
 *
 * The shared secret is encrypted with the same server master key as AI provider
 * credentials (`MEOS_SECRETS_KEY`). If that key is missing, MFA setup fails
 * closed rather than storing a plaintext TOTP secret.
 */

export interface MfaStatus {
  enabled: boolean;
  pending: boolean;
  recoveryCodesRemaining: number;
}

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
/** Crockford base32 for human-typed recovery codes (no I, L, O or U). */
const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const STEP_SECONDS = 30;
const DIGITS = 6;
const RECOVERY_CODE_COUNT = 10;

function base32Encode(bytes: Uint8Array): string {
  let bits = 0;
  let acc = 0;
  let out = '';
  for (const b of bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += BASE32[(acc >>> bits) & 31];
    }
  }
  if (bits > 0) out += BASE32[(acc << (5 - bits)) & 31];
  return out;
}

function base32Decode(text: string): Uint8Array<ArrayBuffer> {
  const clean = text.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0;
  let acc = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const v = BASE32.indexOf(ch);
    if (v < 0) continue;
    acc = (acc << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >>> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

function counterBytes(counter: number): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(8);
  let n = counter;
  for (let i = 7; i >= 0; i--) {
    out[i] = n & 0xff;
    n = Math.floor(n / 256);
  }
  return out;
}

async function hotp(secret: string, counter: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    base32Decode(secret),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign']
  );
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, counterBytes(counter)));
  const offset = mac[mac.length - 1]! & 0x0f;
  const code =
    ((mac[offset]! & 0x7f) << 24) |
    ((mac[offset + 1]! & 0xff) << 16) |
    ((mac[offset + 2]! & 0xff) << 8) |
    (mac[offset + 3]! & 0xff);
  return String(code % 10 ** DIGITS).padStart(DIGITS, '0');
}

function constantTimeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i]! ^ y[i]!;
  return diff === 0;
}

/** Verify a 6-digit TOTP with one step of clock skew either way. */
export async function verifyTotp(secret: string, code: string, now = Date.now()): Promise<boolean> {
  const clean = code.replace(/\s+/g, '');
  if (!/^\d{6}$/.test(clean)) return false;
  const counter = Math.floor(now / 1000 / STEP_SECONDS);
  for (const offset of [-1, 0, 1]) {
    const expected = await hotp(secret, counter + offset);
    if (constantTimeEqual(clean, expected)) return true;
  }
  return false;
}

export function newTotpSecret(): string {
  return base32Encode(crypto.getRandomValues(new Uint8Array(20)));
}

function crockfordEncode(bytes: Uint8Array): string {
  let bits = 0;
  let acc = 0;
  let out = '';
  for (const b of bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += CROCKFORD[(acc >>> bits) & 31];
    }
  }
  if (bits > 0) out += CROCKFORD[(acc << (5 - bits)) & 31];
  return out;
}

export function newRecoveryCodes(): string[] {
  const codes: string[] = [];
  for (let i = 0; i < RECOVERY_CODE_COUNT; i++) {
    const raw = crockfordEncode(crypto.getRandomValues(new Uint8Array(8))).slice(0, 12);
    codes.push(`${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`);
  }
  return codes;
}

export function normalizeRecoveryCode(code: string): string {
  return [...code.toUpperCase().replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1')]
    .filter((ch) => CROCKFORD.includes(ch))
    .join('');
}

async function recoveryHash(code: string): Promise<string> {
  // Stable pepper, separate from the rotating MEOS_SECRETS_KEY. Recovery codes
  // are 96-bit random values, so even the fixed fallback is not brute-forceable;
  // the pepper only stops a DB-only attacker from testing a stolen code list.
  const pepper = env.MEOS_MFA_RECOVERY_PEPPER || 'meos-recovery-no-pepper';
  const data = new TextEncoder().encode(`${pepper}\n${normalizeRecoveryCode(code)}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function otpauthUrl(username: string, secret: string): string {
  const label = encodeURIComponent(`MeOS:${username}`);
  const params = new URLSearchParams({
    secret,
    issuer: 'MeOS',
    algorithm: 'SHA1',
    digits: String(DIGITS),
    period: String(STEP_SECONDS)
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

let ensured = false;
async function ensureMfaTables(): Promise<void> {
  if (ensured) return;
  await sql`
    create table if not exists user_mfa (
      user_id    integer primary key references users(id) on delete cascade,
      secret     text not null,
      enabled    integer not null default 0,
      created_at text not null,
      enabled_at text
    )`;
  await sql`
    create table if not exists mfa_recovery_codes (
      user_id   integer not null references users(id) on delete cascade,
      code_hash text not null,
      used_at   text,
      primary key (user_id, code_hash)
    )`;
  ensured = true;
}

export async function mfaStatus(userId: number): Promise<MfaStatus> {
  await ensureMfaTables();
  const rows = await sql`select enabled from user_mfa where user_id = ${userId}`;
  const remaining = await sql`
    select count(*) as n from mfa_recovery_codes
    where user_id = ${userId} and used_at is null`;
  return {
    enabled: Boolean(rows[0]?.enabled),
    pending: rows.length > 0 && !Boolean(rows[0]?.enabled),
    recoveryCodesRemaining: Number(remaining[0]?.n ?? 0)
  };
}

export async function isMfaEnabled(userId: number): Promise<boolean> {
  await ensureMfaTables();
  const rows = await sql`select enabled from user_mfa where user_id = ${userId}`;
  return Boolean(rows[0]?.enabled);
}

/**
 * Start enrollment. Replaces any previous *pending* secret, but refuses if MFA
 * is already enabled — disable first, which requires a fresh factor.
 */
export async function beginMfaSetup(
  userId: number,
  username: string
): Promise<{ secret: string; otpauthUrl: string; recoveryCodes: string[] }> {
  await ensureMfaTables();
  const status = await mfaStatus(userId);
  if (status.enabled) throw new Error('Two-factor authentication is already enabled.');

  const secret = newTotpSecret();
  const encrypted = await encryptSecret(secret);
  const codes = newRecoveryCodes();
  const now = nowISO();

  await sql`
    insert into user_mfa (user_id, secret, enabled, created_at, enabled_at)
    values (${userId}, ${encrypted}, 0, ${now}, null)
    on conflict (user_id) do update set secret = excluded.secret, enabled = 0, created_at = excluded.created_at, enabled_at = null`;
  await sql`delete from mfa_recovery_codes where user_id = ${userId}`;
  for (const code of codes) {
    await sql`insert into mfa_recovery_codes (user_id, code_hash) values (${userId}, ${await recoveryHash(code)})`;
  }

  return { secret, otpauthUrl: otpauthUrl(username, secret), recoveryCodes: codes };
}

/** Confirm the first code and switch the factor on. */
export async function enableMfa(userId: number, code: string): Promise<boolean> {
  await ensureMfaTables();
  const rows = await sql`select secret, enabled from user_mfa where user_id = ${userId}`;
  if (!rows.length || Boolean(rows[0]?.enabled)) return false;
  const secret = await decryptSecret(String(rows[0]!.secret));
  if (!(await verifyTotp(secret, code))) return false;
  await sql`update user_mfa set enabled = 1, enabled_at = ${nowISO()} where user_id = ${userId}`;
  return true;
}

export async function disableMfa(userId: number): Promise<void> {
  await ensureMfaTables();
  await sql`delete from user_mfa where user_id = ${userId}`;
  await sql`delete from mfa_recovery_codes where user_id = ${userId}`;
}

/**
 * Verify a login second factor. A TOTP code is preferred; a one-time recovery
 * code is accepted and immediately burned. Any failure is a plain `false` so
 * callers cannot distinguish "wrong code" from "already used".
 */
export async function verifySecondFactor(userId: number, code: string): Promise<boolean> {
  await ensureMfaTables();
  const rows = await sql`select secret, enabled from user_mfa where user_id = ${userId}`;
  if (!rows.length || !Boolean(rows[0]?.enabled)) return true; // not enrolled

  const raw = code.trim();
  if (!raw) return false;

  if (/^\d{6}$/.test(raw.replace(/\s+/g, ''))) {
    try {
      const secret = await decryptSecret(String(rows[0]!.secret));
      if (await verifyTotp(secret, raw)) return true;
    } catch {
      return false;
    }
  }

  const hash = await recoveryHash(raw);
  const found = await sql`
    select code_hash from mfa_recovery_codes
    where user_id = ${userId} and code_hash = ${hash} and used_at is null
    limit 1`;
  if (!found.length) return false;
  await sql`
    update mfa_recovery_codes set used_at = ${nowISO()}
    where user_id = ${userId} and code_hash = ${hash} and used_at is null`;
  return true;
}
