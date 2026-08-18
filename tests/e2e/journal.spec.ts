import { test, expect, type Page } from '@playwright/test';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

test('create a journal entry with title + body', async ({ page }) => {
	await login(page);
	await page.goto('/journal/new');

	await page.getByPlaceholder('Title').fill('Test day');
	await page.locator('.ProseMirror').click();
	await page.locator('.ProseMirror').pressSequentially('Today was a good day.');
	await page.getByRole('button', { name: 'Save entry' }).click();

	await page.waitForURL('**/journal');
	await expect(page.getByText('Test day').first()).toBeVisible();
});
