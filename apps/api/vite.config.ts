import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [sveltekit()],
  // The Argon2id path is optional, but when enabled its WASM-backed package must
  // be bundled into the Worker rather than left as a bare runtime import.
  ssr: { noExternal: ['hash-wasm'] },
  test: {
    environment: 'node',
    include: ['src/**/*.{test,spec}.ts']
  }
});
