import type {
  BelongingItem,
  EventItem,
  FocusItem,
  Note,
  Profile,
  TrashEntry
} from '../schemas/models.ts';
import { DEFAULT_PROFILE } from '../schemas/models.ts';
import { hasScope } from '../auth/scopes.ts';
import { errors } from '../utils/errors.ts';
import type { ToolContext } from './registry.ts';
import { nowStamp, todayKey } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import { STATE_KEYS } from '../schemas/models.ts';

export async function readArray<T>(ctx: ToolContext, key: string): Promise<T[]> {
  const value = await ctx.services.store.read<T[]>(key);
  return Array.isArray(value) ? value : [];
}

export async function readObject<T>(ctx: ToolContext, key: string, fallback: T): Promise<T> {
  const value = await ctx.services.store.read<T>(key);
  return value && typeof value === 'object' ? value : fallback;
}

export function requireId(value: string, field = 'id'): string {
  const id = value.trim().toLowerCase();
  if (!id || !/^[a-z0-9._-]{1,120}$/i.test(id)) throw errors.invalidInput(`${field} is not a valid MeOS id`);
  return id;
}

export function cleanText(value: string, field: string, max = 4000): string {
  const text = value.replace(/\r\n/g, '\n').trim();
  if (!text) throw errors.invalidInput(`${field} must not be empty`);
  if (text.length > max) throw errors.invalidInput(`${field} must be at most ${max} characters`);
  return text;
}

export function assertOneOf<T extends string>(value: string, allowed: readonly T[], field: string): T {
  if (!(allowed as readonly string[]).includes(value)) {
    throw errors.invalidInput(`${field} must be one of: ${allowed.join(', ')}`);
  }
  return value as T;
}

/* ------------------------------------------------------------------ */
/* Identity / privacy                                                  */
/* ------------------------------------------------------------------ */

export function publicProfile(profile: Profile | null, includeSensitive: boolean): Record<string, unknown> {
  const p = { ...DEFAULT_PROFILE, ...(profile ?? {}) };
  const base: Record<string, unknown> = {
    name: p.name,
    city: p.city,
    hometown: p.hometown,
    role: p.role,
    work: p.work,
    education: p.education,
    links: { website: p.website, instagram: p.instagram, github: p.github },
    goals: { short: p.goalsShort, mid: p.goalsMid, long: p.goalsLong },
    achievements: p.achievements,
    habits: p.habits
  };
  if (includeSensitive) {
    base.identity = {
      dob: p.dob,
      age: p.age ?? null,
      blood_group: p.bloodGroup,
      relationship: p.relationship,
      phone: p.phone,
      email: p.email
    };
    base.health_notes = p.healthNotes;
    base.about = p.about;
    base.has_photo = Boolean(p.photoBase64);
    // The photo itself is never returned. It is large, personal, and can be
    // reconstructed from other apps; an agent has no need for the bytes.
  }
  return base;
}

export function noteForClient(note: Note, canReadLocked: boolean): Record<string, unknown> {
  if (note.locked && !canReadLocked) {
    return {
      id: note.id,
      title: '[locked]',
      body: null,
      locked: true,
      pinned: note.pinned,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      redacted: true
    };
  }
  return {
    id: note.id,
    title: note.title,
    body: note.body,
    locked: note.locked,
    pinned: note.pinned,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    has_rich_content: Boolean(note.content)
  };
}

export function canReadLockedNotes(ctx: ToolContext): boolean {
  return hasScope(ctx.client.scopes, 'secret');
}

/* ------------------------------------------------------------------ */
/* Recycle bin                                                         */
/* ------------------------------------------------------------------ */

export interface RecycleInput {
  kind: TrashEntry['kind'];
  itemID: string;
  title: string;
  subtitle?: string;
  payload: unknown;
  context?: string | null;
  mediaKeys?: string[];
}

export function trashEntry(input: RecycleInput): TrashEntry {
  return {
    id: newId(),
    itemID: input.itemID,
    kind: input.kind,
    title: input.title.trim() || `Untitled ${input.kind}`,
    subtitle: input.subtitle ?? '',
    deletedAt: nowStamp(),
    payload: JSON.stringify(input.payload ?? null),
    context: input.context ?? null,
    mediaKeys: input.mediaKeys ?? []
  };
}

/**
 * Capture first, remove second. If the module write fails, the bin entry is
 * rolled back so a failed delete never leaves a phantom entry — and more
 * importantly, the original record is still in place.
 */
export async function recycleAndRemove<M>(
  ctx: ToolContext,
  opts: {
    moduleKey: string;
    entry: TrashEntry;
    fallback: M;
    remove: (current: M) => M;
  }
): Promise<void> {
  await ctx.services.store.update<TrashEntry[]>(STATE_KEYS.trash, (current) => [
    opts.entry,
    ...(Array.isArray(current) ? current : [])
  ]);

  try {
    await ctx.services.store.update<M>(opts.moduleKey, (current) => opts.remove(current ?? opts.fallback));
  } catch (e) {
    // Best-effort rollback. If this also fails the record is still intact and
    // the bin has a harmless extra row the user can purge.
    try {
      await ctx.services.store.update<TrashEntry[]>(STATE_KEYS.trash, (current) =>
        (Array.isArray(current) ? current : []).filter((x) => x.id !== opts.entry.id)
      );
    } catch {
      /* leave it */
    }
    throw e;
  }
}

