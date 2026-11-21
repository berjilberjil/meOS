import { z } from 'zod';
import { STATE_KEYS, type EventItem, type EventTag } from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { addDays, assertDateKey, dayDelta, nowMinutes, todayKey, timeToMinutes } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import {
  REMINDER_DAYS,
  REMINDER_LEADS,
  describeRecurrence,
  nextOccurrence,
  normalizeRecurrence,
  occurrences,
  reminderLabel,
  reminderPlan
} from '../utils/recurrence.ts';
import type { ToolDefinition } from './registry.ts';
import { cleanText, eventForClient, readArray, recycleAndRemove, sortEvents, trashEntry } from './shared.ts';

const DEFAULT_TAGS: EventTag[] = [
  { id: 'personal', name: 'Personal', symbol: 'person.fill', colorHex: '58CC02', builtIn: true },
  { id: 'travel', name: 'Travel', symbol: 'airplane', colorHex: '1CB0F6', builtIn: true },
  { id: 'family', name: 'Family', symbol: 'house.fill', colorHex: 'FF9600', builtIn: true },
  { id: 'work', name: 'Work', symbol: 'briefcase.fill', colorHex: 'FFC800', builtIn: true },
  { id: 'milestone', name: 'Milestone', symbol: 'flag.fill', colorHex: 'CE82FF', builtIn: true },
  { id: 'reminder', name: 'Reminder', symbol: 'bell.fill', colorHex: '84D8FF', builtIn: true },
  { id: 'other', name: 'Other', symbol: 'calendar', colorHex: '9A9A9A', builtIn: true }
];

const RecurrenceInput = z.object({
  unit: z.enum(['none', 'daily', 'weekly', 'monthly', 'yearly']),
  interval: z.number().int().min(1).max(99).optional(),
  until: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional()
});

const RemindersInput = z.array(z.enum(REMINDER_LEADS as unknown as [string, ...string[]])).max(7);

function normalizeReminders(input: string[] | undefined): string[] {
  if (input === undefined) return [];
  return [...new Set(input)].filter((r) => r in REMINDER_DAYS);
}

function normalizeTags(input: string[] | undefined, tags: EventTag[]): string[] {
  if (input === undefined) return ['personal'];
  const known = new Set(tags.map((t) => t.id));
  const out = [...new Set(input.map((t) => t.trim()).filter(Boolean))];
  const unknown = out.filter((t) => !known.has(t));
  if (unknown.length) {
    throw errors.invalidInput(`Unknown tag(s): ${unknown.join(', ')}. Known: ${[...known].join(', ')}`);
  }
  return out;
}

function eventDetail(event: EventItem, tags: EventTag[]) {
  const tagNames = event.tagIDs.map((id) => tags.find((t) => t.id === id)?.name ?? id);
  return {
    ...eventForClient(event),
    tag_names: tagNames,
    recurrence_description: describeRecurrence(event.recurrence),
    reminder_labels: (event.reminders ?? []).map((r) => ({ lead: r, label: reminderLabel(r as keyof typeof REMINDER_DAYS) })),
    next_occurrence: nextOccurrence(event, todayKey()),
    upcoming_occurrences: occurrences(event, todayKey(), addDays(todayKey(), 365), 100)
  };
}

