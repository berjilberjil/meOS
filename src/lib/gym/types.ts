// Gym programming & progress types. Weight in grams (weight_g), like health_logs.

export type MuscleGroup =
	| 'chest'
	| 'back'
	| 'legs'
	| 'shoulders'
	| 'arms'
	| 'core'
	| 'full_body'
	| 'cardio';

export type Equipment = 'barbell' | 'dumbbell' | 'machine' | 'bodyweight' | 'cable' | 'kettlebell' | 'other';

export interface Exercise {
	id: string;
	user_id: string | null; // null = shared/global
	name: string;
	muscle_group: MuscleGroup;
	equipment: Equipment;
	parent_exercise_id: string | null;
	unilateral: boolean;
	created_at: string;
}

export interface WorkoutPlan {
	id: string;
	user_id: string;
	name: string;
	active: boolean;
	created_at: string;
	updated_at: string;
}

export interface PlanDay {
	id: string;
	user_id: string;
	plan_id: string;
	name: string;
	weekday: number | null; // 0=Sun..6=Sat
	sort_order: number;
	created_at: string;
}

export interface PlanExercise {
	id: string;
	user_id: string;
	plan_day_id: string;
	exercise_id: string;
	target_sets: number;
	target_reps_low: number;
	target_reps_high: number;
	target_weight_g: number | null;
	sort_order: number;
	created_at: string;
}

export interface WorkoutSession {
	id: string;
	user_id: string;
	plan_day_id: string | null;
	logged_on: string;
	started_at: string | null;
	ended_at: string | null;
	notes: string | null;
	created_at: string;
	updated_at: string;
}

export interface SessionSet {
	id: string;
	user_id: string;
	session_id: string;
	exercise_id: string;
	set_number: number;
	reps: number;
	weight_g: number;
	rpe: number | null;
	created_at: string;
}

export const MUSCLE_GROUPS: MuscleGroup[] = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'full_body', 'cardio'];
export const EQUIPMENT: Equipment[] = ['barbell', 'dumbbell', 'machine', 'bodyweight', 'cable', 'kettlebell', 'other'];
export const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
