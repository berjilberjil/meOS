import { supabaseBrowser } from '$lib/supabase/client';

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

type RedeemResult = { ok: true } | { ok: false; error: string };

// Calls the redeem-invite Edge Function via the Supabase client (uses the
// configured project URL + anon key; no privileged key on the client). On a
// non-2xx the client returns a FunctionsHttpError whose .context is the raw
// Response — we read our structured { ok:false, error } out of it.
export async function redeemInvite(input: {
	code: string;
	email: string;
	password: string;
}): Promise<RedeemResult> {
	const { data, error } = await supabaseBrowser().functions.invoke('redeem-invite', { body: input });
	if (error) {
		const ctx = (error as { context?: Response }).context;
		if (ctx && typeof ctx.json === 'function') {
			try {
				const body = (await ctx.json()) as { error?: string };
				if (body?.error) return { ok: false, error: body.error };
			} catch {
				/* fall through */
			}
		}
		return { ok: false, error: 'unknown' };
	}
	return data as RedeemResult;
}
