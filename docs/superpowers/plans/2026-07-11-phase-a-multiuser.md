# Phase A — Invite-Only Multi-User — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn MyOS from single-owner into many independent, fully-private accounts, where new users can only join via a validated invite.

**Architecture:** Public Supabase signup stays disabled. Owners generate invite codes (stored in a new `invites` table, RLS-scoped to the creator). A new Supabase Edge Function `redeem-invite` validates a code server-side with the `service_role` key and creates the user via the Admin API; the static SPA never holds a privileged key. A `/signup?invite=CODE` page drives it. Per-user RLS (already on every table) makes each account's data invisible to others — verified by an isolation test.

**Tech Stack:** SvelteKit 2 + Svelte 5 runes, Supabase (Postgres + Auth + Edge Functions/Deno), TanStack Svelte Query, Vitest, Bun.

## Global Constraints

- Money = integer paise; physical/nutrient values = integers. (No money in Phase A, but the rule stands for the module.)
- Every user-owned table: `user_id uuid not null default auth.uid() references auth.users(id) on delete cascade`, policy `for all using (user_id = auth.uid()) with check (user_id = auth.uid())`, `grant ... to authenticated`, no `anon` grants. `invites` deviates by keying on `created_by` instead of `user_id` (documented in Task 1).
- Shared trigger `set_updated_at()` already exists (migration `0002_finance.sql`); reuse it, don't redefine.
- Next migration number is `0012`. Latest existing is `0011_assets.sql`.
- Derived values computed at render time, never stored.
- `enable_signup = false` and `enable_anonymous_sign_ins = false` in `supabase/config.toml` MUST stay off.
- Commit as `berjilberjil <berjiljacob@gmail.com>` (never the `@skcript.com` identity). Conventional-commit messages. End commit messages with the required Co-Authored-By trailer.
- Run unit tests with `bunx vitest run <path>` (the `test` npm script calls bare `vitest`, which isn't on PATH). Type-check with `bun run check` (must add 0 new errors).

---

### Task 1: `invites` table migration

**Files:**
- Create: `supabase/migrations/0012_invites.sql`

**Interfaces:**
- Produces: table `invites(id, code, email, created_by, used_by, used_at, expires_at, revoked, created_at)` with RLS policy `own invites` on `created_by = auth.uid()`.

- [ ] **Step 1: Write the migration**

```sql
-- Invite-only signup gate. Public signup stays disabled (config.toml
-- enable_signup = false, unchanged). New users are created exclusively via the
-- redeem-invite Edge Function, which validates a code here with service_role
-- (bypassing RLS) and calls the Admin API. Only an authenticated owner can
-- generate/manage invites from the app. Keyed on created_by (not user_id)
-- because an invite belongs to whoever generated it.
create table invites (
	id uuid primary key default gen_random_uuid(),
	code text not null unique,                     -- short human code, compared uppercase
	email text,                                    -- optional: lock invite to one address
	created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
	used_by uuid references auth.users(id) on delete set null,
	used_at timestamptz,
	expires_at timestamptz not null default (now() + interval '14 days'),
	revoked boolean not null default false,
	created_at timestamptz not null default now()
);
create unique index invites_code_uq on invites (code);
create index invites_created_by_idx on invites (created_by);

alter table invites enable row level security;
create policy "own invites" on invites
	for all using (created_by = auth.uid()) with check (created_by = auth.uid());
grant select, insert, update, delete on table invites to authenticated;
```

- [ ] **Step 2: Apply and verify the migration**

Run (requires local stack — start it with `bunx supabase start` if needed):
```bash
bunx supabase migration up
```
Expected: applies `0012_invites.sql` with no error. If the stack isn't running, defer to Task 8's reset. Verify the table exists:
```bash
bunx supabase db execute "select count(*) from invites;"
```
Expected: `0`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0012_invites.sql
git commit -m "feat(auth): invites table + RLS for invite-only signup"
```

---

### Task 2: Invite domain logic (pure, TDD)

Pure helpers with no I/O: code generation (format) and status computation. This is the testable core.

**Files:**
- Create: `src/lib/auth/inviteLogic.ts`
- Test: `tests/unit/invite-logic.test.ts`

**Interfaces:**
- Produces:
  - `formatInviteCode(bytes: Uint8Array): string` — deterministic 8-char code from ≥5 random bytes, grouped `XXXX-XXXX`, uppercase, unambiguous alphabet.
  - `generateInviteCode(): string` — wraps `crypto.getRandomValues`.
  - `type InviteStatus = 'active' | 'used' | 'expired' | 'revoked'`
  - `inviteStatus(inv: { used_by: string | null; expires_at: string; revoked: boolean }, nowIso: string): InviteStatus`

- [ ] **Step 1: Write the failing tests**

```ts
import { describe, it, expect } from 'vitest';
import { formatInviteCode, generateInviteCode, inviteStatus } from '$lib/auth/inviteLogic';

describe('formatInviteCode', () => {
	it('formats 8 chars grouped XXXX-XXXX from bytes, uppercase, no ambiguous chars', () => {
		const code = formatInviteCode(new Uint8Array([0, 1, 2, 3, 250, 200, 150, 100]));
		expect(code).toMatch(/^[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}$/); // excludes I, O
		expect(code).toBe(code.toUpperCase());
	});
	it('is deterministic for the same bytes', () => {
		const b = new Uint8Array([5, 9, 17, 33, 65, 129, 200, 240]);
		expect(formatInviteCode(b)).toBe(formatInviteCode(b));
	});
});

describe('generateInviteCode', () => {
	it('produces a well-formed code', () => {
		expect(generateInviteCode()).toMatch(/^[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}$/);
	});
});

describe('inviteStatus', () => {
	const base = { used_by: null as string | null, expires_at: '2026-08-01T00:00:00Z', revoked: false };
	const now = '2026-07-11T00:00:00Z';
	it('active when unused, unexpired, not revoked', () => {
		expect(inviteStatus(base, now)).toBe('active');
	});
	it('revoked wins over everything', () => {
		expect(inviteStatus({ ...base, revoked: true, used_by: 'u' }, now)).toBe('revoked');
	});
	it('used when used_by set and not revoked', () => {
		expect(inviteStatus({ ...base, used_by: 'u' }, now)).toBe('used');
	});
	it('expired when past expiry, unused, not revoked', () => {
		expect(inviteStatus({ ...base, expires_at: '2026-07-01T00:00:00Z' }, now)).toBe('expired');
	});
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bunx vitest run tests/unit/invite-logic.test.ts`
Expected: FAIL — cannot resolve `$lib/auth/inviteLogic`.

- [ ] **Step 3: Implement**

```ts
// Pure invite helpers — no DB, no crypto side effects except generateInviteCode.
const ALPHABET = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // 34 chars, no I/O to avoid confusion

export function formatInviteCode(bytes: Uint8Array): string {
	let out = '';
	for (let i = 0; i < 8; i++) {
		out += ALPHABET[bytes[i % bytes.length] % ALPHABET.length];
	}
	return `${out.slice(0, 4)}-${out.slice(4)}`;
}

export function generateInviteCode(): string {
	const bytes = new Uint8Array(8);
	crypto.getRandomValues(bytes);
	return formatInviteCode(bytes);
}

export type InviteStatus = 'active' | 'used' | 'expired' | 'revoked';

export function inviteStatus(
	inv: { used_by: string | null; expires_at: string; revoked: boolean },
	nowIso: string
): InviteStatus {
	if (inv.revoked) return 'revoked';
	if (inv.used_by) return 'used';
	if (inv.expires_at < nowIso) return 'expired';
	return 'active';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bunx vitest run tests/unit/invite-logic.test.ts`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add src/lib/auth/inviteLogic.ts tests/unit/invite-logic.test.ts
git commit -m "feat(auth): invite code generation + status logic with tests"
```

---

### Task 3: Invite data layer

**Files:**
- Create: `src/lib/auth/invites.ts`

**Interfaces:**
- Consumes: `SupabaseRepository` from `$lib/data/repository`; `generateInviteCode` from `$lib/auth/inviteLogic`.
- Produces:
  - `interface Invite { id; code; email: string | null; created_by; used_by: string | null; used_at: string | null; expires_at; revoked: boolean; created_at }`
  - `invitesRepo: SupabaseRepository<Invite>`
  - `listInvites(): Promise<Invite[]>`
  - `createInvite(opts?: { email?: string; days?: number }): Promise<Invite>`
  - `revokeInvite(id: string): Promise<void>`

- [ ] **Step 1: Implement**

```ts
import { SupabaseRepository } from '$lib/data/repository';
import { generateInviteCode } from './inviteLogic';

export interface Invite {
	id: string;
	code: string;
	email: string | null;
	created_by: string;
	used_by: string | null;
	used_at: string | null;
	expires_at: string;
	revoked: boolean;
	created_at: string;
}

export const invitesRepo = new SupabaseRepository<Invite>('invites');

export function listInvites(): Promise<Invite[]> {
	return invitesRepo.list();
}

export function createInvite(opts: { email?: string; days?: number } = {}): Promise<Invite> {
	// expires_at default is 14 days server-side; only override when days is given.
	const patch: Partial<Invite> = { code: generateInviteCode(), email: opts.email ?? null };
	if (opts.days != null) {
		const d = new Date();
		d.setDate(d.getDate() + opts.days);
		patch.expires_at = d.toISOString();
	}
	return invitesRepo.create(patch);
}

export function revokeInvite(id: string): Promise<void> {
	return invitesRepo.update(id, { revoked: true }).then(() => undefined);
}
```

- [ ] **Step 2: Type-check**

Run: `bun run check`
Expected: 0 new errors (the 2 pre-existing `client.ts` `$env` errors may remain). Note: `invites` is a new table not in generated Supabase types, but `SupabaseRepository` casts to an untyped client internally, so `invitesRepo` type-checks fine.

- [ ] **Step 3: Commit**

```bash
git add src/lib/auth/invites.ts
git commit -m "feat(auth): invites repository + create/list/revoke helpers"
```

---

### Task 4: `redeem-invite` Edge Function

**Files:**
- Create: `supabase/functions/redeem-invite/index.ts`
- Create: `supabase/functions/redeem-invite/deno.json` (empty `{}` is fine; presence documents it as a function)

**Interfaces:**
- Produces: `POST /functions/v1/redeem-invite` with body `{ code, email, password }` → `200 { ok: true }` or `4xx { ok: false, error }` where error ∈ `invalid_code|expired|already_used|revoked|email_mismatch|email_taken|weak_password|bad_request`.

- [ ] **Step 1: Implement the function**

```ts
// Deno Edge Function. Runs on Supabase with SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
// auto-injected. Validates an invite server-side and creates the user via the
// Admin API — the anon SPA never holds the service key. Public signup stays off.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
	'Access-Control-Allow-Origin': '*',
	'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
	'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

function json(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { ...cors, 'Content-Type': 'application/json' }
	});
}

Deno.serve(async (req) => {
	if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
	if (req.method !== 'POST') return json({ ok: false, error: 'bad_request' }, 405);

	let payload: { code?: string; email?: string; password?: string };
	try {
		payload = await req.json();
	} catch {
		return json({ ok: false, error: 'bad_request' }, 400);
	}
	const code = (payload.code ?? '').trim().toUpperCase();
	const email = (payload.email ?? '').trim().toLowerCase();
	const password = payload.password ?? '';
	if (!code || !email || !password) return json({ ok: false, error: 'bad_request' }, 400);
	if (password.length < 8) return json({ ok: false, error: 'weak_password' }, 400);

	const admin = createClient(
		Deno.env.get('SUPABASE_URL')!,
		Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
		{ auth: { autoRefreshToken: false, persistSession: false } }
	);

	const { data: invite } = await admin
		.from('invites')
		.select('*')
		.eq('code', code)
		.maybeSingle();

	if (!invite) return json({ ok: false, error: 'invalid_code' }, 400);
	if (invite.revoked) return json({ ok: false, error: 'revoked' }, 400);
	if (invite.used_by) return json({ ok: false, error: 'already_used' }, 400);
	if (new Date(invite.expires_at) < new Date()) return json({ ok: false, error: 'expired' }, 400);
	if (invite.email && invite.email.toLowerCase() !== email)
		return json({ ok: false, error: 'email_mismatch' }, 400);

	const { data: created, error: createErr } = await admin.auth.admin.createUser({
		email,
		password,
		email_confirm: true
	});
	if (createErr || !created?.user) {
		const msg = (createErr?.message ?? '').toLowerCase();
		if (msg.includes('already') || msg.includes('registered') || msg.includes('exists'))
			return json({ ok: false, error: 'email_taken' }, 400);
		return json({ ok: false, error: 'bad_request' }, 400);
	}

	// Mark used. If this fails after user creation, log and still succeed — the
	// account exists; a soft-orphaned invite is manually revocable by the owner.
	const { error: updErr } = await admin
		.from('invites')
		.update({ used_by: created.user.id, used_at: new Date().toISOString() })
		.eq('id', invite.id);
	if (updErr) console.error('invite mark-used failed', invite.id, updErr.message);

	return json({ ok: true });
});
```

- [ ] **Step 2: Serve locally and verify a bad code returns 4xx**

Run (local stack up): `bunx supabase functions serve redeem-invite --no-verify-jwt` (in a background terminal), then:
```bash
curl -s -X POST http://localhost:54321/functions/v1/redeem-invite \
  -H 'Content-Type: application/json' \
  -d '{"code":"NOPE-NOPE","email":"x@test.test","password":"password1"}'
```
Expected: `{"ok":false,"error":"invalid_code"}` with HTTP 400.

- [ ] **Step 3: Verify a valid invite creates a user**

Insert a test invite via SQL, then redeem:
```bash
bunx supabase db execute "insert into invites (code, created_by) values ('TEST-1234', (select id from auth.users limit 1));"
curl -s -X POST http://localhost:54321/functions/v1/redeem-invite \
  -H 'Content-Type: application/json' \
  -d '{"code":"TEST-1234","email":"newuser@test.test","password":"password1"}'
```
Expected: `{"ok":true}`. Re-running the same curl returns `{"ok":false,"error":"already_used"}`.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/redeem-invite/
git commit -m "feat(auth): redeem-invite edge function (server-side invite validation)"
```

---

### Task 5: `/signup` page

**Files:**
- Create: `src/routes/(auth)/signup/+page.svelte` (confirm the auth route group name by checking where the existing login page lives, e.g. `src/routes/login/` vs `src/routes/(auth)/login/`; place signup in the same group)
- Create: `src/lib/auth/redeem.ts` (client caller + error copy map)

**Interfaces:**
- Consumes: `PUBLIC_SUPABASE_URL` from `$env/static/public`; `supabaseBrowser` from `$lib/supabase/client`.
- Produces: `redeemInvite(input: { code; email; password }): Promise<{ ok: true } | { ok: false; error: string }>` and `REDEEM_ERROR_COPY: Record<string, string>`.

- [ ] **Step 1: Implement the client caller + copy map**

```ts
// src/lib/auth/redeem.ts
import { PUBLIC_SUPABASE_URL } from '$env/static/public';

export const REDEEM_ERROR_COPY: Record<string, string> = {
	invalid_code: "That invite code doesn't exist. Check for typos.",
	expired: 'This invite has expired. Ask for a new one.',
	already_used: 'This invite has already been used.',
	revoked: 'This invite is no longer valid.',
	email_mismatch: 'This invite was issued for a different email address.',
	email_taken: 'An account with this email already exists — try signing in instead.',
	weak_password: 'Password must be at least 8 characters.',
	bad_request: 'Please fill in every field.',
	unknown: 'Something went wrong. Try again.'
};

export async function redeemInvite(input: { code: string; email: string; password: string }) {
	try {
		const res = await fetch(`${PUBLIC_SUPABASE_URL}/functions/v1/redeem-invite`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(input)
		});
		return (await res.json()) as { ok: true } | { ok: false; error: string };
	} catch {
		return { ok: false as const, error: 'unknown' };
	}
}
```

- [ ] **Step 2: Implement the signup page**

```svelte
<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { supabaseBrowser } from '$lib/supabase/client';
	import { redeemInvite, REDEEM_ERROR_COPY } from '$lib/auth/redeem';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';

	let code = $state((page.url.searchParams.get('invite') ?? '').toUpperCase());
	let email = $state(page.url.searchParams.get('email') ?? '');
	let password = $state('');
	let confirm = $state('');
	let error = $state('');
	let busy = $state(false);

	async function submit() {
		error = '';
		if (password !== confirm) { error = 'Passwords do not match.'; return; }
		busy = true;
		const r = await redeemInvite({ code: code.trim().toUpperCase(), email: email.trim(), password });
		if (!r.ok) { error = REDEEM_ERROR_COPY[r.error] ?? REDEEM_ERROR_COPY.unknown; busy = false; return; }
		const { error: signInErr } = await supabaseBrowser().auth.signInWithPassword({ email: email.trim(), password });
		busy = false;
		if (signInErr) { error = 'Account created — please sign in.'; goto('/login'); return; }
		goto('/');
	}
</script>

<div class="mx-auto flex min-h-dvh max-w-sm flex-col justify-center gap-4 p-6">
	<h1 class="text-xl font-semibold">Join MyOS</h1>
	<p class="text-sm text-muted-foreground">You need an invite code to create an account.</p>
	<Input placeholder="Invite code" bind:value={code} onblur={() => (code = code.trim().toUpperCase())} />
	<Input type="email" placeholder="Email" bind:value={email} />
	<Input type="password" placeholder="Password (min 8)" bind:value={password} />
	<Input type="password" placeholder="Confirm password" bind:value={confirm} />
	{#if error}<p class="text-sm text-destructive">{error}</p>{/if}
	<Button disabled={busy || !code || !email || !password} onclick={submit}>Create account</Button>
	<a href="/login" class="text-center text-sm text-muted-foreground hover:underline">Already have an account? Sign in</a>
</div>
```

- [ ] **Step 3: Type-check**

Run: `bun run check`
Expected: 0 new errors.

- [ ] **Step 4: Manual verify (local stack + function served)**

Visit `http://localhost:5177/signup?invite=TEST-9999` (create that invite first via SQL). Submit with a fresh email/password → lands signed-in at `/`. Bad code → shows the mapped error.

- [ ] **Step 5: Commit**

```bash
git add src/lib/auth/redeem.ts "src/routes/(auth)/signup/+page.svelte"
git commit -m "feat(auth): /signup page redeeming invites"
```

---

### Task 6: Auto-create profile on first login

**Files:**
- Modify: the post-login/session-bootstrap path. Find it first: `grep -rn "onAuthStateChange\|signInWithPassword\|getSession" src/lib src/routes` and check `src/lib/profile/` for the existing profile accessor (the spec references `getPersonal()`).
- Create (if no profile module fn exists): add `ensureProfile()` to `src/lib/profile/personal.ts` (or wherever profile access lives).

**Interfaces:**
- Produces: `ensureProfile(): Promise<void>` — inserts `{ user_id, display_name: email.split('@')[0] }` if no profile row exists for the current user; no-op otherwise.

- [ ] **Step 1: Implement `ensureProfile`**

```ts
// Add to the existing profile module (mirror its existing supabase access style).
import { supabaseBrowser } from '$lib/supabase/client';

export async function ensureProfile(): Promise<void> {
	const db = supabaseBrowser();
	const { data: auth } = await db.auth.getUser();
	const user = auth.user;
	if (!user) return;
	const { data: existing } = await db.from('profile').select('user_id').eq('user_id', user.id).maybeSingle();
	if (existing) return;
	const fallback = (user.email ?? 'friend').split('@')[0];
	await db.from('profile').insert({ user_id: user.id, display_name: fallback });
}
```

- [ ] **Step 2: Call it after a session is established**

In the session-bootstrap location found above (e.g. the root `(app)` layout `onMount` after confirming a session, or the `onAuthStateChange('SIGNED_IN')` handler), call `await ensureProfile();`. Wrap in try/catch so a failure never blocks the app.

- [ ] **Step 3: Type-check + manual verify**

Run: `bun run check` → 0 new errors. Manually: sign in as the freshly-created user from Task 5; confirm a `profile` row appears:
```bash
bunx supabase db execute "select user_id, display_name from profile;"
```
Expected: a row with `display_name` = the email local-part.

- [ ] **Step 4: Commit**

```bash
git add src/lib/profile/personal.ts src/routes  # adjust to the files actually touched
git commit -m "feat(auth): auto-create profile row on first login"
```

---

### Task 7: Invite management UI + sign-in cross-link

**Files:**
- Modify: `src/routes/(app)/profile/+page.svelte` (add an "Invites" card) — confirm this route exists; otherwise add a small section to an existing settings surface.
- Modify: the login page (`src/routes/login/+page.svelte` or wherever it lives) — add a "Have an invite? Sign up" link to `/signup`.

**Interfaces:**
- Consumes: `listInvites`, `createInvite`, `revokeInvite`, `Invite` from `$lib/auth/invites`; `inviteStatus` from `$lib/auth/inviteLogic`.

- [ ] **Step 1: Add the Invites card to the profile page**

```svelte
<!-- Invites: generate/copy/revoke codes to bring people onto MyOS. -->
<script lang="ts">
	// ...existing profile script...
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { listInvites, createInvite, revokeInvite } from '$lib/auth/invites';
	import { inviteStatus } from '$lib/auth/inviteLogic';
	import { toast } from 'svelte-sonner';

	const qc = useQueryClient();
	const invites = createQuery(() => ({ queryKey: ['invites'], queryFn: () => listInvites() }));
	const gen = createMutation(() => ({
		mutationFn: () => createInvite(),
		onSuccess: () => { qc.invalidateQueries({ queryKey: ['invites'] }); toast.success('Invite created'); }
	}));
	const rev = createMutation(() => ({
		mutationFn: (id: string) => revokeInvite(id),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['invites'] })
	}));
	const nowIso = new Date().toISOString();
	function copyLink(code: string) {
		navigator.clipboard.writeText(`${location.origin}/signup?invite=${code}`);
		toast.success('Invite link copied');
	}
</script>

<Card.Root>
	<Card.Header class="flex-row items-center justify-between">
		<Card.Title>Invites</Card.Title>
		<Button disabled={gen.isPending} onclick={() => gen.mutate()}>Generate</Button>
	</Card.Header>
	<Card.Content class="flex flex-col gap-2">
		{#each invites.data ?? [] as inv (inv.id)}
			{@const status = inviteStatus(inv, nowIso)}
			<div class="flex items-center gap-2 text-sm">
				<span class="font-mono font-semibold">{inv.code}</span>
				<span class="rounded-full bg-secondary px-2 py-0.5 text-xs">{status}</span>
				{#if status === 'active'}
					<button class="text-xs text-muted-foreground hover:underline" onclick={() => copyLink(inv.code)}>Copy link</button>
					<button class="ml-auto text-xs text-muted-foreground hover:text-destructive" onclick={() => rev.mutate(inv.id)}>Revoke</button>
				{/if}
			</div>
		{:else}
			<p class="text-sm text-muted-foreground">No invites yet. Generate one to add someone.</p>
		{/each}
	</Card.Content>
</Card.Root>
```

- [ ] **Step 2: Add the sign-in → signup link**

In the login page template, add near the submit button:
```svelte
<a href="/signup" class="text-center text-sm text-muted-foreground hover:underline">Have an invite? Sign up</a>
```

- [ ] **Step 3: Type-check + manual verify**

Run: `bun run check` → 0 new errors. Manually: Generate an invite on the profile page, copy the link, open it in a private window, complete signup.

- [ ] **Step 4: Commit**

```bash
git add "src/routes/(app)/profile/+page.svelte" src/routes/login
git commit -m "feat(auth): invite management UI + sign-up link on login"
```

---

### Task 8: Cross-user isolation RLS test

**Files:**
- Modify: `tests/unit/rls.test.ts` (extend the existing env-gated block; reuse its `userClient(email)` helper)

**Interfaces:**
- Consumes: the existing `userClient` helper and `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` env gating already in the file.

- [ ] **Step 1: Add the isolation test**

```ts
it('a user cannot read another user\'s profile or invites', async () => {
	const stamp = `${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
	const a = await userClient(`a_${stamp}@t.test`);
	const aId = (await a.auth.getUser()).data.user!.id;
	await a.from('profile').upsert({ user_id: aId, display_name: 'Alice' });
	await a.from('invites').insert({ code: `A-${stamp}`.toUpperCase().slice(0, 9) });

	const b = await userClient(`b_${stamp}@t.test`);
	const { data: profiles } = await b.from('profile').select('*');
	expect((profiles ?? []).every((p: { display_name: string | null }) => p.display_name !== 'Alice')).toBe(true);

	const { data: invites } = await b.from('invites').select('*');
	expect(invites).toEqual([]); // B sees none of A's invites
});
```

- [ ] **Step 2: Run the RLS suite (needs local stack + both keys)**

Run:
```bash
export SUPABASE_ANON_KEY="$(bunx supabase status -o env | grep '^ANON_KEY=' | cut -d'"' -f2)"
export SUPABASE_SERVICE_ROLE_KEY="$(bunx supabase status -o env | grep '^SERVICE_ROLE_KEY=' | cut -d'"' -f2)"
bunx vitest run tests/unit/rls.test.ts
```
Expected: PASS, including the new isolation test. (If the stack isn't running, this test is env-skipped like the rest of the file — note that in the commit body.)

- [ ] **Step 3: Commit**

```bash
git add tests/unit/rls.test.ts
git commit -m "test(auth): cross-user isolation for profile + invites"
```

---

## Self-Review

**Spec coverage (Phase A section of the design):**
- A.1 mechanism (edge function) → Task 4 ✓
- A.2 `invites` table + RLS → Task 1 ✓
- A.3 signup UX + error mapping → Task 5 ✓; invite management UI → Task 7 ✓
- A.4 config.toml (no change) → Global Constraints note ✓
- A.5 profile onboarding → Task 6 ✓
- A.6 data-safety test → Task 8 ✓
- Domain logic (code gen/status) not explicitly in spec but required → Task 2 ✓

**Placeholder scan:** No TBD/TODO. Tasks 6 and 7 instruct locating the exact session-bootstrap and profile/login file paths first (grep commands given) — these are genuine codebase-discovery steps, not hand-waved implementation; the code to write is fully specified.

**Type consistency:** `Invite` shape defined in Task 3 matches columns in Task 1 and fields read in Tasks 4/7. `redeemInvite` return shape (Task 5) matches the edge function's response (Task 4). `inviteStatus` signature (Task 2) matches its use in Task 7. `generateInviteCode` (Task 2) used by Task 3. Consistent.

**Owner-dependency:** Task 4's function must be deployed to the hosted project (`supabase functions deploy redeem-invite`) before signup works in production — flagged in the spec's "requires the owner" section; local dev uses `supabase functions serve`.
