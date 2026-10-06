import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

/**
 * Memory extraction — decide whether an exchange contained anything worth
 * remembering for good.
 *
 * The bar is deliberately high. A second brain that remembers everything is a
 * transcript, not a memory: it fills the context window with noise and buries
 * the handful of facts that actually shape an answer. So this returns nothing
 * far more often than it returns something, and the client applies its own
 * deterministic filter on top (see `MemoryBank.judge`).
 *
 * Runs on the cheap `parse` route — this is a classification, not reasoning.
 */
const CATEGORIES = [
  'identity', 'preference', 'goal', 'project',
  'skill', 'decision', 'relationship', 'workflow', 'other'
] as const;

const Schema = z.object({
  memories: z
    .array(
      z.object({
        content: z.string().describe('The fact in one sentence, written about the user, self-contained.'),
        category: z.enum(CATEGORIES),
        importance: z.number().int().min(1).max(5),
        confidence: z.number().min(0).max(1)
      })
    )
    .max(3)
});

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const userMsg = String(body.user ?? '').slice(0, 4000);
  const assistantMsg = String(body.assistant ?? '').slice(0, 4000);
  const known = (Array.isArray(body.known) ? body.known : [])
    .slice(0, 40)
    .map((k: unknown) => String(k).slice(0, 240));

  if (!userMsg.trim()) return json({ memories: [] });

  let resolved;
  try {
    resolved = await resolveModel('parse', locals.user.id);
  } catch {
    // Extraction is a bonus pass, never the point of the request. If the model
    // isn't configured, the conversation still works — it just doesn't learn.
    return json({ memories: [] });
  }

  try {
    const { object } = await generateObject({
      model: resolved.model,
      schema: Schema,
      prompt: [
        `Read one exchange between a user and their personal AI. Extract ONLY facts worth remembering`,
        `permanently — things that will still be true next month.`,
        ``,
        `REMEMBER (examples):`,
        `- "From now on I use PostgreSQL for my projects" → preference`,
        `- "My main project is MeOS, a second brain" → project`,
        `- "I'm training for a half marathon in December" → goal`,
        `- "I decided to drop the Tauri shell and go native Swift" → decision`,
        `- "Ravi is my co-founder" → relationship`,
        ``,
        `DO NOT REMEMBER:`,
        `- Anything true only today: what they ate, how they slept, today's mood or weather.`,
        `- Questions they asked, or anything the assistant said about itself.`,
        `- Passwords, keys, OTPs, card or account numbers — never, under any circumstances.`,
        `- Anything already in KNOWN below, or a reworded version of it.`,
        `- Speculation. If they were thinking out loud rather than stating a fact, skip it.`,
        ``,
        `Write each memory as a standalone sentence about the user, in the third person`,
        `("Uses PostgreSQL for all projects"), not as a quote.`,
        `confidence: 1.0 only when they stated it outright. Below 0.6 means don't bother.`,
        `importance: 5 = core to who they are, 1 = trivia.`,
        `Returning an empty list is the correct answer most of the time.`,
        ``,
        `KNOWN ALREADY:`,
        known.length ? known.map((k: string) => `- ${k}`).join('\n') : '(nothing yet)',
        ``,
        `USER SAID:`,
        userMsg,
        ``,
        `ASSISTANT REPLIED:`,
        assistantMsg
      ].join('\n')
    });
    return json(object);
  } catch {
    return json({ memories: [] });
  }
};
