import { describe, it, expect } from 'vitest';
import {
	todoChipAttrs,
	goalChipAttrs,
	reconcileTodoChip,
	reconcileGoalChip,
	chipTitle
} from '$lib/notes/editor/planner-chip';
import type { Todo, LifeGoal } from '$lib/planner/types';

const todo: Todo = {
	id: 't1',
	user_id: 'u1',
	title: 'Call plumber',
	notes: null,
	done: false,
	due_on: '2026-07-15',
	priority: 3,
	created_at: '2026-07-12T00:00:00Z',
	updated_at: '2026-07-12T00:00:00Z'
};

const goal: LifeGoal = {
	id: 'g1',
	user_id: 'u1',
	title: 'Run a marathon',
	description: null,
	status: 'active',
	target_date: '2026-12-31',
	created_at: '2026-07-12T00:00:00Z',
	updated_at: '2026-07-12T00:00:00Z'
};

describe('todoChipAttrs', () => {
	it('snapshots a todo into chip attrs, not removed', () => {
		expect(todoChipAttrs(todo)).toEqual({
			todoId: 't1',
			title: 'Call plumber',
			done: false,
			due: '2026-07-15',
			priority: 3,
			removed: false
		});
	});
});

describe('goalChipAttrs', () => {
	it('snapshots a goal into chip attrs, not removed', () => {
		expect(goalChipAttrs(goal)).toEqual({
			goalId: 'g1',
			title: 'Run a marathon',
			status: 'active',
			targetDate: '2026-12-31',
			removed: false
		});
	});
});

describe('reconcileTodoChip', () => {
	it('prefers the live entity (title + done reflect DB) and keeps the id', () => {
		const stale = todoChipAttrs(todo);
		const live: Todo = { ...todo, title: 'Call the plumber back', done: true };
		expect(reconcileTodoChip(stale, live)).toEqual({
			todoId: 't1',
			title: 'Call the plumber back',
			done: true,
			due: '2026-07-15',
			priority: 3,
			removed: false
		});
	});

	it('marks removed when the entity is gone, keeping the last snapshot', () => {
		const snap = todoChipAttrs(todo);
		expect(reconcileTodoChip(snap, null)).toEqual({ ...snap, removed: true });
	});
});

describe('reconcileGoalChip', () => {
	it('prefers the live goal and keeps the id', () => {
		const stale = goalChipAttrs(goal);
		const live: LifeGoal = { ...goal, status: 'done' };
		expect(reconcileGoalChip(stale, live)).toEqual({ ...stale, status: 'done' });
	});

	it('marks removed when the goal is gone', () => {
		const snap = goalChipAttrs(goal);
		expect(reconcileGoalChip(snap, null)).toEqual({ ...snap, removed: true });
	});
});

describe('chipTitle', () => {
	it('returns the trimmed title', () => {
		expect(chipTitle({ ...todoChipAttrs(todo), title: '  Call plumber  ' })).toBe('Call plumber');
	});

	it('falls back to "Untitled task" for an empty todo title', () => {
		expect(chipTitle({ ...todoChipAttrs(todo), title: '   ' })).toBe('Untitled task');
	});

	it('falls back to "Untitled goal" for an empty goal title', () => {
		expect(chipTitle({ ...goalChipAttrs(goal), title: '' })).toBe('Untitled goal');
	});
});
