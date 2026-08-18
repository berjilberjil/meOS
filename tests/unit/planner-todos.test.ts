import { describe, it, expect } from 'vitest';
import { todoBucket, compareTodos } from '$lib/planner/todos';
import type { Todo } from '$lib/planner/types';

function todo(p: Partial<Todo>): Todo {
	return {
		id: 't', user_id: 'u', title: 'x', notes: null, done: false, due_on: null,
		priority: 0, created_at: '2026-06-01T00:00:00Z', updated_at: '', ...p
	};
}

describe('todoBucket', () => {
	const today = '2026-06-26';
	it('done overrides everything', () => {
		expect(todoBucket('2026-01-01', true, today)).toBe('done');
	});
	it('classifies by due date', () => {
		expect(todoBucket(null, false, today)).toBe('someday');
		expect(todoBucket('2026-06-25', false, today)).toBe('overdue');
		expect(todoBucket('2026-06-26', false, today)).toBe('today');
		expect(todoBucket('2026-06-27', false, today)).toBe('upcoming');
	});
});

describe('compareTodos', () => {
	it('higher priority first', () => {
		expect(compareTodos(todo({ priority: 3 }), todo({ priority: 1 }))).toBeLessThan(0);
	});
	it('same priority: soonest due first, undated last', () => {
		expect(compareTodos(todo({ due_on: '2026-06-10' }), todo({ due_on: '2026-06-20' }))).toBeLessThan(0);
		expect(compareTodos(todo({ due_on: '2026-06-10' }), todo({ due_on: null }))).toBeLessThan(0);
		expect(compareTodos(todo({ due_on: null }), todo({ due_on: '2026-06-10' }))).toBeGreaterThan(0);
	});
});
