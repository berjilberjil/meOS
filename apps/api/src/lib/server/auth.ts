import { env } from '$env/dynamic/private';
import { execLiteral, sql, nowISO } from './db';

const DAY = 1000 * 60 * 60 * 24;
export const SESSION_COOKIE = 'meos_session';
/** Absolute session lifetime. Short enough that a stolen cookie ages out. */
export const SESSION_DAYS = 30;
/** A session unused for this long is dead even if its absolute expiry is later. */
export const SESSION_IDLE_DAYS = 14;

/**
 * Password hashing on the Workers free tier (10ms CPU cap).
 *
 * The login password is a bearer credential, not the encryption key. The vault
 * passphrase is separate, never sent to the server, and uses 600k PBKDF2 rounds
 * on-device. This hash only has to stop online guessing (rate-limited) and
 * offline guessing *if the database alone leaks*. For the second case the hash
 * is peppered with a dedicated `MEOS_PASSWORD_PEPPER`: a DB dump without the
 * server env cannot verify guesses, and rotating the secrets key does not lock
 * every login out.
 *
 * Stored formats, all still verified:
 *   v3:<iterations>:<saltHex>:<hashHex>   peppered PBKDF2-SHA256 (current)
 *   v2:<iterations>:<saltHex>:<hashHex>   PBKDF2-SHA256 (pre-pepper)
 *   <saltHex>:<hashHex>                   legacy scrypt
 *
 * `MEOS_PBKDF2_ITERATIONS` can raise the work factor on a paid Workers plan.
 * The floor stays 10k so a free-tier deployment does not break; the pepper and
 * rate limits carry the rest. This trade-off is in SECURITY.md.
 */
const DEFAULT_PBKDF2_ITERATIONS = 10_000;
const MIN_PBKDF2_ITERATIONS = 10_000;
const MAX_PBKDF2_ITERATIONS = 1_000_000;

export function pbkdf2Iterations(): number {
  const raw = Number(env.MEOS_PBKDF2_ITERATIONS ?? DEFAULT_PBKDF2_ITERATIONS);
  if (!Number.isFinite(raw)) return DEFAULT_PBKDF2_ITERATIONS;
  return Math.max(MIN_PBKDF2_ITERATIONS, Math.min(MAX_PBKDF2_ITERATIONS, Math.trunc(raw)));
}

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex: string): Uint8Array<ArrayBuffer> {
  return new Uint8Array((hex.match(/.{2}/g) ?? []).map((h) => parseInt(h, 16)));
}

function randomHex(bytes: number): string {
  return toHex(crypto.getRandomValues(new Uint8Array(bytes)));
}

let cachedPepper: { raw: string; bytes: Promise<Uint8Array<ArrayBuffer>> } | null = null;

/**
 * The pepper is not a replacement for the master key; it is an extra input the
 * database does not contain. If no server secret is configured, we fall back to
 * the unpeppered v2 format so existing deployments keep working, and the docs
 * say plainly that the pepper is off.
 */
export function passwordPepperConfigured(): boolean {
  return Boolean(env.MEOS_PASSWORD_PEPPER);
}

function pepper(): Promise<Uint8Array<ArrayBuffer>> | null {
  // Deliberately separate from MEOS_SECRETS_KEY. The secrets key is rotated for
  // AI/TOTP ciphertext; reusing it as the password pepper would make a routine
  // rotation lock every login out. This pepper must stay stable for the life of
  // the password hashes (rotating it requires rehashing on next login).
  const raw = env.MEOS_PASSWORD_PEPPER;
  if (!raw) return null;
  if (cachedPepper?.raw === raw) return cachedPepper.bytes;
  const bytes = crypto.subtle
    .digest('SHA-256', new TextEncoder().encode(`meos.password.pepper.v1\n${raw}`))
    .then((d) => new Uint8Array(d));
  cachedPepper = { raw, bytes };
  return bytes;
}

async function hmacPepper(password: string, pepperBytes: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  const key = await crypto.subtle.importKey('raw', pepperBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(password)));
}

