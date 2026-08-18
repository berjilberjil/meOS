import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

// Journaling is the daily driver, so the app opens into it. Today lives
// at /dashboard (the elevated center button in the bottom dock).
export const load: PageLoad = () => {
	throw redirect(307, '/journal');
};
