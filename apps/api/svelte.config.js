import adapterNetlify from '@sveltejs/adapter-netlify';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// MyOS is deployed to Netlify only (the local node backend is retired), so every
// build uses the Netlify adapter. `npm run dev` still uses Vite's dev server and
// doesn't touch the adapter. This avoids the reserved NETLIFY env var being
// unset during a local `netlify deploy --build` and silently shipping adapter-node.

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapterNetlify()
  }
};

export default config;
