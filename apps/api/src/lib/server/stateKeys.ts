/**
 * The state-key contract between the Apple client and this API.
 *
 * `PUT /api/state/[key]` used to accept any key name, which let one account
 * fill the shared D1 database with arbitrary rows. The allowlist is now the
 * single source of truth and lives in a module (not inside the route) so a test
 * can prove every key the app writes is accepted.
 *
 * When adding a module:
 *   1. add `meos.<module>` here,
 *   2. add it to `StateKey` in `apps/apple/MeOS/Core/Models.swift`,
 *   3. add a test fixture in `stateKeys.test.ts`.
 */

/** Current namespace. One entry per synced module. */
export const CURRENT_STATE_KEYS = [
  'meos.fitness',
  'meos.fitnessProfile',
  'meos.notes',
  'meos.days',
  'meos.profile',
  'meos.chat',
  'meos.nutrition',
  'meos.training',
  'meos.events',
  'meos.eventTags',
  'meos.watch',
  'meos.belongings',
  'meos.fold',
  'meos.memory',
  'meos.scans',
  'meos.taskMode',
  'meos.weekly',
  'meos.activity',
  'meos.appearance',
  'meos.crypto',
  'meos.sixPack',
  'meos.trash',
  // Reserved for the Personal Finance expansion. The client writes this key
  // through the generic state route, so it must be accepted before the UI ships.
  'meos.finance'
] as const;

/**
 * Legacy `myos.*` names. Kept while older installed builds still push them.
 * New writes always use `meos.*`; remove a pair only after no supported client
 * can still write it.
 */
export const LEGACY_STATE_KEYS = [
  'myos.fitness',
  'myos.fitnessProfile',
  'myos.notes',
  'myos.days',
  'myos.profile',
  'myos.chat',
  'myos.nutrition',
  'myos.training',
  'myos.events',
  'myos.eventTags',
  'myos.watch',
  'myos.belongings',
  'myos.fold',
  'myos.memory',
  'myos.scans',
  'myos.taskMode',
  'myos.weekly',
  'myos.activity',
  'myos.appearance',
  'myos.crypto',
  'myos.sixPack'
] as const;

export const STATE_KEYS: ReadonlySet<string> = new Set([
  ...CURRENT_STATE_KEYS,
  ...LEGACY_STATE_KEYS
]);

/**
 * Finance history is sharded (`meos.finance.tx.2024`, `.tx.2024.2`,
 * `.audit.2024`, `.import.<batch>`) so a lifetime of rows never approaches D1's
 * 2 MB value limit. Only this namespace gets a prefix rule; every other module
 * stays an exact key.
 */
const FINANCE_SHARD_RE = /^meos\.finance(?:\.[a-z0-9._-]{1,60})?$/;

export function isAllowedStateKey(key: string): boolean {
  if (!key || key.includes('..')) return false;
  return STATE_KEYS.has(key) || FINANCE_SHARD_RE.test(key);
}

/**
 * D1's documented maximum row/value size is 2,000,000 bytes. Leave headroom for
 * the row's other columns and SQLite's record header, and measure UTF-8 bytes
 * rather than JavaScript string length.
 */
export const MAX_STATE_VALUE_BYTES = 1_900_000;
