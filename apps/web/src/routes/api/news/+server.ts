import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateText, generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

/**
 * MyOS Today news — real, recent tech + finance headlines for the user (India
 * focus). Uses Gemini with Google Search grounding so the news is actually current
 * (not the model's stale memory), then structures it.
 */

const NewsSchema = z.object({
  items: z
    .array(
      z.object({
        title: z.string(),
        category: z.enum(['tech', 'ai', 'markets', 'india', 'finance', 'crypto']),
        summary: z.string(), // one line
        detail: z.string(), // 2-3 sentences of extra context, shown when expanded
        source: z.string().nullable(), // publication name
        url: z.string().nullable(), // link to the article/source
        time: z.string().nullable() // when it happened / was published, human readable
      })
    )
    .max(8)
});

const SEARCH_PROMPT = [
  `Find the most important TECH and FINANCE news from the last 3 days, useful to someone who follows`,
  `tech and Indian markets. Cover: major AI / big-tech launches (e.g. new Claude/OpenAI/Google models),`,
  `Indian stock market moves (Nifty/Sensex), RBI, notable earnings, and 1-2 global finance items.`,
  `For each item give: a one-line factual summary, the source publication name, the source article URL,`,
  `and the date it was published or happened. Prefer the newest, highest-impact items.`
].join(' ');

export const POST: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  let resolved;
  try {
    resolved = await resolveModel('news', locals.user.id);
  } catch (e) {
    throw error(503, (e as Error)?.message ?? 'AI is not configured on the server');
  }
  if (!resolved.google) throw error(503, 'News needs a Gemini key — it uses Google Search grounding');

  try {
    const model = resolved.model;
    const google = resolved.google;

    // 1) Grounded search → real current news as text.
    const { text } = await generateText({
      model,
      tools: { google_search: google.tools.googleSearch({}) },
      prompt: SEARCH_PROMPT
    });

    // 2) Structure the grounded text into items (no tools here).
    const { object } = await generateObject({
      model,
      schema: NewsSchema,
      prompt:
        `Turn these grounded search results into 5-8 news items. For each: a punchy title, ` +
        `a one-line summary, a 'detail' of 2-3 sentences with the extra context/why-it-matters, ` +
        `the source publication name, the source article 'url' (if present in the results, else null), ` +
        `and 'time' = the human-readable date it was published or happened (e.g. "Aug 7, 2026"). ` +
        `Keep facts; drop anything vague.\n\n${text}`
    });

    return json(object);
  } catch (e) {
    throw error(502, `Could not fetch news: ${(e as Error)?.message ?? 'try again'}`);
  }
};
