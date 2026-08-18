import { test, expect, type Page } from '@playwright/test';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

test('life map renders center + module nodes', async ({ page }) => {
	await login(page);
	await page.goto('/mindmap');

	await expect(page.getByText('You', { exact: true })).toBeVisible();
	await expect(page.locator('svg').getByText('Finance')).toBeVisible();
	await expect(page.locator('svg').getByText('Journal')).toBeVisible();
});
