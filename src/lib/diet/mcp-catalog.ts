export interface DietMcpTool {
	name: string;
	description: string;
	mutates: boolean;
}

export const DIET_MCP_TOOLS: DietMcpTool[] = [
	{
		name: 'get_context',
		description:
			'Read profile (weight, height, goal weight, sex, dob), nutrition goals, latest health weight, and today’s logged totals vs remaining macros. Start here before planning.',
		mutates: false
	},
	{
		name: 'get_week_plan',
		description:
			'Read the Mon–Sun diet grid for a week. Pass week_start (Monday YYYY-MM-DD) or a date inside the week. Returns each slot’s foods, quantities, and planned kcal/protein.',
		mutates: false
	},
	{
		name: 'get_day_log',
		description:
			'Read food_log_entries for one date (YYYY-MM-DD) with names and computed kcal/protein. Use to compare planned vs actually eaten.',
		mutates: false
	},
	{
		name: 'search_foods',
		description:
			'Search the shared + custom food catalog by name substring. Returns id, name, serving, kcal, protein. Use the id in set_slot / log_food.',
		mutates: false
	},
	{
		name: 'list_recent_foods',
		description: 'List the most recently logged distinct foods (default 10). Good for one-tap re-use.',
		mutates: false
	},
	{
		name: 'set_goals',
		description:
			'Create or update nutrition_goals: energy_kcal, protein_mg, carb_mg, fat_mg, fiber_mg. Pass grams for macros and they are stored as mg. Irreversible only in that it overwrites the single goals row.',
		mutates: true
	},
	{
		name: 'upsert_food',
		description:
			'Add a private custom food (name, category, serving label, grams, kcal, protein/carb/fat/fiber grams). Does not edit the shared catalog. Returns the new food id.',
		mutates: true
	},
	{
		name: 'set_slot',
		description:
			'Replace every food in one meal slot (weekday 0=Mon…6=Sun + breakfast|lunch|dinner|snack) with the given [{food_id, quantity}] list. Transactional — the previous meal is cleared then the new foods are inserted.',
		mutates: true
	},
	{
		name: 'add_slot_food',
		description: 'Append one food + quantity to an existing meal slot without clearing the rest.',
		mutates: true
	},
	{
		name: 'remove_slot_food',
		description: 'Remove one planned food row by diet_slots.id. Does not delete the food from the catalog.',
		mutates: true
	},
	{
		name: 'clear_slot',
		description: 'Remove every food from one meal slot. The week row stays.',
		mutates: true
	},
	{
		name: 'log_food',
		description:
			'Log a food the user actually ate (food_id, quantity, logged_on, meal). This writes food_log_entries, not the plan.',
		mutates: true
	},
	{
		name: 'log_planned_meal',
		description:
			'Copy every food in a planned slot into today’s (or a given date’s) food log. Use when the user ate the planned meal as-is.',
		mutates: true
	},
	{
		name: 'delete_log',
		description:
			'Delete one food_log_entries row by id. Use to undo a bad log. Does not change the weekly plan.',
		mutates: true
	}
];
