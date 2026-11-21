import { z } from 'zod';
import { STATE_KEYS, DEFAULT_PROFILE, type DayPlan, type FocusItem, type Profile } from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { assertDateKey, todayKey } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolDefinition } from './registry.ts';
import { cleanText, readObject, recycleAndRemove, taskOwner, trashEntry } from './shared.ts';

type Days = Record<string, DayPlan>;

function flatten(days: Days) {
  return Object.entries(days)
    .flatMap(([date, plan]) => (plan?.todos ?? []).map((todo) => ({ date, ...todo })))
    .sort((a, b) => {
      if (a.date !== b.date) return b.date.localeCompare(a.date);
      if (a.done !== b.done) return a.done ? 1 : -1;
      return a.text.localeCompare(b.text);
    });
}

function todoForClient(row: { date: string } & FocusItem) {
  return {
    id: row.id,
    date: row.date,
    text: row.text,
    done: row.done,
    mins: row.mins ?? null,
    spent_seconds: row.spent ?? 0
  };
}

export const taskTools: ToolDefinition[] = [
  {
    name: 'meos_tasks_list',
    title: 'List tasks',
    description:
      'List MeOS to-dos across days. Tasks belong to a specific date in MeOS (there is no separate project or priority model). Filter by date range, status or text.',
    inputSchema: {
      from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      status: z.enum(['open', 'done', 'all']).optional(),
      query: z.string().max(200).optional(),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const days = await readObject<Days>(ctx, STATE_KEYS.days, {});
      const from = args.from ? assertDateKey(args.from, 'from') : null;
      const to = args.to ? assertDateKey(args.to, 'to') : null;
      if (from && to && from > to) throw errors.invalidInput('from must be on or before to');
      const status = args.status ?? 'all';
      const q = String(args.query ?? '').trim().toLowerCase();

      const rows = flatten(days)
        .filter((t) => (!from || t.date >= from) && (!to || t.date <= to))
        .filter((t) => (status === 'all' ? true : status === 'done' ? t.done : !t.done))
        .filter((t) => !q || t.text.toLowerCase().includes(q));

      const page = paginate(rows, args.limit, args.cursor);
      return ok({ ...page, items: page.items.map(todoForClient), total_matching: rows.length });
    }
  },

  {
    name: 'meos_tasks_get',
    title: 'Get a task',
    description: 'Read one to-do, including the date it belongs to and focus time already banked against it.',
    inputSchema: { id: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const days = await readObject<Days>(ctx, STATE_KEYS.days, {});
      const id = String(args.id).toLowerCase();
      const day = taskOwner(days, id);
      if (!day) throw errors.notFound('Task');
      const todo = (days[day]?.todos ?? []).find((t) => t.id === id)!;
      return ok(todoForClient({ date: day, ...todo }));
    }
  },

  {
    name: 'meos_tasks_create',
    title: 'Create a task',
    description: 'Add a to-do to a specific day (default today). MeOS stores tasks per day; there is no cross-day project list.',
    inputSchema: {
      text: z.string().min(1).max(500),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      mins: z.number().int().min(1).max(600).optional().describe('Planned focus block length in minutes.')
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const text = cleanText(args.text, 'text', 500);
      const date = assertDateKey(args.date ?? todayKey());
      const todo: FocusItem = { id: newId(), text, done: false, mins: args.mins ?? null, spent: 0 };
      await ctx.services.store.update<Days>(STATE_KEYS.days, (current) => {
        const base = current ?? {};
        const plan = base[date] ?? { todos: [], habits: {} };
        return { ...base, [date]: { ...plan, todos: [...(plan.todos ?? []), todo] } };
      });
      return ok(todoForClient({ date, ...todo }), { written: STATE_KEYS.days });
    }
  },

  {
    name: 'meos_tasks_update',
    title: 'Update a task',
    description:
      'Change a task\'s text, planned minutes, completion, or the day it belongs to. Moving a task preserves its id and banked focus time. Only supplied fields change.',
    inputSchema: {
      id: z.string().min(1),
      text: z.string().min(1).max(500).optional(),
      done: z.boolean().optional(),
      mins: z.number().int().min(1).max(600).nullable().optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const days = await readObject<Days>(ctx, STATE_KEYS.days, {});
      const owner = taskOwner(days, id);
      if (!owner) throw errors.notFound('Task');
      if (
        args.text === undefined &&
        args.done === undefined &&
        args.mins === undefined &&
        args.date === undefined
      ) {
        throw errors.invalidInput('Nothing to update');
      }

      const targetDate = args.date ? assertDateKey(args.date) : owner;
      let updated: FocusItem | null = null;
      await ctx.services.store.update<Days>(STATE_KEYS.days, (current) => {
        const base = { ...(current ?? {}) };
        const source = base[owner] ?? { todos: [], habits: {} };
        const found = (source.todos ?? []).find((t) => t.id === id);
        if (!found) throw errors.notFound('Task');

        updated = {
          ...found,
          text: args.text !== undefined ? cleanText(args.text, 'text', 500) : found.text,
          done: args.done !== undefined ? Boolean(args.done) : found.done,
          mins: args.mins !== undefined ? args.mins : found.mins
        };

        if (targetDate === owner) {
          base[owner] = { ...source, todos: (source.todos ?? []).map((t) => (t.id === id ? updated! : t)) };
        } else {
          base[owner] = { ...source, todos: (source.todos ?? []).filter((t) => t.id !== id) };
          const target = base[targetDate] ?? { todos: [], habits: {} };
          base[targetDate] = { ...target, todos: [...(target.todos ?? []), updated!] };
        }
        return base;
      });
      return ok(todoForClient({ date: targetDate, ...updated! }), { written: STATE_KEYS.days });
    }
  },

  {
    name: 'meos_tasks_complete',
    title: 'Complete a task',
    description: 'Mark a to-do done (or undone with done=false). Idempotent.',
    inputSchema: { id: z.string().min(1), done: z.boolean().optional() },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const days = await readObject<Days>(ctx, STATE_KEYS.days, {});
      const owner = taskOwner(days, id);
      if (!owner) throw errors.notFound('Task');
      const done = args.done !== false;
      let updated: FocusItem | null = null;
      await ctx.services.store.update<Days>(STATE_KEYS.days, (current) => {
        const base = { ...(current ?? {}) };
        const plan = base[owner] ?? { todos: [], habits: {} };
        base[owner] = {
          ...plan,
          todos: (plan.todos ?? []).map((t) => {
            if (t.id !== id) return t;
            updated = { ...t, done };
            return updated;
          })
        };
        return base;
      });
      return ok(
        { id, date: owner, done, task: updated ? todoForClient({ date: owner, ...(updated as FocusItem) }) : null },
        { written: STATE_KEYS.days }
      );
    }
  },

  {
    name: 'meos_tasks_delete',
    title: 'Delete a task',
    description:
      'Move a to-do to the MeOS recycle bin (30 days). It is restored back into the day it belonged to. Requires destructive scope and confirm=true.',
    inputSchema: { id: z.string().min(1), confirm: z.boolean().optional() },
    scopes: ['write', 'destructive'],
    destructive: true,
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const days = await readObject<Days>(ctx, STATE_KEYS.days, {});
      const owner = taskOwner(days, id);
      if (!owner) throw errors.notFound('Task');
      const todo = (days[owner]?.todos ?? []).find((t) => t.id === id)!;
      const entry = trashEntry({
        kind: 'todo',
        itemID: todo.id,
        title: todo.text,
        subtitle: owner,
        payload: todo,
        context: owner
      });
      await recycleAndRemove<Days>(ctx, {
        moduleKey: STATE_KEYS.days,
        entry,
        fallback: {},
        remove: (all) => {
          const base: Days = { ...all };
          const day = owner;
          const plan = base[day];
          if (plan) base[day] = { ...plan, todos: (plan.todos ?? []).filter((t) => t.id !== id) };
          return base;
        }
      });
      return ok({ deleted: true, id, date: owner, recycle_bin_entry: entry.id, recoverable_until_days: 30 }, {
        written: [STATE_KEYS.trash, STATE_KEYS.days]
      });
    }
  },

  {
    name: 'meos_tasks_list_habits',
    title: 'List habits',
    description: 'List the owner\'s habit names and which were completed on a date (default today). MeOS habits live on the profile and are ticked per day.',
    inputSchema: { date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() },
    scopes: ['read'],
    async handler(args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const days = await readObject<Days>(ctx, STATE_KEYS.days, {});
      const date = assertDateKey(args.date ?? todayKey());
      return ok({
        date,
        habits: (profile.habits ?? []).map((name) => ({ name, done: Boolean(days[date]?.habits?.[name]) }))
      });
    }
  },

  {
    name: 'meos_tasks_set_habit',
    title: 'Tick a habit',
    description: 'Mark one of the profile\'s habits done or not done on a date (default today). Unknown habit names are rejected so a typo cannot create a hidden habit.',
    inputSchema: {
      name: z.string().min(1).max(80),
      done: z.boolean(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const name = args.name.trim();
      const known = profile.habits ?? [];
      if (!known.includes(name)) {
        throw errors.invalidInput(`Unknown habit "${name}". Known habits: ${known.join(', ')}`);
      }
      const date = assertDateKey(args.date ?? todayKey());
      await ctx.services.store.update<Days>(STATE_KEYS.days, (current) => {
        const base = current ?? {};
        const plan = base[date] ?? { todos: [], habits: {} };
        return { ...base, [date]: { ...plan, habits: { ...(plan.habits ?? {}), [name]: Boolean(args.done) } } };
      });
      return ok({ date, habit: name, done: Boolean(args.done) }, { written: STATE_KEYS.days });
    }
  },

  {
    name: 'meos_tasks_summary',
    title: 'Get task summary',
    description: 'Counts for a date: open and done to-dos, focus time banked, and habits completed.',
    inputSchema: { date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() },
    scopes: ['read'],
    async handler(args, ctx) {
      const date = assertDateKey(args.date ?? todayKey());
      const days = await readObject<Days>(ctx, STATE_KEYS.days, {});
      const plan = days[date] ?? { todos: [], habits: {} };
      const todos = plan.todos ?? [];
      return ok({
        date,
        total: todos.length,
        done: todos.filter((t) => t.done).length,
        open: todos.filter((t) => !t.done).length,
        focus_seconds: todos.reduce((n, t) => n + (t.spent ?? 0), 0),
        habits_done: Object.values(plan.habits ?? {}).filter(Boolean).length
      });
    }
  }
];
