import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { generateObject } from 'ai';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { z } from 'zod';
import { CATEGORIES, CATEGORY_HINTS, QUALITIES, QUALITY_HINTS } from '$lib/finance';

/**
 * MyOS quick-log AI. The user types (or dictates) ONE line about their day and
 * Gemini splits it into structured entries the native app files into the right
 * key: finance, fitness, journal, notes. The server only structures meaning —
 * it never touches the database; the client applies the result.
 */
const ParseSchema = z.object({
  // One short human sentence describing what was logged (for a toast).
  summary: z.string(),
  finance: z.array(
    z.object({
      spoken: z.string(),
      kind: z.enum(['income', 'expense']),
      amountInr: z.number(),
      category: z.enum(CATEGORIES),
      quality: z.enum(QUALITIES).nullable(),
      merchant: z.string().nullable(),
      note: z.string().nullable()
    })
  ),
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
    `the user's personal operating system. All money is Indian rupees (₹). They said:`,
    ``,
    `"${text}"`,
    ``,
    `Split it across four areas. Only fill what they actually said — leave the rest empty/null.`,
    ``,
    `FINANCE — every amount of money spent or received.`,
    `- kind: "expense" unless it is clearly money coming IN (salary, received, refund) → "income".`,
    `- amountInr: the number of rupees (e.g. "spent 200 on auto" → 200). "5k"/"5 thousand" → 5000. "1.5L"/"1.5 lakh" → 150000.`,
    `- category: choose the closest of: ${CATEGORIES.join(', ')}. ${CATEGORY_HINTS}.`,
    `- quality: judge the spend — ${QUALITY_HINTS}. null for income.`,
    `- merchant: who was paid / who paid (e.g. "Swiggy", "BSNL", "mom") if clear, else null.`,
    `- note: short free text if useful, else null.`,
    ``,
    `FITNESS — body/nutrition numbers. weightKg, calories, proteinG (grams), waterMl (millilitres; "2 litres" → 2000). null each if not mentioned. note optional.`,
    ``,
    `JOURNAL — reflection/feeling. mood is 1(awful)–5(great) if a feeling is expressed, else null.`,
    `Put clear achievements in wins, regrets/errors in mistakes, takeaways in lessons, thanks in gratitude. Free reflection goes in note.`,
    ``,
    `NOTES — only genuine "note this down"/idea/reminder content → title + body. Usually empty.`,
    ``,
    `summary: one short sentence, e.g. "Logged ₹200 transport, 40g protein, and a low mood."`
  ].join('\n');
}

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw error(503, 'AI logging is not configured on the server');

  const body = await request.json().catch(() => ({}));
  const text = String(body.text ?? '').trim();
  if (!text) throw error(400, 'Nothing to parse');

  try {
    const google = createGoogleGenerativeAI({ apiKey });
    const { object } = await generateObject({
      model: google(env.GEMINI_MODEL ?? 'gemini-2.5-flash'),
      schema: ParseSchema,
      prompt: buildPrompt(text)
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not understand that: ${(e as Error)?.message ?? 'try again'}`);
  }
};
