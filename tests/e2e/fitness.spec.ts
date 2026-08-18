import { test, expect, type Page } from '@playwright/test';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

test('diet tab renders the weekly grid and opens a meal slot', async ({ page }) => {
	await login(page);
	await page.goto('/fitness/diet');
	await expect(page.getByRole('heading', { name: 'Diet' })).toBeVisible();
	await expect(page.getByTestId('diet-grid')).toBeVisible();
	await expect(page.getByText('Mon', { exact: true }).first()).toBeVisible();
	await page.getByTestId('diet-slot-0-breakfast').click();
	await expect(page.getByTestId('diet-editor')).toBeVisible();
	await page.getByTestId('diet-search').fill('Chapati');
	await expect(page.getByTestId('diet-add-Chapati / Roti')).toBeVisible();
	await page.getByTestId('diet-add-Chapati / Roti').click();
	await expect(page.getByTestId('diet-slot-0-breakfast')).toContainText('Chapati');

	await page.goto('/fitness/food');
	await expect(page.getByRole('heading', { name: /food/i })).toBeVisible();
});

test('log a workout and see it listed', async ({ page }) => {
	await login(page);
	await page.goto('/fitness/workouts');

	const activity = `Run ${Date.now()}`;
	await page.getByPlaceholder('Activity (e.g. Run)').fill(activity);
	await page.getByPlaceholder('Minutes').fill('30');
	await page.getByRole('button', { name: 'Add', exact: true }).click();

	await expect(page.getByText(activity).first()).toBeVisible();
});