async function pbkdf2(
  pw: string | Uint8Array<ArrayBuffer>,
  salt: Uint8Array<ArrayBuffer>,
  iterations: number
): Promise<Uint8Array<ArrayBuffer>> {
  const material = typeof pw === 'string' ? new TextEncoder().encode(pw) : pw;
  const keyMaterial = await crypto.subtle.importKey('raw', material, 'PBKDF2', false, ['deriveBits']);
  return new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: 'PBKDF2', hash: 'SHA-256', salt, iterations },
      keyMaterial,
      512 // 64 bytes, same length the old scrypt hash had
    )
  );
}

export async function hashPassword(pw: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iterations = pbkdf2Iterations();
  const pepperBytes = await pepper();
  if (pepperBytes) {
    const peppered = await hmacPepper(pw, pepperBytes);
    const hash = await pbkdf2(peppered, salt, iterations);
    return `v3:${iterations}:${toHex(salt)}:${toHex(hash)}`;
  }
  const hash = await pbkdf2(pw, salt, iterations);
  return `v2:${iterations}:${toHex(salt)}:${toHex(hash)}`;
}

export async function verifyPassword(pw: string, stored: string): Promise<boolean> {
  if (stored.startsWith('v3:')) {
    const [, iters, saltHex, hashHex] = stored.split(':');
    const pepperBytes = await pepper();
    // A v3 hash without its pepper cannot be verified. Fail closed; never treat
    // an unpeppered comparison as a success.
    if (!pepperBytes || !iters || !saltHex || !hashHex) return false;
    const iterations = Number(iters);
    if (!Number.isInteger(iterations) || iterations < MIN_PBKDF2_ITERATIONS || iterations > MAX_PBKDF2_ITERATIONS) {
      return false;
    }
    const peppered = await hmacPepper(pw, pepperBytes);
    const test = await pbkdf2(peppered, fromHex(saltHex), iterations);
    return constantTimeEqual(fromHex(hashHex), test);
  }
  if (stored.startsWith('v2:')) {
    const [, iters, saltHex, hashHex] = stored.split(':');
    if (!iters || !saltHex || !hashHex) return false;
    const iterations = Number(iters);
    if (!Number.isInteger(iterations) || iterations < MIN_PBKDF2_ITERATIONS || iterations > MAX_PBKDF2_ITERATIONS) {
      return false;
    }
    const test = await pbkdf2(pw, fromHex(saltHex), iterations);
    return constantTimeEqual(fromHex(hashHex), test);
  }
  // Legacy scrypt hash: lazy-import the polyfill only for old hashes, so the
  // common path never pays for it.
  const { scryptSync, timingSafeEqual } = await import('node:crypto');
  const [salt, hash] = stored.split(':');
  if (!salt || !hash) return false;
  const test = scryptSync(pw, salt, 64);
  const orig = Buffer.from(hash, 'hex');
  return orig.length === test.length && timingSafeEqual(orig, test);
}

function constantTimeEqual(orig: Uint8Array, test: Uint8Array): boolean {
  if (orig.length !== test.length) return false;
  let diff = 0;
  for (let i = 0; i < orig.length; i++) diff |= orig[i]! ^ test[i]!;
  return diff === 0;
}

/**
 * Spend the same PBKDF2 work for an unknown username as for a real one, so
 * response timing does not answer "does this account exist?".
 */
export async function dummyVerify(password: string): Promise<void> {
  const salt = new Uint8Array(16);
  const pepperBytes = await pepper();
  if (pepperBytes) await pbkdf2(await hmacPepper(password, pepperBytes), salt, pbkdf2Iterations());
  else await pbkdf2(password, salt, pbkdf2Iterations());
}

export const LOGIN_MAX_ATTEMPTS = 10;
export const LOGIN_WINDOW_MINUTES = 15;

/** A failed sign-in writes one row per scope, so each scope is judged alone. */
export function attemptsAllowed(usernameCount: number, ipCount: number): boolean {
  return usernameCount < LOGIN_MAX_ATTEMPTS && ipCount < LOGIN_MAX_ATTEMPTS;
}

/**
 * Public signup is closed for this single-owner app, but the first account must
 * be creatable on a fresh database. `MEOS_ALLOW_SIGNUP=true` is the explicit
 * escape hatch for a deliberate second account.
 */
