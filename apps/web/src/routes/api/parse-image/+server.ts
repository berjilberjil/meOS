import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';
import { CATEGORIES, CATEGORY_HINTS, QUALITIES, QUALITY_HINTS, HOLDING_TYPES } from '$lib/finance';

/**
 * MyOS screenshot reader. The user drops a UPI screenshot / bank statement (mode
 * "transactions") or a portfolio screenshot (mode "portfolio"); Gemini vision
 * reads it into structured rows the native app reviews and then saves. Like the
 * text parser, the server only structures meaning — it never touches the DB.
 */

const TxnItem = z.object({
  kind: z.enum(['income', 'expense']),
  amountInr: z.number(),
  category: z.enum(CATEGORIES),
  quality: z.enum(QUALITIES).nullable(),
  merchant: z.string().nullable(),
  account: z.string().nullable(),
  note: z.string().nullable(),
  date: z.string().nullable()
});
const TxnResult = z.object({ summary: z.string(), transactions: z.array(TxnItem) });

const HoldingItem = z.object({
  name: z.string(),
  type: z.enum(HOLDING_TYPES),
  investedInr: z.number().nullable(),
  currentInr: z.number(),
  units: z.number().nullable(),
  note: z.string().nullable()
});
const PortfolioResult = z.object({ summary: z.string(), holdings: z.array(HoldingItem) });

function txnPrompt(): string {
  return [
    `These images are screenshots of the user's payment history — UPI apps (GPay, PhonePe,`,
    `Paytm), bank SMS, or a bank statement. All money is Indian rupees (₹).`,
    ``,
    `Extract EVERY distinct real transaction you can clearly read. For each:`,
    `- kind: "expense" for money going out; "income" if it is clearly credited/received.`,
    `- amountInr: the rupee amount as a number (no ₹, no commas).`,
    `- category: the closest of: ${CATEGORIES.join(', ')}. ${CATEGORY_HINTS}.`,
    `- quality: judge the spend — ${QUALITY_HINTS}. null for income.`,
    `- merchant: the payee or sender name shown (e.g. "Swiggy", "BSNL", "Amma"), else null.`,
    `- account: the bank or app the money moved through if visible (e.g. "HDFC", "GPay", "PhonePe"), else null.`,
    `- note: anything useful shown (a UPI note / reference), else null.`,
    `- date: the transaction date as yyyy-MM-dd if a date is visible, else null.`,
    ``,
    `Ignore failed, pending, or declined transactions and any non-transaction UI (balances,`,
    `headers, ads). Never invent a transaction you cannot read. If nothing is readable, return`,
    `an empty transactions array.`,
    `summary: one short sentence, e.g. "Read 6 transactions — ₹2,340 spent, ₹0 in."`
  ].join('\n');
}

function portfolioPrompt(): string {
  return [
    `These images are screenshots of the user's investment portfolio (Groww, Zerodha, Kuvera,`,
    `or another broker/app). All money is Indian rupees (₹).`,
    ``,
    `Extract EVERY holding you can clearly read. For each:`,
    `- name: the fund or stock name as shown.`,
    `- type: one of ${HOLDING_TYPES.join(', ')} (mutual fund -> mutualFund).`,
    `- investedInr: the invested/cost amount if shown, else null.`,
    `- currentInr: the current value (number, no ₹/commas).`,
    `- units: quantity/units held if shown, else null.`,
    `- note: today's/overall gain-loss text if shown, else null.`,
    ``,
    `A portfolio total or "Current value" summary row is a cross-check, NOT a holding — do not`,
    `emit it as one. Never invent a holding. If nothing is readable, return an empty array.`,
    `summary: one short sentence, e.g. "Read 4 holdings worth ₹18,200."`
  ].join('\n');
}

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const mode = body.mode === 'portfolio' ? 'portfolio' : 'transactions';
  const mediaType = typeof body.mediaType === 'string' ? body.mediaType : 'image/png';
  const images: string[] = Array.isArray(body.images)
    ? body.images.filter((s: unknown) => typeof s === 'string' && s.length > 0).slice(0, 8)
    : [];
  if (!images.length) throw error(400, 'No image to read');

  const schema = mode === 'portfolio' ? PortfolioResult : TxnResult;
  const prompt = mode === 'portfolio' ? portfolioPrompt() : txnPrompt();

  let resolved;
  try {
    resolved = await resolveModel('vision', locals.user.id);
  } catch (e) {
    throw error(503, (e as Error)?.message ?? 'AI is not configured on the server');
  }

  try {
    const { object } = await generateObject({
      model: resolved.model,
      schema,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            ...images.map((b64) => ({
              type: 'image' as const,
              image: Buffer.from(b64, 'base64'),
              mediaType
            }))
          ]
        }
      ]
    });
    return json(object);
  } catch (e) {
    throw error(502, `Could not read that image: ${(e as Error)?.message ?? 'try again'}`);
  }
};
