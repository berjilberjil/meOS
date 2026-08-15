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

  const schema = FoodResult;
  const prompt = foodPrompt();

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
