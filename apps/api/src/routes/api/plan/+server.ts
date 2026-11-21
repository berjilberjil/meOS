import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { readJsonBody } from '$lib/server/http';
import { z } from 'zod';

/**
 * MeOS weekly plan generator. Given the user's goal + calorie/macro targets and the
 * foods/exercises actually in their library, draft a 7-day workout split and a
 * macro-hitting meal plan. The client maps names back to library ids and lets them
 * edit. Picks ONLY from the provided lists so everything resolves.
 */

const PlanSchema = z.object({
  summary: z.string(),
  workout: z.array(
    z.object({
      weekday: z.number().int().min(0).max(6), // 0=Sun … 6=Sat
      rest: z.boolean(),
      exercises: z.array(z.object({ name: z.string(), sets: z.number().int(), reps: z.number().int() }))
    })
  ),
  meals: z.array(
    z.object({
      weekday: z.number().int().min(0).max(6),
      breakfast: z.array(z.string()),
      lunch: z.array(z.string()),
      dinner: z.array(z.string()),
      snacks: z.array(z.string())
    })
  )
});

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = (await readJsonBody(request, 64_000)) as Record<string, unknown>;
  const goal = String(body.goal ?? 'maintain').slice(0, 200);
  const numberIn = (v: unknown, min: number, max: number): number => {
    const n = Number(v);
    return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : 0;
  };
  const cals = numberIn(body.calories, 0, 20_000);
  const protein = numberIn(body.protein, 0, 1_000);
  // 120 elements was capped; the length of each element was not, so one
  // element could carry the whole prompt.
  const names = (v: unknown): string[] =>
    Array.isArray(v) ? v.slice(0, 120).map((x) => String(x).slice(0, 120)) : [];
  const foods: string[] = names(body.foods);
  const exercises: string[] = names(body.exercises);
  const daysPerWeek = numberIn(body.daysPerWeek ?? 5, 0, 7);

  const prompt = [
    `Build the user a 7-day fitness plan. Goal: ${goal}. Daily target ≈ ${cals || '(unknown)'} kcal and`,
    `${protein || '(unknown)'} g protein. Train about ${daysPerWeek} days/week; the rest are rest days (rest:true, empty exercises).`,
    ``,
    `WORKOUT: give each weekday (0=Sun … 6=Sat) a sensible split (push/pull/legs or upper/lower — group muscles`,
    `smartly, don't hit the same muscle two days running). 4–6 exercises per training day, with sets and reps`,
    `(compounds ~4×6-8, isolation ~3×10-15). Use ONLY these exercise names, verbatim:`,
    exercises.join(', ') || '(none provided)',
    ``,
    `MEALS: for every weekday give breakfast, lunch, dinner and snacks as arrays of food names that together`,
    `roughly hit the calorie and protein target. Vary it across the week; keep it realistic and Tamil/Indian.`,
    `Use ONLY these food names, verbatim:`,
    foods.join(', ') || '(none provided)',
    ``,
    `Every name MUST come from the lists above so it resolves. "summary" is one blunt sentence on the plan's logic.`
  ].join('\n');

  let resolved;
  try {
    resolved = await resolveModel('plan', locals.user.id);
  } catch (e) {
    throw error(503, (e as Error)?.message ?? 'AI is not configured on the server');
  }

  try {
    const { object } = await generateObject({
      model: resolved.model,
      schema: PlanSchema,
      prompt
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not build a plan: ${(e as Error)?.message ?? 'try again'}`);
  }
};
