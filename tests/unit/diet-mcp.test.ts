import { describe, it, expect } from 'vitest';
import { DIET_MCP_TOOLS } from '$lib/diet/mcp-catalog';

const NAMES = DIET_MCP_TOOLS.map((t) => t.name);

describe('diet MCP tool catalog', () => {
	it('exposes the read + write surface the coach needs', () => {
		expect(NAMES.sort()).toEqual(
			[
				'add_slot_food',
				'clear_slot',
				'delete_log',
				'get_context',
				'get_day_log',
				'get_week_plan',
				'list_recent_foods',
				'log_food',
				'log_planned_meal',
				'remove_slot_food',
				'search_foods',
				'set_goals',
				'set_slot',
				'upsert_food'
			].sort()
		);
	});

	it('does not expose delete-food or delete-week', () => {
		expect(NAMES).not.toContain('delete_food');
		expect(NAMES).not.toContain('delete_week');
		expect(NAMES).not.toContain('remove_week');
	});

	it('describes every tool so a client can pick without guessing', () => {
		for (const t of DIET_MCP_TOOLS) {
			expect(t.name.length).toBeGreaterThan(0);
			expect(t.description.length).toBeGreaterThan(20);
		}
	});

	it('marks write tools so clients can separate reads from mutations', () => {
		const writes = DIET_MCP_TOOLS.filter((t) => t.mutates).map((t) => t.name);
		expect(writes).toEqual(
			expect.arrayContaining([
				'set_goals',
				'upsert_food',
				'set_slot',
				'add_slot_food',
				'remove_slot_food',
				'clear_slot',
				'log_food',
				'log_planned_meal',
				'delete_log'
			])
		);
		expect(DIET_MCP_TOOLS.find((t) => t.name === 'get_context')?.mutates).toBe(false);
	});
});
