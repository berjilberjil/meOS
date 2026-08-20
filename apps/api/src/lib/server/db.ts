import { AsyncLocalStorage } from 'node:async_hooks';

/**
 * D1 (SQLite) behind a `postgres.js`-shaped tagged template.
 *
 * The whole backend is four tables and ~20 single-table queries — no joins, no
 * jsonb operators, no extensions — so moving off Postgres is a driver swap
 * rather than a rewrite. Keeping the `sql` tagged-template shape means none of
 * the call sites had to change.
 *
 * The binding arrives per-request on `platform.env`, so there is no module-level
 * connection to hold. `hooks.server.ts` wraps each request in `withDB`, and
 * AsyncLocalStorage carries it down to whatever runs inside — which is why this
 * still looks like a singleton to callers.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */
type Row = Record<string, any>;
type D1Result = { results?: Row[] };
type D1Statement = { bind: (...v: unknown[]) => D1Statement; all: () => Promise<D1Result> };
export type D1Database = { prepare: (q: string) => D1Statement };

const ctx = new AsyncLocalStorage<D1Database>();

/** Run `fn` with `db` as the ambient connection for this request. */
export function withDB<T>(db: D1Database, fn: () => T): T {
  return ctx.run(db, fn);
}

function db(): D1Database {
  const d = ctx.getStore();
  if (!d) throw new Error('No D1 binding for this request (is the DB binding configured?)');
  return d;
}

/**
 * Columns holding JSON. Postgres `jsonb` handed back parsed objects; SQLite
 * stores TEXT, so revive them or every caller would suddenly see a string.
 */
const JSON_COLUMNS = ['value', 'models'];

function bindable(v: unknown): unknown {
  if (v === undefined || v === null) return null;
  if (typeof v === 'boolean') return v ? 1 : 0; // SQLite has no boolean
  if (v instanceof Date) return v.toISOString();
  if (typeof v === 'object') return JSON.stringify(v);
  return v;
}

function revive(row: Row): Row {
  for (const col of JSON_COLUMNS) {
    const raw = row[col];
    if (typeof raw === 'string') {
      try {
        row[col] = JSON.parse(raw);
      } catch {
        /* not JSON after all — leave it */
      }
    }
  }
  return row;
}

/**
 * `sql` tagged template -> prepared statement with `?` binds. With N
 * interpolations there are N+1 literal chunks, so joining on '?' yields exactly
 * N placeholders. Values are bound, never concatenated into the SQL text.
 */
export async function sql(
  strings: TemplateStringsArray,
  ...values: unknown[]
): Promise<Row[]> {
  const query = strings.join('?');
  const stmt = db().prepare(query);
  const bound = values.length ? stmt.bind(...values.map(bindable)) : stmt;
  const res = await bound.all();
  return (res.results ?? []).map(revive);
}

/** Marks a value as JSON, mirroring `postgres.js`'s `sql.json()`. */
sql.json = (v: unknown): string => JSON.stringify(v);

/**
 * ISO-8601 UTC — the one timestamp format this database uses. SQLite's
 * `current_timestamp` renders `YYYY-MM-DD HH:MM:SS`, which does NOT sort
 * against an ISO string ('T' > ' '), so timestamps are always written from
 * here instead of from SQL.
 */
export function nowISO(): string {
  return new Date().toISOString();
}
