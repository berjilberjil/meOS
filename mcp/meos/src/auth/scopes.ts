/**
 * Permission scopes.
 *
 * A client is granted a set of scopes by server-side configuration only. Nothing
 * in a tool call can widen them. `read` is the floor; everything that changes
 * data needs `write`; irreversible actions need `destructive` *and* an explicit
 * `confirm: true` argument. `health` gates health, fitness, diet and body-photo
 * data; `secret` gates locked notes, the profile's private brief, and other
 * explicitly-private fields.
 */
export type Scope = 'read' | 'write' | 'destructive' | 'health' | 'secret';

export const ALL_SCOPES: readonly Scope[] = ['read', 'write', 'destructive', 'health', 'secret'];

export function isScope(value: string): value is Scope {
  return (ALL_SCOPES as readonly string[]).includes(value);
}

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

export function hasScope(scopes: readonly Scope[], needed: Scope): boolean {
  return scopes.includes(needed);
}

export function hasEveryScope(scopes: readonly Scope[], needed: readonly Scope[]): boolean {
  return needed.every((s) => scopes.includes(s));
}
