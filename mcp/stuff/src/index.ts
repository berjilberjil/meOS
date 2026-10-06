#!/usr/bin/env bun
/**
 * MeOS Stuff MCP — log what you buy, from a receipt.
 *
 * Point it at an Amazon (or any) order screenshot and it records the product
 * link, title, category, purchase date, price and the payback window, keeping
 * the bill image with the item. Writes go through the Mac app's loopback bridge
 * into the same encrypted store the Stuff tab uses, so everything syncs to the
 * iPhone on its own.
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { readBill, store } from './store';
import { canonicalLink, DEFAULT_ROI_MONTHS, parseDate, parseInr, todayIso } from './receipt';

function json(data: unknown) {
	return { content: [{ type: 'text' as const, text: JSON.stringify(data, null, 2) }] };
}
function fail(err: unknown) {
	const message = err instanceof Error ? err.message : JSON.stringify(err);
	console.error(`[meos-stuff] ${message}`);
	return { content: [{ type: 'text' as const, text: `Error: ${message}` }], isError: true as const };
}

const Bill = {
	bill_image_path: z
		.string()
		.optional()
		.describe('Path to the bill/receipt screenshot on this Mac. Downscaled before it is stored.'),
	bill_image_base64: z.string().optional().describe('The bill image inline, if you have no file path.')
};

async function main() {
	const server = new McpServer({ name: 'meos-stuff', version: '1.0.0' });

	server.registerTool(
		'get_spending',
		{
			description:
				'Spending overview: what is owned, total spent, monthly ownership burn vs salary, and per-category totals. Start here.'
		},
		async () => {
			try {
				return json(await store.summary());
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'list_categories',
		{ description: 'The Stuff shelves (gadgets, clothes, …) with each one’s default payback months.' },
		async () => {
			try {
				return json(await store.categories());
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'list_purchases',
		{
			description:
				'List logged purchases, newest first, each with its ROI progress and true cost per day. Filter by text or category.',
			inputSchema: {
				query: z.string().optional().describe('Match against name, note or link.'),
				category: z.string().optional().describe('Category id or name, e.g. "gadgets".'),
				limit: z.number().int().positive().max(200).optional(),
				include_retired: z.boolean().optional()
			}
		},
		async ({ query, category, limit, include_retired }) => {
			try {
				return json(await store.list(query ?? '', category ?? '', limit ?? 50, include_retired ?? false));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'add_purchase',
		{
			description:
				'Log something bought, from a receipt. Give it the product link, title, category, purchase date, price and a bill screenshot; ' +
				`anything missing is inferred — the category from the product name, the date from today, and the payback window from ${DEFAULT_ROI_MONTHS} months. ` +
				'Prices and dates may be passed exactly as they appear on the receipt ("₹2,499.00", "19 August 2026").',
			inputSchema: {
				name: z.string().describe('Product title, short. "CMF Buds Pro 2", not the full Amazon listing.'),
				link: z.string().optional().describe('Product page URL. Amazon links are reduced to /dp/<ASIN>.'),
				category: z.string().optional().describe('Category id or name. Guessed from the product name if omitted.'),
				price: z.union([z.string(), z.number()]).optional().describe('Price in rupees, as written on the bill.'),
				bought_on: z.string().optional().describe('Purchase date. Numeric dates are read day-first. Defaults to today.'),
				roi_months: z
					.number()
					.int()
					.positive()
					.max(600)
					.optional()
					.describe(`Months to pay for itself. Defaults to ${DEFAULT_ROI_MONTHS}.`),
				note: z.string().optional(),
				...Bill
			}
		},
		async (a) => {
			try {
				const bought = parseDate(a.bought_on) ?? todayIso();
				const price = parseInr(a.price ?? null);
				const item = await store.add({
					name: a.name,
					link: canonicalLink(a.link ?? ''),
					category: a.category ?? '',
					price_inr: price ?? 0,
					bought_on: bought,
					roi_months: a.roi_months ?? DEFAULT_ROI_MONTHS,
					note: a.note ?? '',
					bill_image_base64: readBill(a.bill_image_path, a.bill_image_base64)
				});
				// Say what was guessed, so the caller can correct it in one follow-up
				// instead of silently logging a wrong price or date.
				const inferred: string[] = [];
				if (!a.category) inferred.push('category');
				if (price === null) inferred.push('price (recorded as ₹0)');
				if (!parseDate(a.bought_on)) inferred.push('bought_on (today)');
				if (!a.roi_months) inferred.push(`roi_months (${DEFAULT_ROI_MONTHS})`);
				return json({ ...item, inferred });
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'update_purchase',
		{
			description:
				'Change a logged purchase. Only the fields you pass are touched. Use list_purchases to get the id.',
			inputSchema: {
				id: z.string(),
				name: z.string().optional(),
				link: z.string().optional(),
				category: z.string().optional(),
				price: z.union([z.string(), z.number()]).optional(),
				bought_on: z.string().optional(),
				roi_months: z.number().int().positive().max(600).optional(),
				note: z.string().optional(),
				retired: z.boolean().optional().describe('Mark as no longer owned; it drops out of the burn.'),
				...Bill
			}
		},
		async (a) => {
			try {
				const price = a.price === undefined ? undefined : parseInr(a.price);
				const patch: Record<string, unknown> = { id: a.id };
				if (a.name !== undefined) patch.name = a.name;
				if (a.link !== undefined) patch.link = canonicalLink(a.link);
				if (a.category !== undefined) patch.category = a.category;
				if (price !== undefined && price !== null) patch.price_inr = price;
				if (a.bought_on !== undefined) {
					const d = parseDate(a.bought_on);
					if (d) patch.bought_on = d;
				}
				if (a.roi_months !== undefined) patch.roi_months = a.roi_months;
				if (a.note !== undefined) patch.note = a.note;
				if (a.retired !== undefined) patch.retired = a.retired;
				const bill = readBill(a.bill_image_path, a.bill_image_base64);
				if (bill) patch.bill_image_base64 = bill;
				return json(await store.update(patch));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'delete_purchase',
		{
			description: 'Remove a logged purchase for good. Prefer update_purchase with retired=true for things you simply no longer own.',
			inputSchema: { id: z.string() }
		},
		async ({ id }) => {
			try {
				return json(await store.remove(id));
			} catch (e) {
				return fail(e);
			}
		}
	);

	const transport = new StdioServerTransport();
	await server.connect(transport);
	try {
		await store.health();
		console.error('[meos-stuff] ready (mac-local)');
	} catch {
		console.error('[meos-stuff] ready — native MeOS is closed, tools will error until it is open');
	}
}

main().catch((err) => {
	console.error(`[meos-stuff] ${err instanceof Error ? err.message : err}`);
	process.exit(1);
});
