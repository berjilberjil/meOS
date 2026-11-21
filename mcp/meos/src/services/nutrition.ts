import type { FitnessDay, FitnessProfile, Profile } from '../schemas/models.ts';
import { todayKey } from '../utils/dates.ts';

const ACTIVITY_MULTIPLIER: Record<string, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
  athlete: 1.9
};
const GOAL_OFFSET: Record<string, number> = { cut: -500, maintain: 0, bulk: 300 };

export function ageFrom(dob: string, age: number | null | undefined, today = new Date()): number | null {
  if (/^\d{4}-\d{2}-\d{2}/.test(dob)) {
    const [y, m, d] = dob.slice(0, 10).split('-').map(Number);
    let years = today.getUTCFullYear() - y!;
    const beforeBirthday =
      today.getUTCMonth() + 1 < m! || (today.getUTCMonth() + 1 === m! && today.getUTCDate() < d!);
    if (beforeBirthday) years -= 1;
    if (years >= 0 && years <= 120) return years;
  }
  return typeof age === 'number' && age > 0 ? age : null;
}

export function latestWeight(
  fitness: Record<string, FitnessDay>,
  beforeOrOn = todayKey()
): { date: string; kg: number } | null {
  const rows = Object.entries(fitness)
    .filter(([d, v]) => d <= beforeOrOn && typeof v?.weightKg === 'number' && v.weightKg! > 0)
    .sort(([a], [b]) => a.localeCompare(b));
  const last = rows.at(-1);
  return last ? { date: last[0], kg: last[1].weightKg! } : null;
}

export function bmi(
  heightCm: number | null | undefined,
  weightKg: number | null | undefined
): { value: number; category: string } | null {
  if (!heightCm || !weightKg || heightCm <= 0 || weightKg <= 0) return null;
  const m = heightCm / 100;
  const value = weightKg / (m * m);
  const category =
    value < 18.5 ? 'underweight' : value < 25 ? 'normal range' : value < 30 ? 'overweight' : 'obese range';
  return { value: Math.round(value * 10) / 10, category };
}

export interface CalorieTargets {
  bmr: number;
  tdee: number;
  maintain: number;
  cut: number;
  bulk: number;
  goal_calories: number;
  protein_g: number;
  fat_g: number;
  carb_g: number;
  formula: string;
}

/**
 * Mifflin-St Jeor × activity, mirroring `Nutrition.swift` and the Fitness tab.
 * Returning null when age/height/weight are missing is deliberate: a fabricated
 * target is worse than saying "not enough body metrics".
 */
export function calorieTargets(
  profile: Profile,
  fitnessProfile: FitnessProfile,
  weightKg: number | null
): CalorieTargets | null {
  const age = ageFrom(profile.dob, profile.age);
  const height = profile.heightCm ?? null;
  if (!weightKg || !height || !age) return null;
  const sex = fitnessProfile.sex === 'female' ? 'female' : 'male';
  const bmr = 10 * weightKg + 6.25 * height - 5 * age + (sex === 'male' ? 5 : -161);
  const activity = ACTIVITY_MULTIPLIER[fitnessProfile.activity] ?? 1.55;
  const tdee = bmr * activity;
  const goal = fitnessProfile.goal ?? 'maintain';
  const goalCalories = Math.max(1000, tdee + (GOAL_OFFSET[goal] ?? 0));
  const protein = (goal === 'cut' ? 2.0 : 1.8) * weightKg;
  const fat = (goalCalories * 0.25) / 9;
  const carbs = Math.max(0, (goalCalories - protein * 4 - fat * 9) / 4);
  const r = (n: number) => Math.round(n);
  return {
    bmr: r(bmr),
    tdee: r(tdee),
    maintain: r(tdee),
    cut: r(Math.max(1000, tdee - 500)),
    bulk: r(Math.max(1000, tdee + 300)),
    goal_calories: r(goalCalories),
    protein_g: r(protein),
    fat_g: r(fat),
    carb_g: r(carbs),
    formula: 'Mifflin-St Jeor × activity, matching the MeOS Fitness tab'
  };
}
