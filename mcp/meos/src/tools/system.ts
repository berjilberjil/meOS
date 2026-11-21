import { z } from 'zod';
import {
  STATE_KEYS,
  DEFAULT_BELONGINGS,
  DEFAULT_PROFILE,
  type BelongingItem,
  type EventItem,
  type Note,
  type Profile,
  type TrashEntry,
  type WatchItem
} from '../schemas/models.ts';
import { hasScope } from '../auth/scopes.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { todayKey } from '../utils/dates.ts';
import type { ToolDefinition, ToolContext } from './registry.ts';
import {
  canReadLockedNotes,
  daysLeftInTrash,
  liveTrash,
  publicProfile,
  readArray,
  readObject
} from './shared.ts';

const COUNT_KEYS: Array<[string, string]> = [
  ['profile', STATE_KEYS.profile],
  ['notes', STATE_KEYS.notes],
  ['days', STATE_KEYS.days],
  ['events', STATE_KEYS.events],
  ['event_tags', STATE_KEYS.eventTags],
  ['fitness', STATE_KEYS.fitness],
  ['fitness_profile', STATE_KEYS.fitnessProfile],
  ['nutrition', STATE_KEYS.nutrition],
  ['training', STATE_KEYS.training],
  ['memory', STATE_KEYS.memory],
  ['belongings', STATE_KEYS.belongings],
  ['fold', STATE_KEYS.fold],
  ['trash', STATE_KEYS.trash],
  ['watch', STATE_KEYS.watch],
  ['scans', STATE_KEYS.scans],
  ['weekly', STATE_KEYS.weekly],
  ['six_pack', STATE_KEYS.sixPack],
  ['chat', STATE_KEYS.chat]
];

function countOf(value: unknown): number | null {
  if (Array.isArray(value)) return value.length;
  if (value && typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    if (Array.isArray(obj.items)) return obj.items.length;
    if (Array.isArray(obj.threads)) return obj.threads.length;
    if (obj.log && typeof obj.log === 'object') return Object.keys(obj.log).length;
    return Object.keys(obj).length;
  }
  return null;
}

function decodePayload<T>(entry: TrashEntry): T {
  try {
    return JSON.parse(entry.payload) as T;
  } catch {
    throw errors.conflict('This recycle-bin entry cannot be decoded by the current MeOS shape. It was left untouched.');
  }
}

function trashView(entry: TrashEntry, canLocked: boolean) {
  let locked = false;
  let undecodable = false;
  if (entry.kind === 'note') {
    try {
      locked = Boolean((JSON.parse(entry.payload) as Note).locked);
    } catch {
      undecodable = true;
    }
  }
  const hidden = entry.kind === 'note' && (locked ? !canLocked : undecodable);
  return {
    entry_id: entry.id,
    item_id: entry.itemID,
    kind: entry.kind,
    title: hidden ? (undecodable ? '[note]' : '[locked]') : entry.title,
    subtitle: hidden ? (undecodable ? '' : 'Locked') : entry.subtitle,
    deleted_at: entry.deletedAt,
    days_left: daysLeftInTrash(entry),
    has_media: (entry.mediaKeys ?? []).length > 0
  };
}

