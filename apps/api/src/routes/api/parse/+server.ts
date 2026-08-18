import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

/**
 * MyOS quick-log AI. The user types (or dictates) ONE line about their day and
 * Gemini splits it into structured entries the native app files into the right
 * key: fitness, journal, notes. The server only structures meaning —
 * it never touches the database; the client applies the result.
 */
const ParseSchema = z.object({
  // One short human sentence describing what was logged (for a toast).
  summary: z.string(),
  fitness: z
    .object({
      weightKg: z.number().nullable(),
      calories: z.number().nullable(),
      proteinG: z.number().nullable(),
      waterMl: z.number().nullable(),
      note: z.string().nullable()
    })
    .nullable(),
  journal: z
    .object({
      note: z.string().nullable(),
      mood: z.number().int().min(1).max(5).nullable(),
      wins: z.array(z.string()),
      mistakes: z.array(z.string()),
      lessons: z.array(z.string()),
      gratitude: z.array(z.string())
    })
    .nullable(),
  notes: z.array(z.object({ title: z.string(), body: z.string() }))
});

function buildPrompt(text: string): string {
  return [
    `You convert ONE line of a personal daily log into structured entries for MyOS,`,
    `the user's personal operating system. They said:`,
    ``,
    `"${text}"`,
    ``,
    `Split it across three areas. Only fill what they actually said — leave the rest empty/null.`,
    ``,
    `FITNESS — body/nutrition numbers. weightKg, calories, proteinG (grams), waterMl (millilitres; "2 litres" → 2000). null each if not mentioned. note optional.`,
    ``,
    `JOURNAL — reflection/feeling. mood is 1(awful)–5(great) if a feeling is expressed, else null.`,
    `Put clear achievements in wins, regrets/errors in mistakes, takeaways in lessons, thanks in gratitude. Free reflection goes in note.`,
    ``,
    `NOTES — only genuine "note this down"/idea/reminder content → title + body. Usually empty.`,
    ``,
    `summary: one short sentence, e.g. "Logged 40g protein and a low mood."`
  ].join('\n');
}

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const text = String(body.text ?? '').trim();
  if (!text) throw error(400, 'Nothing to parse');

  let resolved;
  try {
    resolved = await resolveModel('parse', locals.user.id);
  } catch (e) {
    throw error(503, (e as Error)?.message ?? 'AI logging is not configured on the server');
  }

  try {
    const { object } = await generateObject({
      model: resolved.model,
      schema: ParseSchema,
      prompt: buildPrompt(text)
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not understand that: ${(e as Error)?.message ?? 'try again'}`);
  }
};