export function liveTrash(entries: TrashEntry[], today = todayKey()): TrashEntry[] {
  return entries
    .filter((e) => {
      const day = (e.deletedAt ?? '').slice(0, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return true; // unparseable stamps linger, never vanish
      const delta = (Date.parse(`${today}T00:00:00Z`) - Date.parse(`${day}T00:00:00Z`)) / 86_400_000;
      return delta < 30;
    })
    .sort((a, b) => (b.deletedAt ?? '').localeCompare(a.deletedAt ?? ''));
}

export function daysLeftInTrash(entry: TrashEntry, today = todayKey()): number {
  const day = (entry.deletedAt ?? '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return 30;
  const delta = (Date.parse(`${today}T00:00:00Z`) - Date.parse(`${day}T00:00:00Z`)) / 86_400_000;
  return Math.max(0, 30 - delta);
}

/* ------------------------------------------------------------------ */
/* Events                                                              */
/* ------------------------------------------------------------------ */

export function sortEvents(events: EventItem[]): EventItem[] {
  return [...events].sort((a, b) => {
    if (a.date !== b.date) return a.date.localeCompare(b.date);
    const at = a.time ?? '';
    const bt = b.time ?? '';
    if (at !== bt) return at.localeCompare(bt);
    return a.title.localeCompare(b.title);
  });
}

export function eventForClient(event: EventItem): Record<string, unknown> {
  return {
    id: event.id,
    date: event.date,
    time: event.time ?? null,
    title: event.title,
    tag_ids: event.tagIDs,
    note: event.note,
    special: event.special,
    recurrence: event.recurrence,
    reminders: event.reminders,
    media_count: event.media.length,
    has_media: event.media.length > 0
  };
}

/* ------------------------------------------------------------------ */
/* Tasks                                                               */
/* ------------------------------------------------------------------ */

export function taskOwner(days: Record<string, { todos?: FocusItem[] }>, id: string): string | null {
  for (const [day, plan] of Object.entries(days)) {
    if ((plan?.todos ?? []).some((t) => t.id === id)) return day;
  }
  return null;
}

/* ------------------------------------------------------------------ */
/* Stuff / purchases                                                   */
/* ------------------------------------------------------------------ */

const DEFAULT_SALARY_PAISE = 4_000_000;

export interface BelongingSnapshot {
  ownedDays: number;
  progress: number;
  daysLeft: number;
  actualPerDayPaise: number;
  plannedPerDayPaise: number;
}

export function belongingSnapshot(item: BelongingItem, today = todayKey()): BelongingSnapshot {
  const bought = item.boughtOn?.slice(0, 10) ?? '';
  const a = /^\d{4}-\d{2}-\d{2}$/.test(bought) ? Date.parse(`${bought}T00:00:00Z`) : NaN;
  const b = Date.parse(`${today}T00:00:00Z`);
  const owned = Number.isFinite(a) ? Math.max(1, Math.round((b - a) / 86_400_000) + 1) : 1;
  const life = Math.max(1, item.lifeDays || 1);
  const perDay = (price: number, days: number) => (days > 0 ? Math.round(price / days) : price);
  return {
    ownedDays: owned,
    progress: Math.min(1, owned / life),
    daysLeft: Math.max(0, life - owned),
    actualPerDayPaise: perDay(item.pricePaise, owned),
    plannedPerDayPaise: perDay(item.pricePaise, life)
  };
}

export function monthlyBurnPaise(items: BelongingItem[]): number {
  return items.reduce((sum, item) => {
    const life = Math.max(1, item.lifeDays);
    return sum + Math.round(item.pricePaise / life) * 30;
  }, 0);
}

export function spendHealth(burn: number, salary: number): 'good' | 'tight' | 'over' {
  if (salary <= 0) return burn === 0 ? 'good' : 'over';
  if (burn * 2 <= salary) return 'good';
  if (burn < salary) return 'tight';
  return 'over';
}

export function purchaseForClient(item: BelongingItem, today = todayKey()): Record<string, unknown> {
  const snap = belongingSnapshot(item, today);
  return {
    id: item.id,
    name: item.name,
    link: item.link,
    category: item.categoryID,
    price_inr: item.pricePaise / 100,
    bought_on: item.boughtOn,
    roi_months: Math.max(1, Math.round(item.lifeDays / 30)),
    note: item.note,
    retired: item.retired,
    has_bill: Boolean(item.photoBase64),
    roi: {
      days_owned: snap.ownedDays,
      progress: snap.progress,
      days_left: snap.daysLeft,
      paid_off: snap.daysLeft === 0,
      cost_per_day_inr: snap.actualPerDayPaise / 100,
      planned_per_day_inr: snap.plannedPerDayPaise / 100
    }
  };
}

export const DEFAULT_SALARY = DEFAULT_SALARY_PAISE;
