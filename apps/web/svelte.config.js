import adapterNode from '@sveltejs/adapter-node';
import adapterNetlify from '@sveltejs/adapter-netlify';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// Netlify sets NETLIFY=true during its build → use the Netlify adapter there.
// Locally we use adapter-node so `npm run dev`/`preview` and the mac app's dev
// backend keep working.
const onNetlify = !!process.env.NETLIFY;

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: onNetlify ? adapterNetlify() : adapterNode()
  }
};

export default config;
