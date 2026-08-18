import { test, expect } from '@playwright/test';

test('serves a valid PWA manifest', async ({ page, request }) => {
	await page.goto('/');
	const href = await page.locator('link[rel="manifest"]').getAttribute('href');
	expect(href).toBeTruthy();

	const res = await request.get(href!);
	expect(res.ok()).toBeTruthy();

	const manifest = await res.json();
	expect(manifest.name).toBe('MyOS');
	expect(manifest.display).toBe('standalone');
});