async function restoreEntry(ctx: ToolContext, entry: TrashEntry): Promise<{ restored: boolean; kind: string; reason?: string }> {
  switch (entry.kind) {
    case 'note': {
      const item = decodePayload<Note>(entry);
      const existing = await readArray<Note>(ctx, STATE_KEYS.notes);
      if (existing.some((n) => n.id === item.id)) throw errors.conflict('A note with this id already exists.');
      await ctx.services.store.update<Note[]>(STATE_KEYS.notes, (current) => [item, ...(current ?? [])]);
      break;
    }
    case 'event': {
      const item = decodePayload<EventItem>(entry);
      const existing = await readArray<EventItem>(ctx, STATE_KEYS.events);
      if (existing.some((e) => e.id === item.id)) throw errors.conflict('An event with this id already exists.');
      await ctx.services.store.update<EventItem[]>(STATE_KEYS.events, (current) => [...(current ?? []), item]);
      break;
    }
    case 'belonging': {
      const item = decodePayload<BelongingItem>(entry);
      const state = await readObject<any>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      if ((state.items ?? []).some((i: BelongingItem) => i.id === item.id)) throw errors.conflict('This purchase already exists.');
      await ctx.services.store.update<any>(STATE_KEYS.belongings, (current) => ({
        ...(current ?? DEFAULT_BELONGINGS),
        items: [item, ...((current?.items ?? []) as BelongingItem[])]
      }));
      break;
    }
    case 'watch': {
      const item = decodePayload<WatchItem>(entry);
      const existing = await readArray<WatchItem>(ctx, STATE_KEYS.watch);
      if (existing.some((w) => w.id === item.id)) throw errors.conflict('This video already exists.');
      await ctx.services.store.update<WatchItem[]>(STATE_KEYS.watch, (current) => [...(current ?? []), item]);
      break;
    }
    case 'todo': {
      const item = decodePayload<any>(entry);
      if (!entry.context || !/^\d{4}-\d{2}-\d{2}$/.test(entry.context)) {
        throw errors.conflict('This to-do has no day to return to.');
      }
      const days = await readObject<Record<string, any>>(ctx, STATE_KEYS.days, {});
      if ((days[entry.context]?.todos ?? []).some((t: any) => t.id === item.id)) {
        throw errors.conflict('This to-do already exists on its day.');
      }
      await ctx.services.store.update<Record<string, any>>(STATE_KEYS.days, (current) => {
        const base = current ?? {};
        const plan = base[entry.context!] ?? { todos: [], habits: {} };
        return { ...base, [entry.context!]: { ...plan, todos: [...(plan.todos ?? []), item] } };
      });
      break;
    }
    case 'scan': {
      const item = decodePayload<any>(entry);
      await ctx.services.store.update<any[]>(STATE_KEYS.scans, (current) => [item, ...(current ?? [])]);
      break;
    }
    case 'chatThread': {
      const item = decodePayload<any>(entry);
      await ctx.services.store.update<any>(STATE_KEYS.chat, (current) => {
        const base = current ?? { threads: [], activeID: null };
        return { ...base, threads: [item, ...(base.threads ?? [])] };
      });
      break;
    }
    case 'food': {
      const item = decodePayload<any>(entry);
      await ctx.services.store.update<any>(STATE_KEYS.nutrition, (current) => {
        const base = current ?? { customFoods: [], log: {}, mealPlan: {} };
        return { ...base, customFoods: [item, ...(base.customFoods ?? []).filter((f: any) => f.id !== item.id)] };
      });
      break;
    }
    case 'exercise': {
      const item = decodePayload<any>(entry);
      await ctx.services.store.update<any>(STATE_KEYS.training, (current) => {
        const base = current ?? { customExercises: [], weekPlan: {}, dayLog: {}, programs: [] };
        return {
          ...base,
          customExercises: [item, ...(base.customExercises ?? []).filter((e: any) => e.id !== item.id)]
        };
      });
      break;
    }
    case 'program': {
      const item = decodePayload<any>(entry);
      await ctx.services.store.update<any>(STATE_KEYS.training, (current) => {
        const base = current ?? { customExercises: [], weekPlan: {}, dayLog: {}, programs: [] };
        return {
          ...base,
          programs: [item, ...(base.programs ?? []).filter((p: any) => p.id !== item.id)]
        };
      });
      break;
    }
    case 'progressPhoto':
      return {
        restored: false,
        kind: entry.kind,
        reason: 'Progress photo files live on the device and in encrypted R2 storage. Restore it in the MeOS app.'
      };
    default:
      throw errors.unsupported(`Restoring "${entry.kind}"`, 'This recycle-bin kind is not handled by the gateway.');
  }

  await ctx.services.store.update<TrashEntry[]>(STATE_KEYS.trash, (current) =>
    (current ?? []).filter((e) => e.id !== entry.id)
  );
  return { restored: true, kind: entry.kind };
}

