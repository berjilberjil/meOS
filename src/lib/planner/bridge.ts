// Bridges the TipTap editor to the planner repos + query cache. Injected into the
// editor as `editor.storage.planner` so the inline To-do / Goal chips can create,
// toggle, and read real entities and keep the Dashboard in sync (via invalidation).
import type { QueryClient } from '@tanstack/svelte-query';
import { todosRepo, addTodo } from './todos';
import { goalsRepo, addGoal, setGoalStatus as setStatus } from './goals';
import type { Todo, LifeGoal, GoalStatus } from './types';

export interface PlannerBridge {
	createTodo(title: string): Promise<Todo>;
	toggleTodo(id: string, done: boolean): Promise<Todo>;
	updateTodo(id: string, patch: Partial<Todo>): Promise<Todo>;
	getTodo(id: string): Todo | null;
	createGoal(title: string): Promise<LifeGoal>;
	setGoalStatus(id: string, status: GoalStatus): Promise<LifeGoal>;
	updateGoal(id: string, patch: Partial<LifeGoal>): Promise<LifeGoal>;
	getGoal(id: string): LifeGoal | null;
}

export function createPlannerBridge(qc: QueryClient): PlannerBridge {
	const invTodos = () => qc.invalidateQueries({ queryKey: ['todos'] });
	const invGoals = () => qc.invalidateQueries({ queryKey: ['goals'] });
	return {
		async createTodo(title) {
			const t = await addTodo(title.trim() || 'Untitled task', null, 0);
			await invTodos();
			return t;
		},
		async toggleTodo(id, done) {
			const t = await todosRepo.update(id, { done } as Partial<Todo>);
			await invTodos();
			return t;
		},
		async updateTodo(id, patch) {
			const t = await todosRepo.update(id, patch);
			await invTodos();
			return t;
		},
		getTodo(id) {
			return qc.getQueryData<Todo[]>(['todos'])?.find((t) => t.id === id) ?? null;
		},
		async createGoal(title) {
			const g = await addGoal(title.trim() || 'Untitled goal', null, null);
			await invGoals();
			return g;
		},
		async setGoalStatus(id, status) {
			const g = await setStatus(id, status);
			await invGoals();
			return g;
		},
		async updateGoal(id, patch) {
			const g = await goalsRepo.update(id, patch);
			await invGoals();
			return g;
		},
		getGoal(id) {
			return qc.getQueryData<LifeGoal[]>(['goals'])?.find((g) => g.id === id) ?? null;
		}
	};
}
