import { defineConfig } from '@playwright/test';

// E2E runs against the production build (preview): the PWA manifest + service
// worker are real and stable, and SSR behaves as in production.
export default defineConfig({
	testDir: 'tests/e2e',
	use: { baseURL: 'http://localhost:4173' },
	webServer: {
		command: 'bun run build && bun run preview -- --port 4173',
		port: 4173,
		reuseExistingServer: !process.env.CI,
		timeout: 120_000
	}
});
