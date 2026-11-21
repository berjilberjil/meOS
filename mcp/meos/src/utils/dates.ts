/** UTC ↔ `yyyy-MM-dd` helpers that never use the host's locale rules for math. */

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * The owner's calendar day. MeOS stores day keys, not instants, so a gateway
 * running on a server in another timezone must still answer with the owner's
 * "today". Set `MEOS_TIMEZONE` (an IANA name) when the host is not in that zone.
 */
const TIME_ZONE = process.env.MEOS_TIMEZONE?.trim() || undefined;

function zonedParts(date: Date): { y: number; m: number; d: number; h: number; min: number; s: number } {
  if (!TIME_ZONE) {
    return {
      y: date.getFullYear(),
      m: date.getMonth() + 1,
      d: date.getDate(),
      h: date.getHours(),
      min: date.getMinutes(),
      s: date.getSeconds()
    };
  }
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(date);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  return { y: get('year'), m: get('month'), d: get('day'), h: get('hour'), min: get('minute'), s: get('second') };
}

export function isDateKey(value: string): boolean {
  if (!DAY_RE.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const dt = new Date(Date.UTC(y!, m! - 1, d!));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m! - 1 && dt.getUTCDate() === d;
}

export function assertDateKey(value: string, field = 'date'): string {
  if (!isDateKey(value)) {
    throw new Error(`${field} must be yyyy-MM-dd`);
  }
  return value;
}

export function dateKey(date = new Date()): string {
  const p = zonedParts(date);
  return `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
}

export function todayKey(date = new Date()): string {
  return dateKey(date);
}

export function addDays(key: string, days: number): string {
  const [y, m, d] = key.split('-').map(Number);
  const dt = new Date(Date.UTC(y!, m! - 1, d!));
  dt.setUTCDate(dt.getUTCDate() + days);
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}

export function dayDelta(from: string, to: string): number {
  const a = Date.parse(`${from}T00:00:00Z`);
  const b = Date.parse(`${to}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

/** Native MeOS: 0 = Sunday … 6 = Saturday. */
export function weekdayKey(key: string): string {
  const [y, m, d] = key.split('-').map(Number);
  return String(new Date(Date.UTC(y!, m! - 1, d!)).getUTCDay());
}

/** The app's stamp format: `yyyy-MM-dd'T'HH:mm:ss` in the owner's timezone. */
export function nowStamp(date = new Date()): string {
  const p = zonedParts(date);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${p.y}-${pad(p.m)}-${pad(p.d)}T${pad(p.h)}:${pad(p.min)}:${pad(p.s)}`;
}

export function monthPrefix(key: string): string {
  return key.slice(0, 7);
}

export function nowMinutes(date = new Date()): number {
  const p = zonedParts(date);
  return p.h * 60 + p.min;
}

export function timeToMinutes(time: string | null | undefined): number | null {
  if (!time) return null;
  const m = /^(\d{2}):(\d{2})$/.exec(time);
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}
