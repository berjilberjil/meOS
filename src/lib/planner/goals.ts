import { SupabaseRepository } from '$lib/data/repository';
import type { LifeGoal, GoalStatus } from './types';

export const goalsRepo = new SupabaseRepository<LifeGoal>('goals');

export async function addGoal(title: string, description: string | null, targetDate: string | null): Promise<LifeGoal> {
	return goalsRepo.create({ title, description, target_date: targetDate, status: 'active' } as Partial<LifeGoal>);
}

export async function setGoalStatus(id: string, status: GoalStatus): Promise<LifeGoal> {
	return goalsRepo.update(id, { status } as Partial<LifeGoal>);
}
