// Pure Today-tab logic. Dates are YYYY-MM-DD; no Date.now so tests stay deterministic.

export type Greeting = 'Good morning' | 'Good afternoon' | 'Good evening';

export function greetingForHour(hour: number): Greeting {
	if (hour < 12) return 'Good morning';
	if (hour < 17) return 'Good afternoon';
	return 'Good evening';
}

export function addDays(iso: string, n: number): string {
	const [y, m, d] = iso.split('-').map(Number);
	const dt = new Date(Date.UTC(y, m - 1, d));
	dt.setUTCDate(dt.getUTCDate() + n);
	return dt.toISOString().slice(0, 10);
}

export function formatTodayHeading(iso: string): { weekday: string; dateLabel: string } {
	const [y, m, d] = iso.split('-').map(Number);
	const date = new Date(y, m - 1, d);
	return {
		weekday: date.toLocaleDateString('en-US', { weekday: 'long' }),
		dateLabel: date.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })
	};
}

export interface DoNowTodo {
	id: string;
	title: string;
	due_on: string | null;
	done: boolean;
	priority: number;
}

export interface DoNowInput {
	today: string;
	journalDone: boolean;
	workoutPlanned: string | null;
	workoutDone: boolean;
	todos: DoNowTodo[];
}

export interface DoNow {
	title: string;
	why: string;
	href: string;
}

export function pickDoNow(input: DoNowInput): DoNow {
	const open = input.todos.filter((t) => !t.done);
	const overdue = open.filter((t) => t.due_on && t.due_on < input.today);
	overdue.sort((a, b) => b.priority - a.priority || (a.due_on ?? '').localeCompare(b.due_on ?? ''));
	if (overdue[0]) {
		return { title: overdue[0].title, why: 'Overdue — close this first.', href: '/todos' };
	}

	if (!input.journalDone) {
		return {
			title: "Write today's journal",
			why: 'Keep the streak. Two sentences is enough.',
			href: '/journal/new'
		};
	}

	const dueToday = open
		.filter((t) => t.due_on === input.today)
		.sort((a, b) => b.priority - a.priority);
	if (dueToday[0]) {
		return { title: dueToday[0].title, why: 'Due today.', href: '/todos' };
	}

	if (input.workoutPlanned && !input.workoutDone) {
		return {
			title: input.workoutPlanned,
			why: 'On the plan for today.',
			href: '/fitness/workouts'
		};
	}

	return {
		title: "You're clear",
		why: 'Nothing urgent. Protect the streak or take a walk.',
		href: '/journal'
	};
}

export interface ComingTodo {
	id: string;
	title: string;
	due_on: string | null;
	done: boolean;
	priority: number;
}

export interface ComingBill {
	id: string;
	name: string;
	next_run_on: string;
}

export interface ComingGoal {
	id: string;
	title: string;
	target_date: string | null;
	status: string;
}

export interface ComingItem {
	id: string;
	kind: 'todo' | 'bill' | 'workout' | 'goal';
	title: string;
	when: string;
	href: string;
}

export function comingUp(input: {
	today: string;
	horizonDays: number;
	todos: ComingTodo[];
	bills: ComingBill[];
	workoutToday: string | null;
	goals: ComingGoal[];
}): ComingItem[] {
	const end = addDays(input.today, input.horizonDays);
	const items: ComingItem[] = [];

	if (input.workoutToday) {
		items.push({
			id: 'workout-today',
			kind: 'workout',
			title: input.workoutToday,
			when: input.today,
			href: '/fitness/workouts'
		});
	}

	for (const t of input.todos) {
		if (t.done || !t.due_on) continue;
		if (t.due_on < input.today) continue; // overdue lives in Do now
		if (t.due_on > end) continue;
		items.push({ id: t.id, kind: 'todo', title: t.title, when: t.due_on, href: '/todos' });
	}

	for (const b of input.bills) {
		if (b.next_run_on < input.today || b.next_run_on > end) continue;
		items.push({
			id: b.id,
			kind: 'bill',
			title: b.name,
			when: b.next_run_on,
			href: '/finance/recurring'
		});
	}

	for (const g of input.goals) {
		if (g.status !== 'active' || !g.target_date) continue;
		if (g.target_date < input.today || g.target_date > end) continue;
		items.push({ id: g.id, kind: 'goal', title: g.title, when: g.target_date, href: '/goals' });
	}

	items.sort((a, b) => a.when.localeCompare(b.when) || a.title.localeCompare(b.title));
	return items;
}

export interface ProductivityInput {
	journalDone: boolean;
	todosDone: number;
	todosToday: number;
	workoutDone: boolean;
	foodLogged: boolean;
}

export interface ProductivityRing {
	key: 'journal' | 'tasks' | 'move' | 'fuel';
	label: string;
	value: number;
	detail: string;
}

export function productivity(input: ProductivityInput): { score: number; rings: ProductivityRing[] } {
	const taskValue = input.todosToday <= 0 ? 1 : input.todosDone / input.todosToday;
	const rings: ProductivityRing[] = [
		{
			key: 'journal',
			label: 'Journal',
			value: input.journalDone ? 1 : 0,
			detail: input.journalDone ? 'Written' : 'Not yet'
		},
		{
			key: 'tasks',
			label: 'Tasks',
			value: taskValue,
			detail: input.todosToday <= 0 ? 'Clear' : `${input.todosDone}/${input.todosToday}`
		},
		{
			key: 'move',
			label: 'Move',
			value: input.workoutDone ? 1 : 0,
			detail: input.workoutDone ? 'Trained' : 'Rest'
		},
		{
			key: 'fuel',
			label: 'Fuel',
			value: input.foodLogged ? 1 : 0,
			detail: input.foodLogged ? 'Logged' : 'Empty'
		}
	];
	const score = Math.round((rings.reduce((s, r) => s + r.value, 0) / rings.length) * 100);
	return { score, rings };
}

export function whenLabel(iso: string, today: string): string {
	if (iso === today) return 'Today';
	if (iso === addDays(today, 1)) return 'Tomorrow';
	const [y, m, d] = iso.split('-').map(Number);
	return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
}
