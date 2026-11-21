/**
 * Port of the pure parts of `EventRecurrence.swift` and `EventNotifier.swift`.
 *
 * Occurrences are projected, never stored. The day-of-month is always taken from
 * the anchor and clamped to the target month, so a 31st-of-the-month event runs
 * 31 Jan → 28 Feb → 31 Mar and a 29 Feb birthday returns on the next leap year.
 */

export type RecurrenceUnit = 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly';

export interface Recurrence {
  unit: RecurrenceUnit;
  interval: number;
  until?: string | null;
}

export const REMINDER_LEADS = ['sameDay', 'oneDay', 'twoDays', 'threeDays', 'oneWeek', 'twoWeeks', 'thirtyDays'] as const;
export type ReminderLeadName = (typeof REMINDER_LEADS)[number];

export const REMINDER_DAYS: Record<ReminderLeadName, number> = {
  sameDay: 0,
  oneDay: 1,
  twoDays: 2,
  threeDays: 3,
  oneWeek: 7,
  twoWeeks: 14,
  thirtyDays: 30
};

export function reminderLabel(lead: ReminderLeadName): string {
  const d = REMINDER_DAYS[lead];
  if (d === 0) return 'On the day';
  if (d === 1) return '1 day before';
  if (d === 7) return '1 week before';
  if (d === 14) return '2 weeks before';
  if (d === 30) return '30 days before';
  return `${d} days before`;
}

export function normalizeRecurrence(input: Partial<Recurrence> | undefined): Recurrence {
  const unit = (input?.unit ?? 'none') as RecurrenceUnit;
  if (!['none', 'daily', 'weekly', 'monthly', 'yearly'].includes(unit)) {
    throw new Error('recurrence.unit must be none, daily, weekly, monthly or yearly');
  }
  const interval = Math.max(1, Math.trunc(input?.interval ?? 1));
  return { unit, interval, until: input?.until ?? null };
}

interface Parts {
  y: number;
  m: number;
  d: number;
}

function parts(key: string): Parts | null {
  const f = key.split('-');
  if (f.length !== 3 || f[0]!.length !== 4) return null;
  const y = Number(f[0]);
  const m = Number(f[1]);
  const d = Number(f[2]);
  if (!Number.isInteger(y) || m < 1 || m > 12 || d < 1 || d > 31) return null;
  if (d > daysIn(y, m)) return null;
  return { y, m, d };
}

