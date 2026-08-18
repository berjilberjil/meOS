import { test, expect, type Page } from '@playwright/test';

const GEMINI = '**generativelanguage.googleapis.com**';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

/** Gemini is never called for real in e2e: seed a key so the UI is unlocked, then
 *  serve a canned candidate so the capture/scan flows stay deterministic. */
async function stubGemini(page: Page, payload: unknown) {
	await page.addInitScript(() => {
		localStorage.setItem('myos:gemini-key', 'test-key');
	});
	await page.route(GEMINI, (route) =>
		route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({
				candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }]
			})
		})
	);
}

test('Today renders the day, the do-now card and the coming-up list', async ({ page }) => {
	await login(page);
	await page.goto('/dashboard');

	// Heading is the weekday, and the greeting/date come from pure today.ts logic.
	const weekday = new Date().toLocaleDateString('en-US', { weekday: 'long' });
	await expect(page.getByRole('heading', { name: weekday })).toBeVisible();
	await expect(page.getByText('Do now')).toBeVisible();
	await expect(page.getByRole('heading', { name: 'Coming up' })).toBeVisible();

	// Settings live inline on Today now (the theme toggle moved off the sidebar).
	await expect(page.getByTestId('theme-toggle')).toBeVisible();
});

test('capture bar routes a spoken/typed event into To-dos', async ({ page }) => {
	const title = `Dentist ${Date.now()}`;
	await stubGemini(page, { kind: 'todo', title, date: new Date().toISOString().slice(0, 10), priority: 2 });

	await login(page);
	await page.goto('/dashboard');

	await page.getByLabel('Add an event').fill(title);
	await page.getByRole('button', { name: 'Add', exact: true }).click();

	// Input clears on success, and the event lands in the To-dos module.
	await expect(page.getByLabel('Add an event')).toHaveValue('');
	await page.goto('/todos');
	await expect(page.getByText(title).first()).toBeVisible();
});

test('Scan reads a food photo and offers to log it', async ({ page }) => {
	await stubGemini(page, {
		kind: 'food',
		name: 'Masala dosa',
		serving: '1 plate',
		energy_kcal: 350,
		protein_g: 8,
		carb_g: 52,
		fat_g: 10,
		detail: 'Fermented rice-lentil crepe.'
	});

	await login(page);
	await page.goto('/scan');
	await expect(page.getByRole('heading', { name: 'Scan' })).toBeVisible();

	// A 1x1 PNG is enough — the model response is stubbed.
	await page.setInputFiles('input[type="file"]', {
		name: 'meal.png',
		mimeType: 'image/png',
		buffer: Buffer.from(
			'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
			'base64'
		)
	});

	await expect(page.getByRole('heading', { name: 'Masala dosa' })).toBeVisible();
	await expect(page.getByText('350')).toBeVisible();
	await expect(page.getByRole('button', { name: 'Log this meal' })).toBeVisible();
});