export function signupAllowed(userCount: number, allowFlag: string | undefined): boolean {
  return allowFlag === 'true' || userCount === 0;
}

let attemptsReady = false;
async function ensureAttempts(): Promise<void> {
  if (attemptsReady) return;
  await sql`
    create table if not exists login_attempts (
      scope      text not null,
      at         text not null
    )`;
  await sql`create index if not exists login_attempts_scope_idx on login_attempts(scope, at)`;
  attemptsReady = true;
}

function windowStart(): string {
  return new Date(Date.now() - LOGIN_WINDOW_MINUTES * 60_000).toISOString();
}

/** Whether this username/IP pair still has attempts left in the window. */
export async function loginAllowed(username: string, ip: string): Promise<boolean> {
  await ensureAttempts();
  const rows = await sql`
    select scope, count(*) as n from login_attempts
    where at > ${windowStart()} and scope in (${'u:' + username}, ${'i:' + ip})
    group by scope`;
  const counts = new Map(rows.map((r) => [String(r.scope), Number(r.n)]));
  return attemptsAllowed(counts.get('u:' + username) ?? 0, counts.get('i:' + ip) ?? 0);
}

/** Record a failure, and opportunistically drop rows that have aged out. */
export async function recordFailedLogin(username: string, ip: string): Promise<void> {
  await ensureAttempts();
  const now = new Date().toISOString();
  await sql`delete from login_attempts where at <= ${windowStart()}`;
  await sql`insert into login_attempts (scope, at) values (${'u:' + username}, ${now})`;
  await sql`insert into login_attempts (scope, at) values (${'i:' + ip}, ${now})`;
}

/** A clean sign-in clears this username's and this address's failures. */
export async function clearFailedLogins(username: string, ip: string): Promise<void> {
  await ensureAttempts();
  await sql`delete from login_attempts where scope in (${'u:' + username}, ${'i:' + ip})`;
}

/* -------------------------------------------------------------------------- */
/* Sessions                                                                    */
/* -------------------------------------------------------------------------- */

/**
 * Session tokens used to be stored verbatim in D1. A read-only database leak
 * then handed over live cookies. The cookie is now random and only its SHA-256
 * hash is stored. Legacy rows are upgraded lazily on first use, so deploying
 * this does not sign anyone out.
 */
async function hashSessionToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return toHex(new Uint8Array(digest));
}

let sessionsReady = false;
async function ensureSessionsSchema(): Promise<void> {
  if (sessionsReady) return;
  // A fresh local database may not have run db/schema.sqlite.sql yet. Create the
  // minimal legacy shape first, then add the hardening columns below.
  await sql`
    create table if not exists sessions (
      token      text primary key,
      user_id    integer not null references users(id) on delete cascade,
      expires_at text not null
    )`;
  const columns = await sql`pragma table_info(sessions)`;
  const has = (name: string) => columns.some((c) => String(c.name) === name);
  const additions: Array<[string, string]> = [
    ['token_hash', 'text'],
    ['public_id', 'text'],
    ['created_at', 'text'],
    ['last_seen_at', 'text'],
    ['user_agent', 'text'],
    ['ip_hash', 'text'],
    ['reauth_at', 'text']
  ];
  for (const [name, type] of additions) {
    if (!has(name)) {
      // Fixed allowlisted identifiers only; no request value reaches this DDL.
      try {
        await execLiteral(`alter table sessions add column ${name} ${type}`);
      } catch {
        /* already added by a concurrent isolate */
      }
    }
  }
  // The tagged-template helper cannot interpolate identifiers; these are fixed
  // strings, never user input.
  await sql`create unique index if not exists sessions_token_hash_idx on sessions(token_hash)`;
  await sql`create unique index if not exists sessions_public_id_idx on sessions(public_id)`;

  // Do not mark the schema ready if an ALTER silently failed (for example, a
  // concurrent isolate won the race but this one still sees an old cache).
  // A missing column would otherwise surface as a 500 on the first login.
  const after = await sql`pragma table_info(sessions)`;
  const names = new Set(after.map((c) => String(c.name)));
  if (!additions.every(([name]) => names.has(name))) {
    throw new Error('Session schema is incomplete; refusing to create a session');
  }
  sessionsReady = true;
}

