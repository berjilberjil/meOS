#!/usr/bin/env bun
/**
 * MyOS diet MCP — stdio. Sign in as the owner (RLS on). Never log secrets.
 * Clients: grok mcp add / claude mcp add / any stdio MCP host via .mcp.json
 */
import { createClient } from '@supabase/supabase-js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { createDietStore } from '../../src/lib/diet/store';
import { DIET_MCP_TOOLS } from '../../src/lib/diet/mcp-catalog';

function required(name: string, ...alts: string[]): string {
	for (const key of [name, ...alts]) {
		const v = process.env[key]?.trim();
		if (v) return v;
	}
	throw new Error(`Missing ${name}${alts.length ? ` (or ${alts.join(', ')})` : ''}`);
}

function json(data: unknown) {
	return { content: [{ type: 'text' as const, text: JSON.stringify(data, null, 2) }] };
}

function fail(err: unknown) {
	const message =
		err instanceof Error
			? err.message
			: typeof err === 'object' && err && 'message' in err
				? String((err as { message: unknown }).message)
				: JSON.stringify(err);
	console.error(`[myos-diet] ${message}`);
	return { content: [{ type: 'text' as const, text: `Error: ${message}` }], isError: true as const };
}

const Meal = z.enum(['breakfast', 'lunch', 'dinner', 'snack']);
const Weekday = z.number().int().min(0).max(6).describe('0=Mon … 6=Sun');
const SlotFood = z.object({
	food_id: z.string().uuid(),
	quantity: z.number().positive()
});

async function main() {
	const url = required('PUBLIC_SUPABASE_URL', 'SUPABASE_URL');
	const anon = required('PUBLIC_SUPABASE_ANON_KEY', 'SUPABASE_ANON_KEY');
	const email = required('MYOS_OWNER_EMAIL');
	const password = required('MYOS_OWNER_PASSWORD');

	const client = createClient(url, anon, {
		auth: { persistSession: false, autoRefreshToken: false }
	});
	const { error: authErr } = await client.auth.signInWithPassword({ email, password });
	if (authErr) throw new Error(`MyOS login failed: ${authErr.message}`);

	const store = createDietStore(client as never);
	const desc = Object.fromEntries(DIET_MCP_TOOLS.map((t) => [t.name, t.description]));

	const server = new McpServer({
		name: 'myos-diet',
		version: '0.1.0'
	});

	const wrap = <T>(fn: () => Promise<T>) => async () => {
		try {
			return json(await fn());
		} catch (err) {
			return fail(err);
		}
	};

	server.registerTool('get_context', { description: desc.get_context }, wrap(() => store.getContext()));

	server.registerTool(
		'get_week_plan',
		{
			description: desc.get_week_plan,
			inputSchema: {
				week_start: z.string().optional().describe('Monday YYYY-MM-DD'),
				date: z.string().optional().describe('Any date in the week, YYYY-MM-DD')
			}
		},
		async ({ week_start, date }) => {
			try {
				return json(await store.getWeekPlan(week_start ?? date));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'get_day_log',
		{
			description: desc.get_day_log,
			inputSchema: { date: z.string().describe('YYYY-MM-DD') }
		},
		async ({ date }) => {
			try {
				return json(await store.getDayLog(date));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'search_foods',
		{
			description: desc.search_foods,
			inputSchema: {
				query: z.string().describe('Name substring, e.g. chapati or whey'),
				limit: z.number().int().positive().max(40).optional()
			}
		},
		async ({ query, limit }) => {
			try {
				return json(await store.searchFoods(query, limit ?? 12));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'list_recent_foods',
		{
			description: desc.list_recent_foods,
			inputSchema: { limit: z.number().int().positive().max(30).optional() }
		},
		async ({ limit }) => {
			try {
				return json(await store.listRecentFoods(limit ?? 10));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'set_goals',
		{
			description: desc.set_goals,
			inputSchema: {
				energy_kcal: z.number().int().nullable().optional(),
				protein_g: z.number().nullable().optional(),
				carb_g: z.number().nullable().optional(),
				fat_g: z.number().nullable().optional(),
				fiber_g: z.number().nullable().optional()
			}
		},
		async (args) => {
			try {
				return json(await store.setGoals(args));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'upsert_food',
		{
			description: desc.upsert_food,
			inputSchema: {
				name: z.string(),
				category: z.string().optional(),
				serving_label: z.string().optional(),
				serving_grams: z.number().int().positive().optional(),
				energy_kcal: z.number(),
				protein_g: z.number().optional(),
				carb_g: z.number().optional(),
				fat_g: z.number().optional(),
				fiber_g: z.number().optional()
			}
		},
		async (args) => {
			try {
				return json(await store.upsertFood(args));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'set_slot',
		{
			description: desc.set_slot,
			inputSchema: {
				week_start: z.string().optional(),
				date: z.string().optional(),
				weekday: Weekday,
				meal: Meal,
				foods: z.array(SlotFood)
			}
		},
		async (args) => {
			try {
				return json(await store.setSlot(args));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'add_slot_food',
		{
			description: desc.add_slot_food,
			inputSchema: {
				week_start: z.string().optional(),
				date: z.string().optional(),
				weekday: Weekday,
				meal: Meal,
				food_id: z.string().uuid(),
				quantity: z.number().positive()
			}
		},
		async (args) => {
			try {
				return json(await store.addSlotFood(args));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'remove_slot_food',
		{
			description: desc.remove_slot_food,
			inputSchema: { slot_id: z.string().uuid() }
		},
		async ({ slot_id }) => {
			try {
				await store.removeSlotFood(slot_id);
				return json({ ok: true, id: slot_id });
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'clear_slot',
		{
			description: desc.clear_slot,
			inputSchema: {
				week_start: z.string().optional(),
				date: z.string().optional(),
				weekday: Weekday,
				meal: Meal
			}
		},
		async (args) => {
			try {
				await store.clearSlot(args);
				return json({ ok: true });
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'log_food',
		{
			description: desc.log_food,
			inputSchema: {
				food_id: z.string().uuid(),
				quantity: z.number().positive(),
				logged_on: z.string().optional(),
				meal: Meal
			}
		},
		async (args) => {
			try {
				return json(await store.logFood(args));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'log_planned_meal',
		{
			description: desc.log_planned_meal,
			inputSchema: {
				week_start: z.string().optional(),
				date: z.string().optional(),
				weekday: Weekday.optional(),
				meal: Meal
			}
		},
		async (args) => {
			try {
				return json(await store.logPlannedMeal(args));
			} catch (err) {
				return fail(err);
			}
		}
	);

	server.registerTool(
		'delete_log',
		{
			description: desc.delete_log,
			inputSchema: { log_id: z.string().uuid() }
		},
		async ({ log_id }) => {
			try {
				await store.deleteLog(log_id);
				return json({ ok: true, id: log_id });
			} catch (err) {
				return fail(err);
			}
		}
	);

	const transport = new StdioServerTransport();
	await server.connect(transport);
	console.error('[myos-diet] ready (stdio)');
}

main().catch((err) => {
	console.error(`[myos-diet] ${err instanceof Error ? err.message : err}`);
	process.exit(1);
});
