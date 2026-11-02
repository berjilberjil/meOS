import { nowISO, sql } from './db';

/**
 * The devices signed into one account.
 *
 * This is deliberately NOT part of the encrypted state blob. The blob is one
 * document per module, written only after a vault is unlocked; a device that is
 * sitting at the passphrase screen must still appear here, and "last active"
 * has to advance without every device racing to rewrite the same document.
 * Nothing stored here is vault data — a name, an OS version and two timestamps.
 */

export type DeviceKind = 'mac' | 'iphone';

export type DeviceRegistration = {
  id: string;
  systemName: string;
  platform: string;
  kind: DeviceKind;
  appVersion: string;
};

export type AccountDevice = DeviceRegistration & {
  name: string;
  createdAt: string;
  lastSeen: string;
};

export type ParseResult<T> =
  | { ok: true; value: T }
  | { ok: false; message: string };

const ID_RE = /^[a-z0-9-]{8,64}$/i;

/**
 * One idempotent DDL per process, like `ensureAttempts` in auth.ts. Production
 * D1 already has the tables from schema.sqlite.sql, but a database created
 * before this feature existed (or a fresh local one) does not, and a failed
 * first heartbeat should not require a manual `wrangler d1 execute`.
 *
 * A boolean, not a memoized promise: a promise awaited by a second request
 * would be I/O owned by the first request, which the Workers runtime rejects.
 */
let ensured = false;
async function ensureDevicesTable(): Promise<void> {
  if (ensured) return;
  await sql`
    create table if not exists devices (
      user_id     integer not null references users(id) on delete cascade,
      id          text not null,
      name        text not null,
      system_name text not null,
      platform    text not null,
      kind        text not null,
      app_version text not null default '',
      created_at  text not null,
      last_seen   text not null,
      primary key (user_id, id)
    )`;
  await sql`create index if not exists devices_user_seen_idx on devices(user_id, last_seen)`;
  ensured = true;
}

/** A single line of user/device text, without control characters. */
function text(value: unknown, max: number): string {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .trim()
    .slice(0, max);
}

/**
 * Validate a heartbeat body. The client is the only writer, but this endpoint
 * is public behind the session cookie, so the shape is checked here rather
 * than trusted: the id becomes part of a primary key and the kind decides
 * which icon the account's other devices draw.
 */
export function parseDeviceRegistration(body: unknown): ParseResult<DeviceRegistration> {
  const b = (body ?? {}) as Record<string, unknown>;
  // Check the id BEFORE any trimming/capping helper: silently turning a
  // 65-character id into a different 64-character one would make the same
  // install look like a new device on every heartbeat.
  const id = typeof b.id === 'string' ? b.id.trim() : '';
  if (id.length < 8 || id.length > 64 || !ID_RE.test(id)) {
    return { ok: false, message: 'A device needs a valid id' };
  }

  const kind: DeviceKind | null =
    b.kind === 'iphone' ? 'iphone' : b.kind === 'mac' ? 'mac' : null;
  if (!kind) return { ok: false, message: 'Unknown device type' };

  const fallbackName = kind === 'iphone' ? 'iPhone' : 'Mac';
  const fallbackPlatform = kind === 'iphone' ? 'iOS' : 'macOS';

  return {
    ok: true,
    value: {
      id,
      systemName: text(b.systemName, 80) || fallbackName,
      platform: text(b.platform, 80) || fallbackPlatform,
      kind,
      appVersion: text(b.appVersion, 40)
    }
  };
}

/** A user-typed device name. Null means "not a usable name". */
export function parseDeviceName(value: unknown): string | null {
  const name = text(value, 60);
  return name.length ? name : null;
}

/* eslint-disable @typescript-eslint/no-explicit-any */
function toDevice(row: Record<string, any>): AccountDevice {
  return {
    id: String(row.id),
    name: String(row.name),
    systemName: String(row.system_name),
    platform: String(row.platform),
    kind: row.kind === 'iphone' ? 'iphone' : 'mac',
    appVersion: String(row.app_version ?? ''),
    createdAt: String(row.created_at),
    lastSeen: String(row.last_seen)
  };
}
/* eslint-enable @typescript-eslint/no-explicit-any */

export async function listDevices(userId: number): Promise<AccountDevice[]> {
  await ensureDevicesTable();
  const rows = await sql`
    select id, name, system_name, platform, kind, app_version, created_at, last_seen
    from devices
    where user_id = ${userId}
    order by last_seen desc
    limit 100`;
  return rows.map(toDevice);
}

/**
 * Register this install, or refresh what the server knows about it.
 *
 * `on conflict ... do update` makes concurrent heartbeats from the same device
 * (a launch and a foreground event can overlap) harmless. The update refreshes
 * the automatically detected facts but never `name` — that field belongs to the
 * person, and a heartbeat must not undo a rename.
 */
export async function registerDevice(
  userId: number,
  input: DeviceRegistration
): Promise<AccountDevice> {
  await ensureDevicesTable();
  const now = nowISO();
  await sql`
    insert into devices
      (user_id, id, name, system_name, platform, kind, app_version, created_at, last_seen)
    values
      (${userId}, ${input.id}, ${input.systemName}, ${input.systemName},
       ${input.platform}, ${input.kind}, ${input.appVersion}, ${now}, ${now})
    on conflict (user_id, id) do update set
      system_name = excluded.system_name,
      platform    = excluded.platform,
      kind        = excluded.kind,
      app_version = excluded.app_version,
      last_seen   = excluded.last_seen`;

  const rows = await sql`
    select id, name, system_name, platform, kind, app_version, created_at, last_seen
    from devices
    where user_id = ${userId} and id = ${input.id}`;
  return toDevice(rows[0]);
}

/** Rename one device belonging to this account. Null when it does not exist. */
export async function renameDevice(
  userId: number,
  id: string,
  name: string
): Promise<AccountDevice | null> {
  const clean = parseDeviceName(name);
  if (!clean) return null;

  await ensureDevicesTable();
  const rows = await sql`
    select id, name, system_name, platform, kind, app_version, created_at, last_seen
    from devices
    where user_id = ${userId} and id = ${id}`;
  if (!rows.length) return null;

  await sql`
    update devices set name = ${clean}
    where user_id = ${userId} and id = ${id}`;
  return toDevice({ ...rows[0], name: clean });
}
