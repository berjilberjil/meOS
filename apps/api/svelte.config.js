import adapterCloudflare from '@sveltejs/adapter-cloudflare';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// MeOS runs on Cloudflare Workers. The D1 and R2 bindings reach the app through
// `event.platform.env` (see src/hooks.server.ts and lib/server/storage.ts).
/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapterCloudflare()
  }
};

export default config;
