export type Priority = 0 | 1 | 2 | 3; // none, low, medium, high
export const PRIORITY_LABELS: Record<Priority, string> = { 0: '—', 1: 'low', 2: 'med', 3: 'high' };

export interface Todo {
	id: string;
	user_id: string;
	title: string;
	notes: string | null;
	done: boolean;
	due_on: string | null;
	priority: Priority;
	created_at: string;
	updated_at: string;
}

export type GoalStatus = 'active' | 'done' | 'archived';

export interface LifeGoal {
	id: string;
	user_id: string;
	title: string;
	description: string | null;
	status: GoalStatus;
	target_date: string | null;
	created_at: string;
	updated_at: string;
}

export type TodoBucket = 'overdue' | 'today' | 'upcoming' | 'someday' | 'done';
