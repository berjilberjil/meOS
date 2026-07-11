import { describe, it, expect } from 'vitest';
import { createClient } from '@supabase/supabase-js';

// Integration test against the local Supabase stack. Skipped unless the anon +
// service_role keys are provided (so the default unit run doesn't need Docker).
const URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const ANON = process.env.SUPABASE_ANON_KEY ?? '';
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';

// Public signup is disabled (config.toml enable_signup = false), so create test
// users via the admin API (service_role), then sign in with the anon client.
async function userClient(email: string) {
	const admin = createClient(URL, SERVICE, { auth: { autoRefreshToken: false, persistSession: false } });
	await admin.auth.admin.createUser({ email, password: 'Passw0rd!test', email_confirm: true });
	const c = createClient(URL, ANON);
	await c.auth.signInWithPassword({ email, password: 'Passw0rd!test' });
	return c;
}

describe.skipIf(!ANON || !SERVICE)('RLS isolation', () => {
	it('a user cannot read another user rows', async () => {
		const stamp = `${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
		const a = await userClient(`a_${stamp}@t.test`);
		const { error: insErr } = await a.from('links').insert({
			source_type: 'goal',
			source_id: crypto.randomUUID(),
			relation: 'funds',
			target_type: 'txn',
			target_id: crypto.randomUUID()
		});
		expect(insErr).toBeNull();

		const b = await userClient(`b_${stamp}@t.test`);
		const { data } = await b.from('links').select('*');
		expect(data).toEqual([]); // B sees none of A's rows
	});

	it('a user cannot read another user profile or invites', async () => {
		const stamp = `${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
		const a = await userClient(`a_${stamp}@t.test`);
		const aId = (await a.auth.getUser()).data.user!.id;
		await a.from('profile').upsert({ user_id: aId, display_name: 'Alice' });
		await a.from('invites').insert({ code: `A-${stamp}`.slice(0, 12).toUpperCase() });

		const b = await userClient(`b_${stamp}@t.test`);
		const { data: profiles } = await b.from('profile').select('*');
		expect((profiles ?? []).every((p: { display_name: string | null }) => p.display_name !== 'Alice')).toBe(true);

		const { data: invites } = await b.from('invites').select('*');
		expect(invites).toEqual([]); // B sees none of A's invites
	});
});
