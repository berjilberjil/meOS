import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

/**
 * MyOS weekly plan generator. Given the user's goal + calorie/macro targets and the
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

  const body = await request.json().catch(() => ({}));
  const goal = String(body.goal ?? 'maintain');
  const cals = Number(body.calories ?? 0);
  const protein = Number(body.protein ?? 0);
  const foods: string[] = Array.isArray(body.foods) ? body.foods.slice(0, 120) : [];
  const exercises: string[] = Array.isArray(body.exercises) ? body.exercises.slice(0, 120) : [];
  const daysPerWeek = Number(body.daysPerWeek ?? 5);

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
