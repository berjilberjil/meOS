import { describe, it, expect } from 'vitest';
import {
	greetingForHour,
	formatTodayHeading,
	addDays,
	pickDoNow,
	comingUp,
	productivity
} from '$lib/today/today';

describe('greetingForHour', () => {
	it('is morning before noon, afternoon until 17, evening after', () => {
		expect(greetingForHour(0)).toBe('Good morning');
		expect(greetingForHour(11)).toBe('Good morning');
		expect(greetingForHour(12)).toBe('Good afternoon');
		expect(greetingForHour(16)).toBe('Good afternoon');
		expect(greetingForHour(17)).toBe('Good evening');
		expect(greetingForHour(23)).toBe('Good evening');
	});
});

describe('formatTodayHeading', () => {
	it('splits weekday and long date from an ISO day', () => {
		const h = formatTodayHeading('2026-08-15');
		expect(h.weekday).toBe('Saturday');
		expect(h.dateLabel).toBe('15 August 2026');
	});
});

describe('addDays', () => {
	it('shifts a YYYY-MM-DD without UTC off-by-one', () => {
		expect(addDays('2026-08-15', 1)).toBe('2026-08-16');
		expect(addDays('2026-08-31', 1)).toBe('2026-09-01');
		expect(addDays('2026-08-15', -2)).toBe('2026-08-13');
	});
});

describe('pickDoNow', () => {
	const today = '2026-08-15';

	it('picks an overdue high-priority todo first', () => {
		const action = pickDoNow({
			today,
			journalDone: false,
			workoutPlanned: 'Pull day',
			workoutDone: false,
			todos: [
				{ id: 'a', title: 'Write essay', due_on: today, done: false, priority: 1 },
				{ id: 'b', title: 'Pay rent', due_on: '2026-08-10', done: false, priority: 3 }
			]
		});
		expect(action.title).toBe('Pay rent');
		expect(action.href).toBe('/todos');
	});

	it('falls through to journal when nothing is overdue', () => {
		const action = pickDoNow({
			today,
			journalDone: false,
			workoutPlanned: null,
			workoutDone: false,
			todos: [{ id: 'a', title: 'Later', due_on: '2026-08-20', done: false, priority: 3 }]
		});
		expect(action.href).toMatch(/^\/journal/);
		expect(action.title.toLowerCase()).toMatch(/journal/);
	});

	it('suggests the planned workout when the journal is done and no todos are due', () => {
		const action = pickDoNow({
			today,
			journalDone: true,
			workoutPlanned: 'Pull day',
			workoutDone: false,
			todos: []
		});
		expect(action.title).toBe('Pull day');
		expect(action.href).toBe('/fitness/workouts');
	});

	it('returns a clear-runway action when nothing is pending', () => {
		const action = pickDoNow({
			today,
			journalDone: true,
			workoutPlanned: null,
			workoutDone: true,
			todos: [{ id: 'a', title: 'Done', due_on: today, done: true, priority: 3 }]
		});
		expect(action.href).toBe('/journal');
		expect(action.why.length).toBeGreaterThan(0);
	});
});

describe('comingUp', () => {
	const today = '2026-08-15';

	it('merges todos, bills, today\'s workout and near goals, soonest first', () => {
		const items = comingUp({
			today,
			horizonDays: 7,
			todos: [
				{ id: 't1', title: 'Call dentist', due_on: '2026-08-18', done: false, priority: 1 },
				{ id: 't2', title: 'Old', due_on: '2026-07-01', done: false, priority: 2 },
				{ id: 't3', title: 'Done', due_on: today, done: true, priority: 3 },
				{ id: 't4', title: 'Far', due_on: '2026-09-01', done: false, priority: 1 }
			],
			bills: [
				{ id: 'r1', name: 'Rent', next_run_on: '2026-08-16' },
				{ id: 'r2', name: 'Netflix', next_run_on: '2026-09-15' }
			],
			workoutToday: 'Pull day',
			goals: [
				{ id: 'g1', title: 'Run 10k', target_date: '2026-08-20', status: 'active' },
				{ id: 'g2', title: 'Archived', target_date: '2026-08-17', status: 'archived' }
			]
		});
		expect(items.map((i) => i.title)).toEqual(['Pull day', 'Rent', 'Call dentist', 'Run 10k']);
		expect(items[0].kind).toBe('workout');
		expect(items[1].kind).toBe('bill');
		expect(items[0].when).toBe(today);
	});

	it('omits overdue todos (those belong in Do now) and done items', () => {
		const items = comingUp({
			today,
			horizonDays: 7,
			todos: [{ id: 't', title: 'Late', due_on: '2026-08-01', done: false, priority: 3 }],
			bills: [],
			workoutToday: null,
			goals: []
		});
		expect(items).toEqual([]);
	});
});

describe('productivity', () => {
	it('scores the four rings like a daily close', () => {
		const p = productivity({
			journalDone: true,
			todosDone: 2,
			todosToday: 4,
			workoutDone: false,
			foodLogged: true
		});
		expect(p.score).toBe(63);
		expect(p.rings).toHaveLength(4);
		expect(p.rings[0]).toMatchObject({ key: 'journal', value: 1 });
		expect(p.rings[1]).toMatchObject({ key: 'tasks', value: 0.5 });
		expect(p.rings[2]).toMatchObject({ key: 'move', value: 0 });
		expect(p.rings[3]).toMatchObject({ key: 'fuel', value: 1 });
	});

	it('treats a day with no todos as tasks-complete', () => {
		const p = productivity({
			journalDone: false,
			todosDone: 0,
			todosToday: 0,
			workoutDone: false,
			foodLogged: false
		});
		expect(p.rings.find((r) => r.key === 'tasks')?.value).toBe(1);
		expect(p.score).toBe(25);
	});
});
