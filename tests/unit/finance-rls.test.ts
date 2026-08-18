import { describe, it, expect } from 'vitest';
import { createClient } from '@supabase/supabase-js';

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

describe.skipIf(!ANON || !SERVICE)('finance RLS isolation', () => {
	it('a user cannot read another user accounts', async () => {
		const stamp = `${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
		const a = await userClient(`fa_${stamp}@t.test`);
		const { error: insErr } = await a.from('accounts').insert({ name: 'HDFC', type: 'bank' });
		expect(insErr).toBeNull();

		const b = await userClient(`fb_${stamp}@t.test`);
		const { data } = await b.from('accounts').select('*');
		expect(data).toEqual([]);
	});
});
