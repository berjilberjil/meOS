import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import type {
	Exercise,
	PlanDay,
	PlanExercise,
	SessionSet,
	WorkoutPlan,
	WorkoutSession
} from './types';

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export const exercisesRepo = new SupabaseRepository<Exercise>('exercises');
export const plansRepo = new SupabaseRepository<WorkoutPlan>('workout_plans');
export const planDaysRepo = new SupabaseRepository<PlanDay>('plan_days');
export const planExercisesRepo = new SupabaseRepository<PlanExercise>('plan_exercises');
export const sessionsRepo = new SupabaseRepository<WorkoutSession>('workout_sessions');
export const setsRepo = new SupabaseRepository<SessionSet>('session_sets');

// ---- exercises (shared + own via RLS) ----
export const listExercises = () => exercisesRepo.list();
export function createExercise(input: {
	name: string;
	muscle_group: string;
	equipment: string;
	unilateral?: boolean;
}): Promise<Exercise> {
	return exercisesRepo.create(input as Partial<Exercise>);
}

// ---- plans / days / planned exercises ----
export const listPlans = () => plansRepo.list();
export const createPlan = (name: string) => plansRepo.create({ name } as Partial<WorkoutPlan>);
export const removePlan = (id: string) => plansRepo.remove(id);

export const listPlanDays = () => planDaysRepo.list();
export function createPlanDay(plan_id: string, name: string, weekday: number | null): Promise<PlanDay> {
	return planDaysRepo.create({ plan_id, name, weekday } as Partial<PlanDay>);
}
export const removePlanDay = (id: string) => planDaysRepo.remove(id);

export const listPlanExercises = () => planExercisesRepo.list();
export function addPlanExercise(input: {
	plan_day_id: string;
	exercise_id: string;
	target_sets: number;
	target_reps_low: number;
	target_reps_high: number;
	sort_order?: number;
}): Promise<PlanExercise> {
	return planExercisesRepo.create(input as Partial<PlanExercise>);
}
export const removePlanExercise = (id: string) => planExercisesRepo.remove(id);

// ---- sessions / sets ----
export const listSessions = () => sessionsRepo.list();
export function startSession(logged_on: string, plan_day_id: string | null): Promise<WorkoutSession> {
	return sessionsRepo.create({
		logged_on,
		plan_day_id,
		started_at: new Date().toISOString()
	} as Partial<WorkoutSession>);
}
export function finishSession(id: string): Promise<WorkoutSession> {
	return sessionsRepo.update(id, { ended_at: new Date().toISOString() } as Partial<WorkoutSession>);
}
export const removeSession = (id: string) => sessionsRepo.remove(id);

export const listAllSets = () => setsRepo.list();
export async function listSetsFor(sessionId: string): Promise<SessionSet[]> {
	const { data } = await db()
		.from('session_sets')
		.select('*')
		.eq('session_id', sessionId)
		.order('created_at');
	return (data ?? []) as SessionSet[];
}
export function addSet(input: {
	session_id: string;
	exercise_id: string;
	set_number: number;
	reps: number;
	weight_g: number;
	rpe?: number | null;
}): Promise<SessionSet> {
	return setsRepo.create(input as Partial<SessionSet>);
}
export const removeSet = (id: string) => setsRepo.remove(id);
