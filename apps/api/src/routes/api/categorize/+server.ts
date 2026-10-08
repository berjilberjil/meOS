import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

/**
 * Classify a YouTube video (from its title + channel) into one of the MeOS
 * Productivity categories. Uses the same resolved model as quick-log parsing —
 * cheap/free is fine.
 */
const Schema = z.object({
  category: z.enum(['finance', 'business', 'investing', 'economy', 'content', 'mindset', 'tech', 'other'])
});

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const body = await request.json().catch(() => ({}));
  const title = String(body.title ?? '').slice(0, 300);
  const channel = String(body.channel ?? '').slice(0, 120);
  if (!title && !channel) return json({ category: 'other' });

  let resolved;
  try {
    resolved = await resolveModel('parse', locals.user.id);
  } catch (e) {
    throw error(503, (e as Error)?.message ?? 'AI is not configured on the server');
  }

  try {
    const { object } = await generateObject({
      model: resolved.model,
      schema: Schema,
      prompt: [
        `Classify this YouTube video into exactly ONE category for a personal-finance creator's learning log.`,
        `- finance: personal finance, saving, budgeting, loans, insurance`,
        `- business: companies, business models, startups, case studies`,
        `- investing: stocks, mutual funds, ETFs, portfolio strategy, trading`,
        `- economy: macro, RBI, GDP, inflation, policy, global economy`,
        `- content: content creation, social media growth, editing, storytelling`,
        `- mindset: motivation, discipline, productivity, psychology`,
        `- tech: software, gadgets, AI tools, coding`,
        `- other: anything that doesn't clearly fit above`,
        ``,
        `Title: ${title}`,
        `Channel: ${channel}`,
        ``,
        `Return the single best-fitting category.`
      ].join('\n')
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not categorize: ${(e as Error)?.message ?? 'try again'}`);
  }
};
