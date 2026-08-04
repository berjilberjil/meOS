import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { generateObject } from 'ai';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { z } from 'zod';
import { financePrinciples } from '$lib/finance';

/**
 * MyOS portfolio review. Given the holdings read from this week's screenshot plus
 * the user's real money situation (loan, income, protection) passed in as context,
 * Gemini gives a blunt, rules-grounded read: allocation, diversification, concrete
 * actions, ideas. The priority order (debt + protection before SIPs) is baked in.
 * All figures come from the request context — nothing personal is hardcoded here.
 */

const AdviceSchema = z.object({
  verdict: z.string(), // one blunt headline sentence
  allocation: z.string(), // read on how the money is split across asset types
  diversification: z.string(), // concentration / spread risk
  actions: z.array(z.string()), // concrete next steps, priority order
  ideas: z.array(z.string()), // funds/assets/directions to consider (only if they should invest at all)
  summary: z.string() // 1–2 sentence wrap
});

const inr = (n: number) => `₹${Math.round(n).toLocaleString('en-IN')}`;

function buildPrompt(body: any): string {
  const holdings = Array.isArray(body.holdings) ? body.holdings : [];
  const c = body.context ?? {};
  const prev = body.prev ?? null;

  const invested = holdings.reduce((s: number, h: any) => s + (Number(h.investedInr) || 0), 0);
  const current = holdings.reduce((s: number, h: any) => s + (Number(h.currentInr) || 0), 0);

  const holdingLines = holdings.length
    ? holdings
        .map((h: any) => {
          const inv = Number(h.investedInr) || 0;
          const cur = Number(h.currentInr) || 0;
          const pnl = inv > 0 ? ` (${cur >= inv ? '+' : ''}${inr(cur - inv)})` : '';
          return `- ${h.name} [${h.type}] — now ${inr(cur)}${inv ? `, invested ${inr(inv)}` : ''}${pnl}`;
        })
        .join('\n')
    : '(no holdings — portfolio is empty)';

  const changeLine = prev
    ? `Since last snapshot (${prev.date}): value ${inr(prev.totalCurrent ?? 0)} -> ${inr(current)}.`
    : `This is the first snapshot — no prior week to compare.`;

  return [
    financePrinciples(),
    ``,
    `THEIR MONEY RIGHT NOW:`,
    `- Monthly income: ${inr(c.monthlyIncomeInr ?? 0)}. Spent this month: ${inr(c.monthExpenseInr ?? 0)}.`,
    `- Loan outstanding: ${inr(c.goldLoanOutstandingInr ?? 0)} at ~${c.goldLoanRatePct ?? 0}%.`,
    `- Emergency fund: ${inr(c.emergencyCurrentInr ?? 0)} of ${inr(c.emergencyTargetInr ?? 0)} target.`,
    `- Term insurance bought: ${c.termInsuranceBought ? 'yes' : 'NO'}. Own health insurance: ${c.healthInsuranceBought ? 'yes' : 'NO'}.`,
    ``,
    `THIS WEEK'S PORTFOLIO (invested ${inr(invested)}, current ${inr(current)}):`,
    holdingLines,
    changeLine,
    ``,
    `Give them a review as their blunt finance mentor. Judge it against the principles above — if they are`,
    `investing in the market while costly debt is large and their protection/emergency fund are`,
    `missing, say so plainly and tell them to redirect. Only suggest specific funds/assets in "ideas"`,
    `if investing is actually the right move for them right now; otherwise use "ideas" for what to do`,
    `instead (debt, insurance, income). Keep every field concrete, specific to their numbers, and short.`,
    `"actions" must be an ordered list of what to do next, most important first.`
  ].join('\n');
}

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw error(503, 'AI is not configured on the server');

  const body = await request.json().catch(() => ({}));

  try {
    const google = createGoogleGenerativeAI({ apiKey });
    const { object } = await generateObject({
      // A weekly, high-value call — use a stronger reasoning model if one is set.
      model: google(env.GEMINI_REASONING_MODEL ?? env.GEMINI_MODEL ?? 'gemini-2.5-flash'),
      schema: AdviceSchema,
      prompt: buildPrompt(body)
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not review that: ${(e as Error)?.message ?? 'try again'}`);
  }
};
