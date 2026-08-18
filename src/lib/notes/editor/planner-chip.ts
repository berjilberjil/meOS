// Pure helpers backing the inline To-do / Goal chips embedded in notes & journal.
// A chip stores a denormalized snapshot of its entity so the note renders offline
// and survives the entity being deleted; the NodeView reconciles against the live
// entity (from the query cache) on load.
import type { Todo, LifeGoal, Priority, GoalStatus } from '$lib/planner/types';

export interface TodoChipAttrs {
	todoId: string;
	title: string;
	done: boolean;
	due: string | null;
	priority: Priority;
	removed: boolean;
}

export interface GoalChipAttrs {
	goalId: string;
	title: string;
	status: GoalStatus;
	targetDate: string | null;
	removed: boolean;
}

export function todoChipAttrs(todo: Todo): TodoChipAttrs {
	return {
		todoId: todo.id,
		title: todo.title,
		done: todo.done,
		due: todo.due_on,
		priority: todo.priority,
		removed: false
	};
}

export function goalChipAttrs(goal: LifeGoal): GoalChipAttrs {
	return {
		goalId: goal.id,
		title: goal.title,
		status: goal.status,
		targetDate: goal.target_date,
		removed: false
	};
}

// Live entity wins (title/done/priority reflect the DB); null = entity deleted,
// so keep the last snapshot but flag it removed.
export function reconcileTodoChip(attrs: TodoChipAttrs, live: Todo | null): TodoChipAttrs {
	return live ? todoChipAttrs(live) : { ...attrs, removed: true };
}

export function reconcileGoalChip(attrs: GoalChipAttrs, live: LifeGoal | null): GoalChipAttrs {
	return live ? goalChipAttrs(live) : { ...attrs, removed: true };
}

export function chipTitle(attrs: TodoChipAttrs | GoalChipAttrs): string {
	const t = attrs.title.trim();
	if (t) return t;
	return 'goalId' in attrs ? 'Untitled goal' : 'Untitled task';
}
