import { redirect } from '@sveltejs/kit';
import { supabaseBrowser } from '$lib/supabase/client';
import type { LayoutLoad } from './$types';

// Runs in the browser (ssr=false). No valid session -> bounce to login.
export const load: LayoutLoad = async () => {
	const {
		data: { session }
	} = await supabaseBrowser().auth.getSession();
	if (!session) throw redirect(302, '/login');
	return { user: session.user };
};
