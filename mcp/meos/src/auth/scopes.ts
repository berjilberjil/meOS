/**
 * Permission scopes.
 *
 * Two vocabularies are supported on purpose:
 *
 *   - **Granular (current):** `meos.<module>.read` / `meos.<module>.write`.
 *     OAuth clients request these individually and the consent screen lists
 *     them one by one. A new client gets no data scope by default.
 *   - **Legacy (compatibility):** `read`, `write`, `health`, `secret`,
 *     `destructive`. Static bearer clients and stdio still use them. They are
 *     expanded into the granular set before any tool check, so the old
 *     behaviour is preserved without weakening the new model.
 *
 * `secret` gates locked notes / private profile fields. `destructive` is an
 * extra flag on top of the module write scope and always also requires
 * `confirm: true` in the call. `meos.admin.none` exists as an explicit
 * "no access" sentinel and grants nothing.
 */

export const MODULES = [
  'profile',
  'finance',
  'fitness',
  'health',
  'notes',
  'tasks',
  'calendar',
  'goals',
  'memory',
  'diet',
  'knowledge',
  'files',
  'analytics'
] as const;

export type Module = (typeof MODULES)[number];
export type GranularScope = `meos.${Module}.read` | `meos.${Module}.write`;
export type LegacyScope = 'read' | 'write' | 'destructive' | 'health' | 'secret';
export type SpecialScope = 'offline_access' | 'meos.admin.none';
export type Scope = GranularScope | LegacyScope | SpecialScope;

export const GRANULAR_SCOPES: readonly GranularScope[] = MODULES.flatMap((m) => [
  `meos.${m}.read`,
  `meos.${m}.write`
]) as GranularScope[];

export const ALL_SCOPES: readonly Scope[] = [
  ...GRANULAR_SCOPES,
  'read',
  'write',
  'destructive',
  'health',
  'secret',
  'offline_access',
  'meos.admin.none'
];

export const SCOPE_DESCRIPTIONS: Record<GranularScope, string> = {
  'meos.profile.read': 'Name, city, role, links, goals and achievements',
  'meos.profile.write': 'Edit profile fields and goals',
  'meos.finance.read': 'Net worth, balances, spending and purchases',
  'meos.finance.write': 'Log or edit purchases',
  'meos.fitness.read': 'Workouts, training programme and body metrics',
  'meos.fitness.write': 'Log or edit workouts',
  'meos.health.read': 'Weight, calories, water, steps and health summaries',
  'meos.health.write': 'Log daily health metrics',
  'meos.notes.read': 'Notes and search (locked notes need secret)',
  'meos.notes.write': 'Create, edit, pin or delete notes',
  'meos.tasks.read': 'Daily to-dos and habits',
  'meos.tasks.write': 'Create, complete or move tasks and habits',
  'meos.calendar.read': 'Events, tags and reminders',
  'meos.calendar.write': 'Create or edit events and reminders',
  'meos.goals.read': 'Life goals and achievements',
  'meos.goals.write': 'Edit or archive goals',
  'meos.memory.read': 'Curated durable facts MeOS remembers',
  'meos.memory.write': "Add or update the assistant's memory",
  'meos.diet.read': 'Meal plans, food log and nutrition targets',
  'meos.diet.write': 'Edit meal plans and log food',
  'meos.knowledge.read': 'Learning videos and takeaways',
  'meos.knowledge.write': 'Add or edit learning entries',
  'meos.files.read': 'Media metadata, storage usage and recycle bin',
  'meos.files.write': 'Restore or purge recycle-bin items',
  'meos.analytics.read': 'Daily, weekly and monthly summaries and app status',
  'meos.analytics.write': 'No write tools exist for analytics (reserved)'
};

export function isModule(value: string): value is Module {
  return (MODULES as readonly string[]).includes(value);
}

export function isScope(value: string): value is Scope {
  return (ALL_SCOPES as readonly string[]).includes(value);
}

export function isGranularScope(value: string): value is GranularScope {
  return /^meos\.(profile|finance|fitness|health|notes|tasks|calendar|goals|memory|diet|knowledge|files|analytics)\.(read|write)$/.test(
    value
  );
}

/** Parse a comma/space separated list. Unknown values fail closed. */
export function parseScopes(raw: string | undefined | null): Scope[] {
  if (!raw) return ['read'];
  const out: Scope[] = [];
  for (const part of raw.split(/[\s,]+/)) {
    const p = part.trim().toLowerCase();
    if (!p) continue;
    if (!isScope(p)) throw new Error(`Unknown scope "${p}" (allowed: ${ALL_SCOPES.join(', ')})`);
    if (!out.includes(p)) out.push(p);
  }
  return out.length ? out : ['read'];
}

/**
 * Expand legacy scopes into granular ones. Granular scopes pass through;
 * a write scope implies its read scope. The sentinel grants nothing.
 */
/** Modules the legacy `health` scope gates. */
const HEALTH_GATED: ReadonlySet<Module> = new Set(['health', 'fitness', 'diet']);

