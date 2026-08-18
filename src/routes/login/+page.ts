import { redirect } from '@sveltejs/kit';
import { supabaseBrowser } from '$lib/supabase/client';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
	const {
		data: { session }
	} = await supabaseBrowser().auth.getSession();
	if (session) throw redirect(302, '/');
	return {};
};
