import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { generateObject } from 'ai';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { z } from 'zod';
import { mentorSystem } from '$lib/mentor';

/**
 * MyOS "what to do now" — the Today screen's mentor nudge. Given a snapshot of
 * the user's data, return a few concrete, prioritised actions to fix their life
 * right now, most important first. Grounded in their real numbers and the money
 * principles.
 */

const SuggestSchema = z.object({
  headline: z.string(), // one blunt sentence framing where he's at today
  suggestions: z
    .array(
      z.object({
        area: z.enum(['money', 'fitness', 'content', 'career', 'mind', 'life']),
        title: z.string(), // the action, imperative and short ("Buy term insurance today")
        why: z.string(), // one line, grounded in his data
        impact: z.enum(['high', 'medium', 'low'])
      })
    )
    .min(1)
    .max(5)
});

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw error(503, 'AI is not configured on the server');

  const body = await request.json().catch(() => ({}));
  const context = String(body.context ?? '');

  const prompt = [
    `Look at their data and give them 3–5 things to do NOW to fix their life — most important first.`,
    `Each must be concrete and doable today or this week, grounded in their actual numbers (quote them`,
    `in "why"). Cover the highest-leverage areas their data points to: clearing/servicing any high-interest`,
    `debt, protecting themselves (insurance, emergency fund), not over-spending, fitness/consistency, work`,
    `and income growth. Do NOT suggest generic things or things their data shows they already did. Be blunt.`,
    `"headline" is one sentence on where they stand today.`
  ].join('\n');

  try {
    const google = createGoogleGenerativeAI({ apiKey });
    const { object } = await generateObject({
      model: google(env.GEMINI_MODEL ?? 'gemini-2.5-flash'),
      schema: SuggestSchema,
      system: mentorSystem(context),
      prompt
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not read your day: ${(e as Error)?.message ?? 'try again'}`);
  }
};
