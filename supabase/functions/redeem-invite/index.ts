// Deno Edge Function. Runs on Supabase with SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
// auto-injected. Validates an invite server-side and creates the user via the
// Admin API — the anon SPA never holds the service key. Public signup stays off;
// this is the only path to a new account. Configured with verify_jwt = false
// (config.toml) so it's callable before the user has a session.
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

	const { data: invite } = await admin.from('invites').select('*').eq('code', code).maybeSingle();

	if (!invite) return json({ ok: false, error: 'invalid_code' }, 400);
	if (invite.revoked) return json({ ok: false, error: 'revoked' }, 400);
	if (invite.used_by) return json({ ok: false, error: 'already_used' }, 400);
	if (new Date(invite.expires_at) < new Date()) return json({ ok: false, error: 'expired' }, 400);
	if (invite.email && String(invite.email).toLowerCase() !== email)
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
