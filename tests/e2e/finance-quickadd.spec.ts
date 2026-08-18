import { test, expect, type Page } from '@playwright/test';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

// Idempotent against the persistent local DB: always ensure at least one account
// exists (quick-add auto-selects the first). Repeated runs just add more — harmless.
async function ensureAccount(page: Page) {
	await page.goto('/finance/accounts');
	await page.getByPlaceholder('Name (e.g. HDFC)').fill('Test Bank');
	await page.getByPlaceholder('Opening ₹').fill('10000');
	await page.getByRole('button', { name: 'Add', exact: true }).click();
	await expect(page.getByText('Test Bank').first()).toBeVisible();
}

test('quick-add logs a transaction and it appears in the list', async ({ page }) => {
	await login(page);
	await ensureAccount(page);

	await page.getByRole('button', { name: 'Quick add transaction' }).click();
	await page.getByPlaceholder('0.00').fill('199.50');
	await page.getByRole('button', { name: 'Save' }).click();

	await page.goto('/finance/transactions');
	await expect(page.getByText('₹199.50').first()).toBeVisible();
});

test('offline quick-add syncs after reconnect', async ({ page, context }) => {
	await login(page);
	await ensureAccount(page);

	await context.setOffline(true);
	await page.getByRole('button', { name: 'Quick add transaction' }).click();
	await page.getByPlaceholder('0.00').fill('42.00');
	await page.getByRole('button', { name: 'Save' }).click();

	await context.setOffline(false);
	// Reload while online → authed layout runs flushFinance() on mount, syncing the queue.
	await page.goto('/finance/transactions');
	await expect(page.getByText('₹42.00').first()).toBeVisible({ timeout: 15_000 });
});