export const eventTools: ToolDefinition[] = [
  {
    name: 'meos_events_list',
    title: 'List events',
    description:
      'List MeOS life events (past, present and future). Filter by date range, tag, or text. Recurrence is stored as a rule and projected on read — repeated occurrences are not duplicated in storage.',
    inputSchema: {
      from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      tag: z.string().max(60).optional(),
      query: z.string().max(200).optional(),
      expand: z.boolean().optional().describe('Expand recurrence rules into occurrences inside the range (default false).'),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const events = await readArray<EventItem>(ctx, STATE_KEYS.events);
      let from = args.from ? assertDateKey(args.from, 'from') : null;
      let to = args.to ? assertDateKey(args.to, 'to') : null;
      const tag = String(args.tag ?? '').trim();
      const q = String(args.query ?? '').trim().toLowerCase();

      const matching = events.filter((e) => {
        if (!args.expand && from && e.date < from) return false;
        if (!args.expand && to && e.date > to) return false;
        if (tag && !(e.tagIDs ?? []).some((t) => t.toLowerCase() === tag.toLowerCase())) return false;
        if (q && ![e.title, e.note].some((v) => String(v ?? '').toLowerCase().includes(q))) return false;
        return true;
      });

      let rows: Array<Record<string, unknown>>;
      if (args.expand) {
        if (!from && !to) {
          from = todayKey();
          to = addDays(from, 365);
        } else if (from && !to) {
          to = addDays(from, 365);
        } else if (!from && to) {
          from = addDays(to, -365);
        }
        const start = from!;
        const end = to!;
        if (start > end) throw errors.invalidInput('from must be on or before to');
        rows = matching
          .flatMap((e) =>
            occurrences(e, start, end, 400).map((day) => ({
              ...eventForClient(e),
              date: day,
              occurrence: day,
              recurring: (e.recurrence?.unit ?? 'none') !== 'none'
            }))
          )
          .sort((a, b) => String(a.date).localeCompare(String(b.date)));
      } else {
        rows = sortEvents(matching).map((e) => eventForClient(e));
      }

      const page = paginate(rows, args.limit, args.cursor);
      return ok({
        ...page,
        items: page.items,
        total_matching: rows.length,
        expanded: Boolean(args.expand)
      });
    }
  },

  {
    name: 'meos_events_get',
    title: 'Get an event',
    description: 'Read one event with its tags, recurrence description, reminder leads, and the next year of projected occurrences.',
    inputSchema: { id: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const events = await readArray<EventItem>(ctx, STATE_KEYS.events);
      const tags = await readArray<EventTag>(ctx, STATE_KEYS.eventTags);
      const event = events.find((e) => e.id === String(args.id).toLowerCase());
      if (!event) throw errors.notFound('Event');
      return ok(eventDetail(event, tags.length ? tags : DEFAULT_TAGS));
    }
  },

  {
    name: 'meos_events_create',
    title: 'Create an event',
    description:
      'Create a life event. Recurrence is a rule (daily/weekly/monthly/yearly) with an optional end date; reminders are lead times the app schedules locally. Creating an event never touches other events\' reminders.',
    inputSchema: {
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      title: z.string().min(1).max(200),
      time: z.string().regex(/^\d{2}:\d{2}$/).nullable().optional().describe('HH:mm. Omit for an all-day event.'),
      note: z.string().max(10000).optional(),
      tag_ids: z.array(z.string().max(60)).max(20).optional(),
      special: z.boolean().optional(),
      recurrence: RecurrenceInput.optional(),
      reminders: RemindersInput.optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const date = assertDateKey(args.date);
      const title = cleanText(args.title, 'title', 200);
      if (args.time && timeToMinutes(args.time) == null) throw errors.invalidInput('time must be HH:mm');
      const tags = await readArray<EventTag>(ctx, STATE_KEYS.eventTags);
      const knownTags = tags.length ? tags : DEFAULT_TAGS;

      const event: EventItem = {
        id: newId(),
        date,
        title,
        tagIDs: normalizeTags(args.tag_ids, knownTags),
        note: String(args.note ?? '').slice(0, 10000),
        media: [],
        special: args.special === true,
        time: args.time ?? null,
        recurrence: normalizeRecurrence(args.recurrence),
        reminders: normalizeReminders(args.reminders),
        category: 'personal',
        done: false
      };

      await ctx.services.store.update<EventItem[]>(STATE_KEYS.events, (current) => [...(current ?? []), event]);
      return ok(
        { event: eventDetail(event, knownTags) },
        {
          written: STATE_KEYS.events,
          notifications: 'The MeOS app rebuilds local notification schedules from meos.events. This tool never clears unrelated reminders.'
        }
      );
    }
  },

  {
    name: 'meos_events_update',
    title: 'Update an event',
    description:
      'Change an event. Only supplied fields are touched. If reminders are omitted they are preserved exactly; if provided, only this event\'s reminder leads change. Other events and the device notification schedule are never cleared.',
    inputSchema: {
      id: z.string().min(1),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      title: z.string().min(1).max(200).optional(),
      time: z.string().regex(/^\d{2}:\d{2}$/).nullable().optional(),
      note: z.string().max(10000).optional(),
      tag_ids: z.array(z.string().max(60)).max(20).optional(),
      special: z.boolean().optional(),
      recurrence: RecurrenceInput.optional(),
      reminders: RemindersInput.optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const events = await readArray<EventItem>(ctx, STATE_KEYS.events);
      const tags = await readArray<EventTag>(ctx, STATE_KEYS.eventTags);
      const knownTags = tags.length ? tags : DEFAULT_TAGS;
      const existing = events.find((e) => e.id === id);
      if (!existing) throw errors.notFound('Event');
      if (args.time !== undefined && args.time !== null && timeToMinutes(args.time) == null) {
        throw errors.invalidInput('time must be HH:mm');
      }

      let updated: EventItem | null = null;
      await ctx.services.store.update<EventItem[]>(STATE_KEYS.events, (current) =>
        (current ?? []).map((e) => {
          if (e.id !== id) return e;
          updated = {
            ...e,
            date: args.date !== undefined ? assertDateKey(args.date) : e.date,
            title: args.title !== undefined ? cleanText(args.title, 'title', 200) : e.title,
            time: args.time !== undefined ? args.time : e.time,
            note: args.note !== undefined ? String(args.note).slice(0, 10000) : e.note,
            tagIDs: args.tag_ids !== undefined ? normalizeTags(args.tag_ids, knownTags) : e.tagIDs,
            special: args.special !== undefined ? Boolean(args.special) : e.special,
            recurrence: args.recurrence !== undefined ? normalizeRecurrence(args.recurrence) : e.recurrence,
            reminders: args.reminders !== undefined ? normalizeReminders(args.reminders) : e.reminders
          };
          return updated;
        })
      );
      return ok(
        { event: eventDetail(updated!, knownTags) },
        {
          written: STATE_KEYS.events,
          notifications: 'Only this event changed. Device notification schedules are rebuilt by the app.'
        }
      );
    }
  },

  {
    name: 'meos_events_delete',
    title: 'Delete an event',
    description:
      'Move an event to the MeOS recycle bin (30 days), keeping its media keys open so a restore restores the pictures too. Requires destructive scope and confirm=true.',
    inputSchema: { id: z.string().min(1), confirm: z.boolean().optional() },
    scopes: ['write', 'destructive'],
    destructive: true,
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const events = await readArray<EventItem>(ctx, STATE_KEYS.events);
      const event = events.find((e) => e.id === id);
      if (!event) throw errors.notFound('Event');
      const mediaKeys = (event.media ?? [])
        .flatMap((m) => [m.r2Key, m.posterKey])
        .filter((k): k is string => Boolean(k));
      const entry = trashEntry({
        kind: 'event',
        itemID: event.id,
        title: event.title,
        subtitle: event.date,
        payload: event,
        mediaKeys
      });
      await recycleAndRemove<EventItem[]>(ctx, {
        moduleKey: STATE_KEYS.events,
        entry,
        fallback: [],
        remove: (items) => items.filter((e) => e.id !== id)
      });
      return ok(
        { deleted: true, id, recycle_bin_entry: entry.id, recoverable_until_days: 30, media_keys_held: mediaKeys.length },
        { written: [STATE_KEYS.trash, STATE_KEYS.events] }
      );
    }
  },

  {
    name: 'meos_events_get_upcoming',
    title: 'Get upcoming events',
    description:
      'Project repeated events into the next N days and return every occurrence sooner than the horizon, with days remaining and reminder leads. Occurrences are computed, not stored.',
    inputSchema: {
      days: z.number().int().min(1).max(365).optional().describe('Horizon in days (default 30).'),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const events = await readArray<EventItem>(ctx, STATE_KEYS.events);
      const today = todayKey();
      const horizon = addDays(today, args.days ?? 30);
      const rows = events
        .flatMap((event) =>
          occurrences(event, today, horizon, 400).map((day) => ({
            id: event.id,
            occurrence: day,
            days_until: dayDelta(today, day),
            title: event.title,
            time: event.time ?? null,
            tag_ids: event.tagIDs,
            special: event.special,
            recurring: (event.recurrence?.unit ?? 'none') !== 'none',
            reminders: (event.reminders ?? []).map((r) => ({
              lead: r,
              label: reminderLabel(r as keyof typeof REMINDER_DAYS),
              fires_on: addDays(day, -(REMINDER_DAYS[r as keyof typeof REMINDER_DAYS] ?? 0))
            }))
          }))
        )
        .sort((a, b) => a.occurrence.localeCompare(b.occurrence) || a.title.localeCompare(b.title));
      const page = paginate(rows, args.limit, args.cursor);
      return ok(
        { from: today, to: horizon, ...page, total_matching: rows.length },
        { projection: 'Recurrence rules are expanded at read time; nothing is duplicated in storage.' }
      );
    }
  },

  {
    name: 'meos_events_list_tags',
    title: 'List event tags',
    description: 'List the event tags MeOS uses (the seven built-ins plus any custom tags).',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const tags = await readArray<EventTag>(ctx, STATE_KEYS.eventTags);
      return ok({ tags: tags.length ? tags : DEFAULT_TAGS, source: tags.length ? 'meos.eventTags' : 'built-in defaults' });
    }
  },

  {
    name: 'meos_reminders_list',
    title: 'List event reminders',
    description:
      'List the next reminder for each event/lead pair, soonest first. MeOS has no standalone reminder records: a reminder is a lead time attached to an event. Device schedules are rebuilt by the app and are not stored here.',
    inputSchema: {
      days: z.number().int().min(1).max(365).optional(),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const events = await readArray<EventItem>(ctx, STATE_KEYS.events);
      const plan = reminderPlan(events, todayKey(), 500, nowMinutes());
      const horizon = addDays(todayKey(), args.days ?? 90);
      const rows = plan.filter((p) => p.fires_on <= horizon);
      const page = paginate(rows, args.limit, args.cursor);
      return ok({ ...page, total_matching: rows.length });
    }
  },

  {
    name: 'meos_reminders_set',
    title: 'Set reminders on an event',
    description:
      'Replace the reminder lead times for one event. Empty list makes it silent. This changes only that event; no other event\'s reminders or pending notifications are cleared.',
    inputSchema: {
      event_id: z.string().min(1),
      reminders: RemindersInput
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.event_id).toLowerCase();
      const reminders = normalizeReminders(args.reminders);
      let updated: EventItem | null = null;
      await ctx.services.store.update<EventItem[]>(STATE_KEYS.events, (current) =>
        (current ?? []).map((e) => {
          if (e.id !== id) return e;
          updated = { ...e, reminders };
          return updated;
        })
      );
      if (!updated) throw errors.notFound('Event');
      return ok(
        {
          event_id: id,
          reminders: reminders.map((r) => ({ lead: r, label: reminderLabel(r as keyof typeof REMINDER_DAYS) }))
        },
        {
          written: STATE_KEYS.events,
          notifications: 'The app rebuilds schedules from meos.events on its next sync; this tool does not touch other events.'
        }
      );
    }
  }
];
