import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

const TAGS = ['travel', 'family', 'work', 'personal', 'milestone', 'reminder', 'other'] as const;

const Result = z.object({
  tagId: z.enum(TAGS),
  reason: z.string()
});

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const body = await request.json().catch(() => ({}));
  const title = typeof body.title === 'string' ? body.title.trim() : '';
  if (!title) throw error(400, 'No event title');
  const date = typeof body.date === 'string' ? body.date : '';

  let resolved;
  try {
    resolved = await resolveModel('parse', locals.user.id);
  } catch (e) {
    throw error(503, (e as Error)?.message ?? 'AI is not configured on the server');
  }

  try {
    const { object } = await generateObject({
      model: resolved.model,
      schema: Result,
      prompt: [
        `Classify this personal life event into exactly one tag: ${TAGS.join(', ')}.`,
        `title: ${title}`,
        date ? `date: ${date}` : '',
        `travel = trips/flights; family = relatives/birthdays; work = job/meetings;`,
        `milestone = rare big life marks; reminder = bills/dues; personal = everyday; other = none of those.`,
        `reason: 5–12 words.`
      ]
        .filter(Boolean)
        .join('\n')
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not classify that: ${(e as Error)?.message ?? 'try again'}`);
  }
};
