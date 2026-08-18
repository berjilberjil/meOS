import { test, expect, type Page } from '@playwright/test';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

test('add a todo and complete it', async ({ page }) => {
	await login(page);
	await page.goto('/todos');

	const title = `Buy milk ${Date.now()}`;
	await page.getByPlaceholder('What needs doing?').fill(title);
	await page.getByRole('button', { name: 'Add', exact: true }).click();

	await expect(page.getByText(title).first()).toBeVisible();

	// complete it: first unchecked checkbox in the open list
	await page.getByRole('checkbox').first().check();
	await expect(page.getByText('Done (').first()).toBeVisible();
});
