import { SupabaseRepository } from '$lib/data/repository';
import { todayIso } from '$lib/finance/dates';
import type { Todo, TodoBucket, Priority } from './types';

export const todosRepo = new SupabaseRepository<Todo>('todos');

// Pure: classify a todo into a time bucket.
export function todoBucket(dueOn: string | null, done: boolean, today: string): TodoBucket {
	if (done) return 'done';
	if (!dueOn) return 'someday';
	if (dueOn < today) return 'overdue';
	if (dueOn === today) return 'today';
	return 'upcoming';
}

// Pure: sort by priority (high first), then due date (soonest first, undated last).
export function compareTodos(a: Todo, b: Todo): number {
	if (a.priority !== b.priority) return b.priority - a.priority;
	if (a.due_on && b.due_on) return a.due_on.localeCompare(b.due_on);
	if (a.due_on) return -1;
	if (b.due_on) return 1;
	return a.created_at.localeCompare(b.created_at);
}

export async function listTodos(): Promise<Todo[]> {
	const todos = await todosRepo.list();
	return todos.sort(compareTodos);
}

export async function addTodo(title: string, dueOn: string | null, priority: Priority): Promise<Todo> {
	return todosRepo.create({ title, due_on: dueOn, priority, done: false } as Partial<Todo>);
}

export async function toggleTodo(t: Todo): Promise<Todo> {
	return todosRepo.update(t.id, { done: !t.done } as Partial<Todo>);
}

export { todayIso };
