import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { generateText, generateObject } from 'ai';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
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
        source: z.string().nullable()
      })
    )
    .max(8)
});

const SEARCH_PROMPT = [
  `Find the most important TECH and FINANCE news from the last 3 days, useful to someone who follows`,
  `tech and Indian markets. Cover: major AI / big-tech launches (e.g. new Claude/OpenAI/Google models),`,
  `Indian stock market moves (Nifty/Sensex), RBI, notable earnings, and 1-2 global finance items.`,
  `For each, give a one-line factual summary and the source name. Prefer the newest, highest-impact items.`
].join(' ');

export const POST: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw error(503, 'AI is not configured on the server');

  try {
    const google = createGoogleGenerativeAI({ apiKey });
    const model = google(env.GEMINI_MODEL ?? 'gemini-2.5-flash');

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
      prompt: `Turn these grounded search results into 5-8 concise news items. Keep facts and sources; drop anything vague.\n\n${text}`
    });

    return json(object);
  } catch (e) {
    throw error(502, `Could not fetch news: ${(e as Error)?.message ?? 'try again'}`);
  }
};
