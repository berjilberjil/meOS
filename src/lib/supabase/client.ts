import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import type { Database } from './types';

let client: SupabaseClient<Database> | undefined;

export function supabaseBrowser() {
	if (!client) {
		// Pure SPA (ssr=false): persist the auth session in localStorage, not cookies.
		// The bundled macOS (Tauri) app runs on the `tauri://localhost` custom-protocol
		// origin, where WKWebView silently drops cookie writes — so cookie-backed
		// sessions never persist and the app loops back to /login. localStorage works
		// on the custom-protocol origin.
		client = createClient<Database>(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
			auth: {
				persistSession: true,
				autoRefreshToken: true,
				detectSessionInUrl: true,
				storage: typeof window !== 'undefined' ? window.localStorage : undefined
			}
		});
	}
	return client;
}