export function expandScopes(scopes: readonly Scope[]): Scope[] {
  const out = new Set<Scope>();
  const canWrite = scopes.includes('write');
  const canRead = scopes.includes('read') || canWrite;

  for (const scope of scopes) {
    if (scope === 'meos.admin.none') continue;
    if (isGranularScope(scope)) {
      out.add(scope);
      if (scope.endsWith('.write')) out.add(scope.replace(/\.write$/, '.read') as Scope);
      continue;
    }
    switch (scope) {
      case 'read':
        // `read` alone never unlocked health/fitness/diet: the old model also
        // required the separate `health` scope. That separation is preserved.
        for (const m of MODULES) if (!HEALTH_GATED.has(m)) out.add(`meos.${m}.read`);
        break;
      case 'write':
        for (const m of MODULES) {
          if (HEALTH_GATED.has(m)) continue;
          out.add(`meos.${m}.read`);
          out.add(`meos.${m}.write`);
        }
        break;
      case 'health':
        if (canRead) {
          for (const m of HEALTH_GATED) {
            out.add(`meos.${m}.read`);
            if (canWrite) out.add(`meos.${m}.write`);
          }
        }
        break;
      case 'secret':
      case 'destructive':
      case 'offline_access':
        out.add(scope);
        break;
      default:
        break;
    }
  }
  return [...out];
}

export function hasScope(scopes: readonly string[], needed: string): boolean {
  return scopes.includes(needed);
}

export function hasEveryScope(scopes: readonly string[], needed: readonly string[]): boolean {
  const effective = new Set(expandScopes(scopes as Scope[]));
  return needed.every((s) => effective.has(s as Scope));
}

/* -------------------------------------------------------------------------- */
/* Tool → module mapping                                                       */
/* -------------------------------------------------------------------------- */

const PREFIX_MODULES: Array<[string, Module]> = [
  ['meos_finance_', 'finance'],
  ['meos_health_', 'health'],
  ['meos_fitness_', 'fitness'],
  ['meos_tasks_', 'tasks'],
  ['meos_goals_', 'goals'],
  ['meos_notes_', 'notes'],
  ['meos_events_', 'calendar'],
  ['meos_reminders_', 'calendar'],
  ['meos_memory_', 'memory'],
  ['meos_diet_', 'diet'],
  ['meos_knowledge_', 'knowledge']
];

const EXACT_MODULES: Record<string, Module> = {
  meos_get_profile: 'profile',
  meos_list_devices: 'profile',
  meos_get_device: 'profile',
  meos_get_storage_usage: 'files',
  meos_list_trash: 'files',
  meos_restore_from_trash: 'files',
  meos_purge_from_trash: 'files',
  meos_get_app_status: 'analytics',
  meos_get_module_status: 'analytics',
  meos_get_capabilities: 'analytics',
  meos_get_settings: 'analytics',
  meos_ai_get_available_models: 'analytics',
  meos_ai_get_routes: 'analytics'
};

export function moduleForTool(toolName: string): Module {
  for (const [prefix, module] of PREFIX_MODULES) {
    if (toolName.startsWith(prefix)) return module;
  }
  return EXACT_MODULES[toolName] ?? 'analytics';
}

export interface ToolScopeShape {
  name: string;
  scopes: readonly string[];
  destructive?: boolean;
}

/**
 * The scopes a tool actually needs. Depends only on the tool definition, never
 * on client input. A write tool needs the module's write scope; destructive
 * tools additionally need the `destructive` flag and `confirm: true`.
 */
export function requiredScopesForTool(def: ToolScopeShape): string[] {
  const module = moduleForTool(def.name);
  const write = def.scopes.includes('write') || Boolean(def.destructive);
  const required = [`meos.${module}.${write ? 'write' : 'read'}`];
  // Health-gated tools outside the health/fitness/diet modules (storage usage,
  // setting a fitness goal) still need the health read scope as a second gate.
  if (def.scopes.includes('health') && !HEALTH_GATED.has(module)) required.push('meos.health.read');
  if (def.scopes.includes('secret')) required.push('secret');
  if (def.destructive) required.push('destructive');
  return required;
}

/** Whether a client may even see/call this tool. */
export function canUseTool(scopes: readonly Scope[], def: ToolScopeShape): boolean {
  return hasEveryScope(scopes, requiredScopesForTool(def));
}

/** Human-readable scope list for the consent screen and dashboard. */
export function describeScopes(scopes: readonly string[]): string[] {
  return scopes.map((s) => {
    if (isGranularScope(s)) return `${s} — ${SCOPE_DESCRIPTIONS[s]}`;
    if (s === 'secret') return 'secret — locked notes and private profile fields';
    if (s === 'destructive') return 'destructive — deletes and purges (also needs confirm)';
    if (s === 'offline_access') return 'offline_access — refresh token while not actively connected';
    if (s === 'meos.admin.none') return 'meos.admin.none — no data access';
    return s;
  });
}
