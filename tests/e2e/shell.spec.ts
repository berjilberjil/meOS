import { test, expect, type Page } from '@playwright/test';

// Local owner account created via admin API in Task 7.
async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	// Lands on the guarded dashboard. Wait on the sidebar theme toggle, which only
	// renders when authenticated (the login card title is also "MyOS").
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
	await page.goto('/dashboard');
	await expect(page.getByTestId('theme-toggle')).toBeVisible();
}

test('authenticated shell renders and the theme toggle cycles + applies classes', async ({
	page
}) => {
	await login(page);

	const toggle = page.getByTestId('theme-toggle');
	await expect(toggle).toContainText('system');

	await toggle.click(); // system -> light
	await expect(toggle).toContainText('light');

	await toggle.click(); // light -> dark
	await expect(toggle).toContainText('dark');
	await expect(page.locator('html')).toHaveClass(/dark/);
});
