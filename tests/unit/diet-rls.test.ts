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

describe.skipIf(!ANON || !SERVICE)('diet plan RLS isolation', () => {
	it('a user cannot read another user diet weeks or slots', async () => {
		const stamp = `${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
		const a = await userClient(`da_${stamp}@t.test`);
		const { data: week, error: weekErr } = await a
			.from('diet_weeks')
			.insert({ week_start: '2026-08-17' })
			.select()
			.single();
		expect(weekErr).toBeNull();
		expect(week).toBeTruthy();

		const { data: foods } = await a.from('food_items').select('id').limit(1);
		const foodId = foods?.[0]?.id as string | undefined;
		if (foodId) {
			const { error: slotErr } = await a.from('diet_slots').insert({
				week_id: week!.id,
				weekday: 0,
				meal: 'breakfast',
				food_id: foodId,
				quantity: 1
			});
			expect(slotErr).toBeNull();
		}

		const b = await userClient(`db_${stamp}@t.test`);
		const { data: weeks } = await b.from('diet_weeks').select('*');
		expect(weeks).toEqual([]);
		const { data: slots } = await b.from('diet_slots').select('*');
		expect(slots).toEqual([]);
	});
});