function daysIn(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function keyOf(y: number, m: number, d: number): string {
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

function addDays(key: string, days: number): string {
  const [y, m, d] = key.split('-').map(Number);
  const dt = new Date(Date.UTC(y!, m! - 1, d!));
  dt.setUTCDate(dt.getUTCDate() + days);
  return keyOf(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
}

function dayDelta(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
}

function nextByDays(anchor: string, step: number, onOrAfter: string): string | null {
  if (step <= 0) return null;
  const delta = dayDelta(anchor, onOrAfter);
  if (!Number.isFinite(delta)) return null;
  if (delta <= 0) return anchor;
  const steps = Math.ceil(delta / step);
  return addDays(anchor, steps * step);
}

function nextByMonths(anchor: Parts, step: number, onOrAfter: string): string | null {
  if (step <= 0) return null;
  const target = parts(onOrAfter);
  if (!target) return null;

  const anchorMonths = anchor.y * 12 + (anchor.m - 1);
  const targetMonths = target.y * 12 + (target.m - 1);
  let steps = Math.max(0, Math.ceil((targetMonths - anchorMonths) / step));

  for (let i = 0; i <= 4; i++) {
    const total = anchorMonths + steps * step;
    const y = Math.floor(total / 12);
    const m = (total % 12) + 1;
    const day = Math.min(anchor.d, daysIn(y, m));
    const candidate = keyOf(y, m, day);
    if (candidate >= onOrAfter) return candidate;
    steps += 1;
  }
  return null;
}

export function nextOccurrence(
  event: { date: string; recurrence?: Recurrence | null },
  onOrAfter: string
): string | null {
  const anchor = parts(event.date);
  if (!anchor) return null;
  const rule = event.recurrence ?? { unit: 'none', interval: 1 };

  if (rule.unit === 'none') return event.date >= onOrAfter ? event.date : null;
  if (!parts(onOrAfter)) return null;

  let candidate: string | null = null;
  switch (rule.unit) {
    case 'daily':
      candidate = nextByDays(event.date, Math.max(1, rule.interval), onOrAfter);
      break;
    case 'weekly':
      candidate = nextByDays(event.date, Math.max(1, rule.interval) * 7, onOrAfter);
      break;
    case 'monthly':
      candidate = nextByMonths(anchor, Math.max(1, rule.interval), onOrAfter);
      break;
    case 'yearly':
      candidate = nextByMonths(anchor, Math.max(1, rule.interval) * 12, onOrAfter);
      break;
  }
  if (!candidate) return null;
  if (rule.until && rule.until.length >= 10 && candidate > rule.until) return null;
  return candidate;
}

export function occurrences(
  event: { date: string; recurrence?: Recurrence | null },
  from: string,
  to: string,
  cap = 400
): string[] {
  if (from > to) return [];
  const out: string[] = [];
  let cursor = from;
  while (out.length < cap) {
    const day = nextOccurrence(event, cursor);
    if (!day || day > to) break;
    out.push(day);
    if (!event.recurrence || event.recurrence.unit === 'none') break;
    cursor = addDays(day, 1);
  }
  return out;
}

export function describeRecurrence(rule: Recurrence | undefined): string {
  if (!rule || rule.unit === 'none') return 'Does not repeat';
  const n = Math.max(1, rule.interval);
  const unit = rule.unit;
  if (n === 1) {
    return { daily: 'Every day', weekly: 'Every week', monthly: 'Every month', yearly: 'Every year', none: 'Does not repeat' }[
      unit
    ];
  }
  const plural = { daily: 'days', weekly: 'weeks', monthly: 'months', yearly: 'years', none: 'never' }[unit];
  return `Every ${n} ${plural}${rule.until ? `, until ${rule.until}` : ''}`;
}

export interface ReminderPlan {
  event_id: string;
  title: string;
  lead: ReminderLeadName;
  days_before: number;
  occurrence: string;
  fires_on: string;
  fires_at: string;
}

/**
 * The next fire for each (event, lead), soonest first. Mirrors the app's rule
 * that a warning already in the past is skipped, and that only the next
 * occurrence of each lead is planned.
 */
export function reminderPlan(
  events: Array<{ id: string; date: string; title: string; time?: string | null; reminders?: string[]; recurrence?: Recurrence | null }>,
  today: string,
  limit = 48,
  nowMinutes = 0
): ReminderPlan[] {
  const out: ReminderPlan[] = [];
  for (const event of events) {
    if (!event.reminders?.length) continue;
    const leads = [...new Set(event.reminders)].filter((l): l is ReminderLeadName => l in REMINDER_DAYS);
    const at = /^\d{2}:\d{2}$/.test(event.time ?? '') ? event.time! : '09:00';
    const [hh, mm] = at.split(':').map(Number);
    const fireMinutes = hh! * 60 + mm!;

    for (const lead of leads) {
      const days = REMINDER_DAYS[lead];
      let probe = addDays(today, days);
      for (let i = 0; i < 2; i++) {
        const occurrence = nextOccurrence(event, probe);
        if (!occurrence) break;
        const firesOn = addDays(occurrence, -days);
        const inFuture = firesOn > today || (firesOn === today && fireMinutes > nowMinutes);
        if (inFuture) {
          out.push({
            event_id: event.id,
            title: event.title,
            lead,
            days_before: days,
            occurrence,
            fires_on: firesOn,
            fires_at: at
          });
          break;
        }
        probe = addDays(occurrence, 1);
      }
    }
  }
  out.sort((a, b) => `${a.fires_on}T${a.fires_at}`.localeCompare(`${b.fires_on}T${b.fires_at}`) || a.event_id.localeCompare(b.event_id));
  return out.slice(0, limit);
}