export interface SessionUser {
  userId: number;
  username: string;
  sessionId: string;
  createdAt: string;
  lastSeenAt: string;
  reauthAt: string | null;
}

/** Create a session and return the raw cookie token (never stored). */
export async function createSession(
  userId: number,
  meta: { userAgent?: string | null; ipHash?: string | null } = {}
): Promise<string> {
  await ensureSessionsSchema();
  // Sweep this user's dead tokens first.
  await sql`delete from sessions where user_id = ${userId} and expires_at <= ${new Date().toISOString()}`;
  const token = randomHex(32);
  const tokenHash = await hashSessionToken(token);
  const publicId = randomHex(8);
  const now = nowISO();
  const expires = new Date(Date.now() + SESSION_DAYS * DAY).toISOString();
  await sql`
    insert into sessions
      (token, token_hash, public_id, user_id, expires_at, created_at, last_seen_at, user_agent, ip_hash, reauth_at)
    values
      (${randomHex(16)}, ${tokenHash}, ${publicId}, ${userId}, ${expires}, ${now}, ${now},
       ${meta.userAgent ?? null}, ${meta.ipHash ?? null}, ${now})`;
  return token;
}

/**
 * Resolve a cookie token to its owner, upgrading a legacy plaintext row on the
 * way. Returns null for expired/revoked/idle sessions — never a partial user.
 */
export async function findSession(token: string): Promise<SessionUser | null> {
  if (!token || token.length > 200) return null;
  await ensureSessionsSchema();
  const tokenHash = await hashSessionToken(token);

  let rows = await sql`
    select s.token_hash, s.public_id, s.user_id, s.expires_at, s.created_at, s.last_seen_at,
           s.reauth_at, u.username
    from sessions s join users u on u.id = s.user_id
    where s.token_hash = ${tokenHash}
    limit 1`;

  if (!rows.length) {
    // Pre-hardening row: the cookie itself is the primary key.
    const legacy = await sql`
      select s.token, s.user_id, s.expires_at, u.username
      from sessions s join users u on u.id = s.user_id
      where s.token = ${token}
      limit 1`;
    if (!legacy.length) return null;
    const now = nowISO();
    const publicId = randomHex(8);
    await sql`
      update sessions
      set token_hash = ${tokenHash}, public_id = ${publicId}, token = ${'legacy:' + randomHex(16)},
          created_at = coalesce(created_at, ${now}), last_seen_at = coalesce(last_seen_at, ${now}),
          reauth_at = coalesce(reauth_at, ${now})
      where token = ${token}`;
    rows = await sql`
      select s.token_hash, s.public_id, s.user_id, s.expires_at, s.created_at, s.last_seen_at,
             s.reauth_at, u.username
      from sessions s join users u on u.id = s.user_id
      where s.token_hash = ${tokenHash}
      limit 1`;
  }

  const row = rows[0];
  if (!row) return null;

  const now = Date.now();
  const expires = Date.parse(String(row.expires_at));
  const lastSeen = Date.parse(String(row.last_seen_at ?? row.created_at ?? nowISO()));
  const created = Date.parse(String(row.created_at ?? nowISO()));
  const idleCutoff = now - SESSION_IDLE_DAYS * DAY;
  if (!Number.isFinite(expires) || !Number.isFinite(lastSeen) || expires <= now || lastSeen < idleCutoff) {
    await sql`delete from sessions where token_hash = ${tokenHash}`;
    return null;
  }

  // One update per 15 minutes, not per 1.5s poll.
  const touched = now - lastSeen > 15 * 60_000;
  if (touched) {
    await sql`update sessions set last_seen_at = ${nowISO()} where token_hash = ${tokenHash}`;
  }

  return {
    userId: Number(row.user_id),
    username: String(row.username),
    sessionId: String(row.public_id ?? tokenHash.slice(0, 16)),
    createdAt: Number.isFinite(created) ? new Date(created).toISOString() : nowISO(),
    lastSeenAt: new Date(touched ? now : lastSeen).toISOString(),
    reauthAt: row.reauth_at ? String(row.reauth_at) : null
  };
}

