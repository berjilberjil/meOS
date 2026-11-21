import { errors } from './errors.ts';

export interface Page<T> {
  items: T[];
  page: {
    limit: number;
    returned: number;
    next_cursor: string | null;
    has_more: boolean;
  };
}

export const DEFAULT_LIMIT = 25;
export const MAX_LIMIT = 100;

export function clampLimit(limit: number | undefined, fallback = DEFAULT_LIMIT): number {
  if (limit == null) return fallback;
  if (!Number.isInteger(limit) || limit < 1) throw errors.invalidInput('limit must be a positive integer');
  return Math.min(limit, MAX_LIMIT);
}

/**
 * Opaque offset cursors. Deliberately not an item id: several MeOS collections
 * (to-dos, goals, profile strings) have no stable ordering key, and an offset is
 * the only cursor that cannot silently skip a record when one is edited between
 * pages.
 */
export function encodeCursor(offset: number): string {
  return Buffer.from(JSON.stringify({ o: offset }), 'utf8').toString('base64url');
}

export function decodeCursor(cursor: string | undefined): number {
  if (!cursor) return 0;
  try {
    const parsed = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as { o?: unknown };
    const offset = Number(parsed.o);
    if (!Number.isInteger(offset) || offset < 0) throw new Error('bad offset');
    return offset;
  } catch {
    throw errors.invalidInput('cursor is invalid; omit it to start from the first page');
  }
}

export function paginate<T>(items: T[], limitInput: number | undefined, cursor: string | undefined): Page<T> {
  const limit = clampLimit(limitInput);
  const offset = decodeCursor(cursor);
  const slice = items.slice(offset, offset + limit);
  const next = offset + slice.length;
  const hasMore = next < items.length;
  return {
    items: slice,
    page: {
      limit,
      returned: slice.length,
      next_cursor: hasMore ? encodeCursor(next) : null,
      has_more: hasMore
    }
  };
}

/** Deterministic sort for ISO-ish stamps, newest first. */
export function byNewest<T>(get: (item: T) => string | undefined | null): (a: T, b: T) => number {
  return (a, b) => (get(b) ?? '').localeCompare(get(a) ?? '');
}