export const systemTools: ToolDefinition[] = [
  {
    name: 'meos_get_profile',
    title: 'Get MeOS profile',
    description:
      'Read the owner profile: name, place, work, links, goals by horizon, achievements and habits. Contact details and the private brief are omitted unless the client has the secret scope. The profile photo is never returned.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      return ok(publicProfile(profile, hasScope(ctx.client.scopes, 'secret')));
    }
  },

  {
    name: 'meos_get_app_status',
    title: 'Get MeOS status',
    description:
      'Health of the gateway connection: backend reachability, authenticated MeOS user, vault configured/unlocked state, and which module documents exist. Never returns tokens, hashes, keys or session cookies.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      let user: { id: number; username: string } | null = null;
      let reachable = false;
      try {
        user = await ctx.services.api.getMe();
        reachable = true;
      } catch {
        reachable = false;
      }
      let raw: Record<string, unknown>;
      try {
        raw = await ctx.services.store.raw(true);
      } catch {
        return ok({
          backend: { reachable: false, base_url: ctx.services.account.baseUrl },
          user: null,
          vault: 'unknown',
          modules_present: [],
          server_version: '1.0.0',
          transport: 'mcp',
          time: new Date().toISOString()
        });
      }
      const metaPresent = Boolean(raw['meos.crypto'] ?? raw['myos.crypto']);
      let vault: string;
      if (!metaPresent) vault = 'not_configured';
      else if (ctx.services.vault.isUnlocked) vault = 'unlocked';
      else if (ctx.services.account.vaultPassphrase || ctx.services.account.vaultRecovery) {
        try {
          await ctx.services.vault.unlock();
          vault = 'unlocked';
        } catch {
          vault = 'locked_bad_key';
        }
      } else {
        vault = 'locked_no_key';
      }
      return ok({
        backend: { reachable, base_url: ctx.services.account.baseUrl },
        user: user ? { username: user.username } : null,
        vault,
        modules_present: COUNT_KEYS.filter(([, key]) => raw[key] !== undefined).map(([name]) => name),
        server_version: '1.0.0',
        transport: 'mcp',
        time: new Date().toISOString()
      });
    }
  },

  {
    name: 'meos_get_module_status',
    title: 'Get module status',
    description:
      'Report each MeOS module document: present, stored key, sealed, and a count where it can be read. Counts are omitted when the vault is locked rather than reported as zero.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const raw = await ctx.services.store.raw(true);
      const modules: Record<string, unknown> = {};
      for (const [name, key] of COUNT_KEYS) {
        const desc = await ctx.services.vault.describe(raw, key);
        const row: Record<string, unknown> = { ...desc };
        if (desc.present) {
          try {
            const read = await ctx.services.vault.read(raw, key);
            row.count = countOf(read.value);
          } catch (e) {
            row.count = null;
            row.readable = false;
            row.reason = e instanceof Error && e.message.includes('locked') ? 'vault locked' : 'unreadable';
          }
        }
        modules[name] = row;
      }
      return ok({ modules });
    }
  },

  {
    name: 'meos_get_storage_usage',
    title: 'Get storage usage',
    description:
      'Aggregate private-media usage: how many encrypted progress photos exist and their total bytes. No filenames, dates, signed URLs or image data are returned. Database quota is not exposed by the MeOS backend.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const photos = await ctx.services.api.listBodyPhotos();
      return ok(
        {
          media: {
            body_photos: {
              count: photos.length,
              total_bytes: photos.reduce((n, p) => n + (p.bytes ?? 0), 0)
            },
            encrypted: true
          },
          database: { available: false }
        },
        { note: 'Only R2 media is measurable through the existing API. The backend does not expose D1 quota.' }
      );
    }
  },

  {
    name: 'meos_list_devices',
    title: 'List devices',
    description: 'List every device signed into this MeOS account, most recently active first. No tokens or credentials are stored on these rows.',
    inputSchema: {
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const devices = (await ctx.services.api.listDevices()).sort((a, b) =>
        String(b.last_seen ?? '').localeCompare(String(a.last_seen ?? ''))
      );
      const page = paginate(devices, args.limit, args.cursor);
      return ok({
        ...page,
        items: page.items.map((d) => ({
          id: d.id,
          name: d.name,
          system_name: d.system_name,
          platform: d.platform,
          kind: d.kind,
          app_version: d.app_version,
          created_at: d.created_at,
          last_seen: d.last_seen
        })),
        total_matching: devices.length
      });
    }
  },

  {
    name: 'meos_get_device',
    title: 'Get a device',
    description: 'Read one signed-in device by its install id.',
    inputSchema: { id: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const devices = await ctx.services.api.listDevices();
      const device = devices.find((d) => d.id === String(args.id));
      if (!device) throw errors.notFound('Device');
      return ok(device);
    }
  },

  {
    name: 'meos_ai_get_available_models',
    title: 'List available AI models',
    description:
      'List the AI providers and model ids available to MeOS, using the provider keys the owner configured. Keys are returned masked exactly as the backend stores them; raw secrets never leave the server.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const keys = await ctx.services.api.listAiKeys();
      const providers = keys.map((k) => ({
        id: k.id,
        provider: k.provider,
        label: k.label,
        masked_key: k.masked,
        enabled: k.enabled,
        models: Array.isArray(k.models) ? k.models : []
      }));
      return ok({
        providers,
        models: [...new Set(providers.flatMap((p) => p.models))].sort()
      });
    }
  },

  {
    name: 'meos_ai_get_routes',
    title: 'Get AI routing',
    description:
      'Read the per-feature AI routing (which key id and model each feature uses). This is non-secret configuration; provider secrets are never included.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const routes = await ctx.services.api.getAiRoutes();
      const scrub = (value: unknown): unknown => {
        if (Array.isArray(value)) return value.map(scrub);
        if (value && typeof value === 'object') {
          const out: Record<string, unknown> = {};
          for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
            if (/secret|password|token|apikey|api_key|authorization|cookie/i.test(k)) continue;
            out[k] = scrub(v);
          }
          return out;
        }
        return value;
      };
      return ok({ routes: scrub(routes) });
    }
  },

  {
    name: 'meos_get_settings',
    title: 'Get safe settings',
    description:
      'Read the settings that are safe for an agent: Task Mode state, the fitness goal, and the profile habit list. Credentials, AI keys and encryption material are never included.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const taskMode = await readObject<any>(ctx, STATE_KEYS.taskMode, { on: false, since: '', device: '' });
      const fitness = await readObject<any>(ctx, STATE_KEYS.fitnessProfile, { goal: 'maintain' });
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      return ok({
        task_mode: taskMode,
        fitness: { goal: fitness.goal ?? 'maintain' },
        habits: profile.habits ?? []
      });
    }
  },

  {
    name: 'meos_list_trash',
    title: 'List recycle bin',
    description:
      'List live recycle-bin entries (30-day retention) without their payloads. Locked note titles are redacted unless the client has the secret scope. Use meos_restore_from_trash to put something back.',
    inputSchema: {
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const entries = liveTrash(await readArray<TrashEntry>(ctx, STATE_KEYS.trash));
      const page = paginate(entries, args.limit, args.cursor);
      return ok({
        ...page,
        items: page.items.map((e) => trashView(e, canReadLockedNotes(ctx))),
        total_matching: entries.length
      });
    }
  },

  {
    name: 'meos_restore_from_trash',
    title: 'Restore from recycle bin',
    description:
      'Put one recycle-bin entry back where it came from. Restores notes, events, purchases, videos, to-dos, scans, chat threads, foods, exercises and programs. Progress-photo files must be restored in the app.',
    inputSchema: { entry_id: z.string().min(1) },
    scopes: ['write'],
    async handler(args, ctx) {
      const entries = await readArray<TrashEntry>(ctx, STATE_KEYS.trash);
      const entry = entries.find((e) => e.id === String(args.entry_id).toLowerCase());
      if (!entry) throw errors.notFound('Recycle-bin entry');
      const result = await restoreEntry(ctx, entry);
      return ok(result, { written: result.restored ? [STATE_KEYS.trash] : [] });
    }
  },

  {
    name: 'meos_purge_from_trash',
    title: 'Permanently purge a recycle-bin entry',
    description:
      'Permanently remove one recycle-bin entry and release the encrypted media it was holding. This cannot be undone. Requires destructive scope and confirm=true.',
    inputSchema: { entry_id: z.string().min(1), confirm: z.boolean().optional() },
    scopes: ['write', 'destructive'],
    destructive: true,
    async handler(args, ctx) {
      const entries = await readArray<TrashEntry>(ctx, STATE_KEYS.trash);
      const entry = entries.find((e) => e.id === String(args.entry_id).toLowerCase());
      if (!entry) throw errors.notFound('Recycle-bin entry');

      await ctx.services.store.update<TrashEntry[]>(STATE_KEYS.trash, (current) =>
        (current ?? []).filter((e) => e.id !== entry.id)
      );

      const warnings: string[] = [];
      for (const key of entry.mediaKeys ?? []) {
        try {
          await ctx.services.api.deleteEventMedia(key);
        } catch {
          warnings.push(`media ${key} could not be released`);
        }
      }
      if (entry.kind === 'progressPhoto') {
        try {
          await ctx.services.api.deleteBodyPhoto(entry.itemID);
        } catch {
          warnings.push('progress photo cloud copy could not be released');
        }
      }
      return ok(
        { purged: true, entry_id: entry.id, kind: entry.kind, warnings },
        { written: STATE_KEYS.trash }
      );
    }
  },

  {
    name: 'meos_get_capabilities',
    title: 'Get MeOS capability inventory',
    description:
      'Return the audited capability map of this MeOS build: what genuinely exists, what is deliberately not exposed, and what was removed. Use it instead of assuming a finance ledger or a tag system exists.',
    inputSchema: {},
    scopes: ['read'],
    async handler() {
      return ok({
        version: '1.0.0-audit',
        modules: {
          finance: {
            available: ['fold_snapshot (net worth, liquid, investments, debt, spend categories)', 'stuff_purchases (price, ROI, monthly burn)'],
            unavailable: ['transaction_ledger', 'account_crud', 'budgets', 'transfers', 'savings_goals', 'investment_holdings'],
            note: 'The standalone finance ledger was removed from the native MeOS app. Fold is an external, read-only snapshot.'
          },
          health: {
            available: ['daily_metrics (weight, calories, protein, water, steps, note)', 'body_metrics', 'workout_history', 'workout_logging', 'exercise_history', 'progress_photos_metadata'],
            unavailable: ['medical_records', 'lab_results', 'medication_tracking'],
            note: 'Body-photo bytes are vault ciphertext and are never returned.'
          },
          tasks: {
            available: ['per_day_todos (text, done, planned minutes, focus seconds)', 'daily_habits'],
            unavailable: ['priority', 'due_date', 'cross_day_projects', 'recurrence'],
            note: 'A task belongs to a date. Deleting moves it to the recycle bin with its day.'
          },
          goals: {
            available: ['life_goals (short/mid/long strings)', 'fitness_goal', 'achievements', 'archive_to_achievement'],
            unavailable: ['goal_progress_percentage', 'goal_deadlines']
          },
          notes: {
            available: ['title/body', 'pin', 'lock', 'search', 'recycle_bin'],
            unavailable: ['tags', 'folders', 'backlinks'],
            note: 'Rich blocks are preserved for attachments; plain-text edits rebuild paragraphs.'
          },
          events: {
            available: ['events', 'recurrence rules', 'event tags', 'reminder lead times'],
            unavailable: ['standalone_reminder_records', 'calendar_provider_sync'],
            note: 'Occurrences are projected, never stored. The app owns device notification schedules.'
          },
          memory: { available: ['curated_memories', 'search', 'create/update'], unavailable: ['delete'] },
          devices: { available: ['device list', 'profile', 'module presence', 'media usage'] },
          diet: {
            available: ['day plan', 'meal log', 'food search', 'custom foods', 'goals'],
            note: 'Reuses the native diet logic in mcp/diet/src/plan.ts; there is one meal implementation.'
          },
          removed: ['journal']
        }
      });
    }
  }
];

// Kept for the resource layer's type narrowing.
export { trashView };
