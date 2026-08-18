export interface HealthLog {
	id: string;
	user_id: string;
	logged_on: string;
	weight_g: number | null;
	sleep_min: number | null;
	water_ml: number | null;
	mood: string | null;
	notes: string | null;
	created_at: string;
	updated_at: string;
}

export interface FitnessLog {
	id: string;
	user_id: string;
	logged_on: string;
	activity: string;
	duration_min: number;
	calories: number | null;
	distance_m: number | null;
	notes: string | null;
	created_at: string;
	updated_at: string;
}
