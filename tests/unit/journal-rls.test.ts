import { describe, it, expect } from 'vitest';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const ANON = process.env.SUPABASE_ANON_KEY ?? '';
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';

async function userClient(email: string) {
	const admin = createClient(URL, SERVICE, { auth: { autoRefreshToken: false, persistSession: false } });
	await admin.auth.admin.createUser({ email, password: 'Passw0rd!test', email_confirm: true });
	const c = createClient(URL, ANON);
	await c.auth.signInWithPassword({ email, password: 'Passw0rd!test' });
	return c;
}

describe.skipIf(!ANON || !SERVICE)('journal RLS isolation', () => {
	it('a user cannot read another user journal entries', async () => {
		const stamp = `${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
		const a = await userClient(`ja_${stamp}@t.test`);
		const { error: insErr } = await a.from('journal_entries').insert({ title: 'secret', occurred_on: '2026-06-26' });
		expect(insErr).toBeNull();

		const b = await userClient(`jb_${stamp}@t.test`);
		const { data } = await b.from('journal_entries').select('*');
		expect(data).toEqual([]);
	});
});
