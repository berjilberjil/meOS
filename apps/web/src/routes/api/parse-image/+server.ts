import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

/**
 * MyOS screenshot reader. The user drops a photo of a packaged food's nutrition
 * label (mode "food"); Gemini vision reads it into structured rows the native
 * app reviews and then saves. Like the text parser, the server only structures
 * meaning — it never touches the DB.
 */

const FOOD_CATEGORIES = ['protein', 'carb', 'veg', 'dairy', 'fruit', 'drink', 'junk', 'other'] as const;

const FoodItem = z.object({
  name: z.string(),
  category: z.enum(FOOD_CATEGORIES),
  servingLabel: z.string(),
  calories: z.number(),
  protein: z.number(),
  carbs: z.number(),
  fiber: z.number(),
  fats: z.number(),
  vitamins: z.string().nullable()
});
const FoodResult = z.object({ summary: z.string(), foods: z.array(FoodItem) });

const ScanObject = z.object({
  name: z.string(),
  needed: z.enum(['yes', 'no', 'maybe']),
  why: z.string(),
  useful: z.string()
});
const ScanResult = z.object({
  kind: z.enum(['food', 'object']),
  summary: z.string(),
  foods: z.array(FoodItem),
  object: ScanObject.nullable()
});

const BelongingResult = z.object({
  name: z.string(),
  category: z.string(),
  priceInr: z.number(),
  lifeMonths: z.number(),
  summary: z.string()
});

function scanPrompt(context: string): string {
  const who = context.trim()
    ? `WHO THEY ARE (use this — you are Catherine, their personal AI):\n${context.trim().slice(0, 4000)}\n`
    : `You are Catherine, their personal AI. You do not have a data snapshot this time — still identify the object.\n`;
  return [
    `You are Catherine inside MyOS. Look at this photo.`,
    who,
    `First decide: is the main subject edible food (a dish, a pack, a label, a menu item)?`,
    ``,
    `IF FOOD: kind=food, object=null. Fill foods[] with name, category, serving, macros. summary = one line of what they should eat/log.`,
    ``,
    `IF NOT FOOD: kind=object, foods=[]. Identify the EXACT thing. Never say "Unknown object" unless the image is blank/black/blurred beyond recognition.`,
    `object = {`,
    `  name: specific name (e.g. "Hydro Flask 32oz", "Anker USB-C cable", "Noise-cancelling headphones") — not "object" or "item",`,
    `  needed: yes | no | maybe — WANTED FOR THEM, judged against THEIR life above (fitness, money, work, city, goals).`,
    `    yes = this helps a real goal they already have.`,
    `    no = clutter, impulse, duplicate, or fights a goal (junk spend, unused gadget).`,
    `    maybe = could help IF they use it a certain way.`,
    `  why: 1-2 blunt sentences. Why you said yes/no/maybe for THEM specifically. Quote a real fact from their data when you can.`,
    `  useful: how it would actually help (or what to do instead). Concrete. Not generic.`,
    `}.`,
    `summary: one short sentence naming the thing + the verdict.`,
    `Never invent a brand you cannot see. If you can see the category but not the brand, name the category clearly (e.g. "stainless steel water bottle").`
  ].join('\n');
}

function belongingPrompt(context: string): string {
  return [
    `You are identifying a product someone owns so MyOS can file it in Stuff.`,
    context.trim() ? `Available shelves: ${context.trim().slice(0, 2000)}` : '',
    `Look at the photo. Name the exact product.`,
    `- name: brand + product (e.g. "CMF Buds 2", "Nike Vomero 18", "Activa 6G"). Never "earbuds" alone if a brand is visible.`,
    `- category: one shelf id from the list above (gadgets, clothes, home, books, wheels, other, or a custom id).`,
    `- priceInr: typical India street/MRP in WHOLE rupees. Best guess. 0 only if you truly cannot estimate.`,
    `- lifeMonths: how many months this should last before it has paid for itself (earbuds 24, phone 36, tee 12, bike 60).`,
    `- summary: one short line, e.g. "CMF Buds 2 — about ₹2,499."`,
    `Never invent a brand you cannot see. If you only know the type, name the type clearly.`
  ].filter(Boolean).join('\n');
}

function foodPrompt(): string {
  return [
    `These images show a packaged food item — a nutrition/ingredients label, a product`,
    `pack, or a menu item at a restaurant. Extract each distinct food/product visible so it`,
    `can be added to a food-tracking library and logged for today.`,
    ``,
    `For each food:`,
    `- name: the product/dish name as shown (e.g. "Lay's Magic Masala", "Amul Butter").`,
    `- category: the closest of: ${FOOD_CATEGORIES.join(', ')} (chips/sweets/soda -> junk).`,
    `- servingLabel: the serving size the macros below are FOR, as a short human label`,
    `  (e.g. "1 pack (28 g)", "100 g", "1 slice"). Prefer the label's own "per serving" if shown,`,
    `  else "100 g".`,
    `- calories, protein, carbs, fiber, fats: the numbers for exactly that one serving`,
    `  (grams for protein/carbs/fiber/fats, kcal for calories). Use 0 if genuinely absent.`,
    `- vitamins: notable vitamins/minerals listed (e.g. "B12, Iron"), else null.`,
    ``,
    `Never invent a food you cannot read. If nothing is readable, return an empty array.`,
    `summary: one short sentence, e.g. "Read Lay's Magic Masala — 160 kcal per pack."`
  ].join('\n');
}

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const mediaType = typeof body.mediaType === 'string' ? body.mediaType : 'image/png';
  const images: string[] = Array.isArray(body.images)
    ? body.images.filter((s: unknown) => typeof s === 'string' && s.length > 0).slice(0, 8)
    : [];
  if (!images.length) throw error(400, 'No image to read');

  const mode = typeof body.mode === 'string' ? body.mode : 'food';
  const context = typeof body.context === 'string' ? body.context : '';
  const schema = mode === 'scan' ? ScanResult : mode === 'belonging' ? BelongingResult : FoodResult;
  const prompt = mode === 'scan' ? scanPrompt(context) : mode === 'belonging' ? belongingPrompt(context) : foodPrompt();

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
