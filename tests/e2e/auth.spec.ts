import { test, expect } from '@playwright/test';

test('unauthenticated user is redirected to login', async ({ page }) => {
	await page.context().clearCookies();
	await page.goto('/');
	await expect(page).toHaveURL(/\/login/);
	await expect(page.getByPlaceholder('email')).toBeVisible();
});
