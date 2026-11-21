import adapterCloudflare from '@sveltejs/adapter-cloudflare';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// MeOS runs on Cloudflare Workers. The D1 and R2 bindings reach the app through
// `event.platform.env` (see src/hooks.server.ts and lib/server/storage.ts).
/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    // The only HTML surface is the static landing page. It loads no third-party
    // scripts and needs no network access, so the policy is default-deny. JSON
    // API responses are unaffected.
    csp: {
      mode: 'auto',
      directives: {
        'default-src': ['self'],
        'script-src': ['self'],
        'style-src': ['self', 'unsafe-inline'],
        'img-src': ['self', 'data:'],
        'font-src': ['self'],
        'connect-src': ['self'],
        'object-src': ['none'],
        'base-uri': ['self'],
        'form-action': ['self'],
        'frame-ancestors': ['none']
      }
    },
    // `platformProxy` gives `bun run dev` the same DB/MEDIA/AI bindings that
    // `wrangler dev` provides, so local development does not 503 on every route.
    adapter: adapterCloudflare({ platformProxy: { enabled: true } })
  }
};

export default config;
