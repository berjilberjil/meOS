#!/usr/bin/env bun
/**
 * Native MeOS diet MCP. Talks to the unlocked Mac app on 127.0.0.1:17881
 * (same encrypted store Mac + iPhone already sync). Falls back to the
 * production API + vault passphrase if the Mac app is closed.
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { createStore } from './store';

function json(data: unknown) {
	return { content: [{ type: 'text' as const, text: JSON.stringify(data, null, 2) }] };
}
function fail(err: unknown) {
	const message = err instanceof Error ? err.message : JSON.stringify(err);
	console.error(`[meos-diet] ${message}`);
	return { content: [{ type: 'text' as const, text: `Error: ${message}` }], isError: true as const };
}

const Meal = z.enum(['breakfast', 'lunch', 'dinner', 'snack', 'snacks']);
const Weekday = z.number().int().min(0).max(6).describe('0=Sun … 6=Sat (native MeOS)');
const SlotFood = z.object({
	food_id: z.string().describe('seed-food-N or a custom food id'),
	quantity: z.number().positive()
});

async function main() {
	const store = await createStore();
	const server = new McpServer({ name: 'meos-diet', version: '1.0.0' });

	server.registerTool('get_context', { description: 'Native profile, goals, today totals vs plan. Start here.' }, async () => {
		try {
			return json(await store.getContext());
		} catch (e) {
			return fail(e);
		}
	});

	server.registerTool(
		'get_week_plan',
		{
			description: 'Read Sun–Sat meal plan from native MeOS (syncs to iPhone). weekday 0=Sun.',
			inputSchema: { week_start: z.string().optional(), date: z.string().optional() }
		},
		async () => {
			try {
				return json(await store.getWeekPlan());
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'get_day_log',
		{
			description: 'Logged meals for one YYYY-MM-DD.',
			inputSchema: { date: z.string() }
		},
		async ({ date }) => {
			try {
				return json(await store.getDayLog(date));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'search_foods',
		{
			description: 'Search the native seed + custom catalog. Use id in set_slot / log_food.',
			inputSchema: { query: z.string(), limit: z.number().int().positive().max(40).optional() }
		},
		async ({ query, limit }) => {
			try {
				return json(await store.searchFoods(query, limit ?? 12));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'list_recent_foods',
		{ description: 'Recently logged foods.', inputSchema: { limit: z.number().int().positive().max(30).optional() } },
		async ({ limit }) => {
			try {
				return json(await store.listRecentFoods(limit ?? 10));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'set_slot',
		{
			description: 'Replace one meal slot. weekday 0=Sun…6=Sat. meal breakfast|lunch|dinner|snacks.',
			inputSchema: {
				weekday: Weekday.optional(),
				date: z.string().optional(),
				meal: Meal,
				foods: z.array(SlotFood)
			}
		},
		async (args) => {
			try {
				return json(await store.setSlot(args));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'add_slot_food',
		{
			description: 'Append one food to a planned meal.',
			inputSchema: {
				weekday: Weekday.optional(),
				date: z.string().optional(),
				meal: Meal,
				food_id: z.string(),
				quantity: z.number().positive()
			}
		},
		async (args) => {
			try {
				return json(await store.addSlotFood(args));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'remove_slot_food',
		{ description: 'Remove one planned row by item id.', inputSchema: { slot_id: z.string() } },
		async ({ slot_id }) => {
			try {
				return json(await store.removeSlotFood(slot_id));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'clear_slot',
		{
			description: 'Clear one meal slot.',
			inputSchema: { weekday: Weekday.optional(), date: z.string().optional(), meal: Meal }
		},
		async (args) => {
			try {
				return json(await store.clearSlot(args));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool('clear_week', { description: 'Empty the whole weekly meal plan. Syncs to iPhone.' }, async () => {
		try {
			return json(await store.clearWeek());
		} catch (e) {
			return fail(e);
		}
	});

	server.registerTool(
		'log_food',
		{
			description: 'Log a food actually eaten (not the plan).',
			inputSchema: {
				food_id: z.string(),
				quantity: z.number().positive(),
				logged_on: z.string().optional(),
				meal: Meal
			}
		},
		async (args) => {
			try {
				return json(await store.logFood(args));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'log_planned_meal',
		{
			description: 'Copy a planned meal into the daily log.',
			inputSchema: { meal: Meal, date: z.string().optional(), weekday: Weekday.optional() }
		},
		async (args) => {
			try {
				return json(await store.logPlannedMeal(args));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'delete_log',
		{ description: 'Delete one log row by id.', inputSchema: { log_id: z.string() } },
		async ({ log_id }) => {
			try {
				return json(await store.deleteLog(log_id));
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'upsert_food',
		{
			description: 'Add a custom food to the native library.',
			inputSchema: {
				name: z.string(),
				category: z.string().optional(),
				serving_label: z.string().optional(),
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
			} catch (e) {
				return fail(e);
			}
		}
	);

	server.registerTool(
		'set_goals',
		{
			description: 'Update calorie / protein targets on the fitness profile.',
			inputSchema: {
				energy_kcal: z.number().nullable().optional(),
				protein_g: z.number().nullable().optional()
			}
		},
		async (args) => {
			try {
				return json(await store.setGoals(args));
			} catch (e) {
				return fail(e);
			}
		}
	);

	const transport = new StdioServerTransport();
	await server.connect(transport);
	const ping = await store.ping();
	console.error(`[meos-diet] ready native (${ping.bridge})`);
}

main().catch((err) => {
	console.error(`[meos-diet] ${err instanceof Error ? err.message : err}`);
	process.exit(1);
});