export async function deleteSession(token: string): Promise<void> {
  await ensureSessionsSchema();
  const hash = await hashSessionToken(token);
  await sql`delete from sessions where token_hash = ${hash} or token = ${token}`;
}

/** Sign out every other device (or every device when `keepToken` is absent). */
export async function deleteOtherSessions(userId: number, keepToken?: string | null): Promise<number> {
  await ensureSessionsSchema();
  if (keepToken) {
    const hash = await hashSessionToken(keepToken);
    // `NULL <> ?` is NULL (not true), so legacy rows with no token_hash were
    // skipped by the old predicate. Delete them explicitly; the current row was
    // upgraded by findSession before any route can call this.
    const before = await sql`
      select count(*) as n from sessions
      where user_id = ${userId} and (token_hash is null or token_hash <> ${hash})`;
    await sql`
      delete from sessions
      where user_id = ${userId} and (token_hash is null or token_hash <> ${hash})`;
    return Number(before[0]?.n ?? 0);
  }
  const before = await sql`select count(*) as n from sessions where user_id = ${userId}`;
  await sql`delete from sessions where user_id = ${userId}`;
  return Number(before[0]?.n ?? 0);
}

export interface SessionSummary {
  id: string;
  createdAt: string;
  lastSeenAt: string;
  expiresAt: string;
  userAgent: string | null;
  current: boolean;
}

export async function listSessions(
  userId: number,
  currentToken?: string | null
): Promise<SessionSummary[]> {
  await ensureSessionsSchema();
  const currentHash = currentToken ? await hashSessionToken(currentToken) : null;
  const rows = await sql`
    select token_hash, public_id, created_at, last_seen_at, expires_at, user_agent
    from sessions
    where user_id = ${userId} and expires_at > ${nowISO()}
    order by last_seen_at desc
    limit 100`;
  return rows.map((r) => {
    const hash = String(r.token_hash ?? '');
    const id = String(r.public_id ?? hash.slice(0, 16));
    return {
      id,
      createdAt: String(r.created_at ?? ''),
      lastSeenAt: String(r.last_seen_at ?? r.created_at ?? ''),
      expiresAt: String(r.expires_at),
      userAgent: r.user_agent == null ? null : String(r.user_agent),
      current: Boolean(currentHash && hash === currentHash)
    };
  });
}

/** Revoke one session by its public id. Scoped by user id, always. */
export async function revokeSession(userId: number, sessionId: string): Promise<boolean> {
  await ensureSessionsSchema();
  if (!/^[a-f0-9]{8,64}$/i.test(sessionId)) return false;
  const rows = await sql`
    select token_hash from sessions
    where user_id = ${userId}
      and (public_id = ${sessionId} or substr(token_hash, 1, 16) = ${sessionId})
    limit 1`;
  if (!rows.length) return false;
  await sql`delete from sessions where user_id = ${userId} and token_hash = ${rows[0]!.token_hash}`;
  return true;
}

/** Mark that the owner re-proved the login password on this session. */
export async function markReauth(token: string): Promise<void> {
  await ensureSessionsSchema();
  const hash = await hashSessionToken(token);
  await sql`update sessions set reauth_at = ${nowISO()}, last_seen_at = ${nowISO()} where token_hash = ${hash}`;
}

export async function hasFreshReauth(token: string, maxAgeMs = 5 * 60_000): Promise<boolean> {
  await ensureSessionsSchema();
  const hash = await hashSessionToken(token);
  const rows = await sql`select reauth_at from sessions where token_hash = ${hash} limit 1`;
  const at = rows[0]?.reauth_at ? Date.parse(String(rows[0].reauth_at)) : NaN;
  return Number.isFinite(at) && Date.now() - at <= maxAgeMs;
}

/**
 * `secure` is decided per request rather than pinned off, so a plain-HTTP
 * localhost dev backend works without weakening the production cookie.
 */
export function cookieOptions(url?: URL) {
  const isLocal =
    !!url && (url.protocol === 'http:' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1'));
  return {
    path: '/',
    httpOnly: true,
    sameSite: 'strict' as const,
    secure: !isLocal,
    maxAge: 60 * 60 * 24 * SESSION_DAYS
  };
}
