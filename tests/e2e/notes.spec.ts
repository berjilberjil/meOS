import { test, expect, type Page } from '@playwright/test';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

test('create a note', async ({ page }) => {
	await login(page);
	await page.goto('/notes/new');

	const title = `Idea ${Date.now()}`;
	await page.getByPlaceholder('Title').fill(title);
	await page.locator('.ProseMirror').click();
	await page.locator('.ProseMirror').pressSequentially('Remember this.');
	await page.getByRole('button', { name: 'Save note' }).click();

	await page.waitForURL('**/notes');
	await expect(page.getByText(title).first()).toBeVisible();
});
