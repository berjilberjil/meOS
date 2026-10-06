import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateObject } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { z } from 'zod';

/**
 * MeOS screenshot reader. The user drops a photo of a packaged food's nutrition
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

/// The Friday report. `percent` is a signed estimate against last week, and the
/// model is told to leave it at 0 with needsPhotos=true rather than invent one.
const WeeklyResult = z.object({
  verdict: z.enum(['gaining', 'holding', 'slipping', 'unknown']),
  percent: z.number(),
  headline: z.string(),
  read: z.string(),
  workouts: z.array(z.string()),
  diet: z.array(z.string()),
  cheer: z.string(),
  needsPhotos: z.boolean()
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
    `You are Catherine inside MeOS. Look at this photo.`,
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
    `You are identifying a product someone owns so MeOS can file it in Stuff.`,
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

function weeklyPrompt(context: string): string {
  return [
    `You are Catherine inside MeOS, writing this person's weekly body-progress report.`,
    `You are their coach, not a cheerleader and not a hype account. You know them.`,
    ``,
    `THEIR WEEK — goal, targets and what they actually logged:`,
    context.trim().slice(0, 6000),
    ``,
    `The images are body photos. The context above says how many are from LAST week and`,
    `how many are from THIS week, and they are attached in that order — last week first.`,
    `Compare the two weeks against THEIR STATED GOAL. Cutting and gaining are not the same`,
    `win; read the goal before you judge the photos.`,
    ``,
    `- verdict: gaining (moving toward the goal) | holding (flat) | slipping (moving away)`,
    `  | unknown (you genuinely cannot tell).`,
    `- percent: signed, approximate change toward the goal versus last week, e.g. -1.8 for`,
    `  1.8% down when cutting is the goal is PROGRESS — sign it by the number that moved`,
    `  (weight, waist), not by whether it is good news. Small is fine; a real week is 0-3%.`,
    `  Lean on the logged weight when it exists — a photo alone cannot tell 1 kg from`,
    `  different lighting. If there is no photo in one of the two weeks, set percent 0,`,
    `  verdict unknown and needsPhotos true, and say so in read. Never invent a number.`,
    `- headline: one short line they will read first. Specific, not "Great work!".`,
    `- read: 2-4 sentences on what you actually SEE and what the numbers say. Name body`,
    `  parts plainly (belly, chest, arms, posture). If the belly is bigger, say the belly`,
    `  is bigger.`,
    `- workouts: 2-4 concrete things to focus on next week, named as real exercises or`,
    `  sessions (e.g. "3 x 30 min zone-2 walk after dinner", "weighted incline press 4x8").`,
    `- diet: 2-4 concrete targets in THEIR numbers (kcal, protein g, what to cut). Use the`,
    `  targets from the context when they exist instead of inventing new ones.`,
    `- cheer: speak to them directly. If they earned it, say so warmly and mean it. If they`,
    `  slipped, tell them straight — disappointed, not cruel, and never sarcastic. One or`,
    `  two sentences, their name if you know it.`,
    `- needsPhotos: true only when a week is missing photos to compare.`,
    ``,
    `Never flatter. Never pad. They asked to be told the truth.`
  ].join('\n');
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
  // An allowlist, not whatever the client says — this string is handed to the
  // provider.
  const ALLOWED_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif']);
  const asked = typeof body.mediaType === 'string' ? body.mediaType : 'image/png';
  const mediaType = ALLOWED_TYPES.has(asked) ? asked : 'image/png';
  const images: string[] = Array.isArray(body.images)
    ? body.images.filter((s: unknown) => typeof s === 'string' && s.length > 0).slice(0, 8)
    : [];
  if (!images.length) throw error(400, 'No image to read');
  // Eight images with no size check at all: the only bound was the Workers
  // request-body limit, and `Buffer.from(b64)` per image blew the isolate's
  // 128 MB before anything else could refuse it. ~24 MB of base64 is eight
  // generously-sized photos.
  const totalBase64 = images.reduce((n, s) => n + s.length, 0);
  if (totalBase64 > 24_000_000) throw error(413, 'Those images are too large');

  const mode = typeof body.mode === 'string' ? body.mode : 'food';
  const context = typeof body.context === 'string' ? body.context : '';
  // One table beats a fourth nested ternary. Unknown modes read a label, which is
  // what this route did before any of the others existed.
  const MODES: Record<string, { schema: z.ZodTypeAny; prompt: (c: string) => string }> = {
    scan: { schema: ScanResult, prompt: scanPrompt },
    belonging: { schema: BelongingResult, prompt: belongingPrompt },
    weekly: { schema: WeeklyResult, prompt: weeklyPrompt },
    food: { schema: FoodResult, prompt: () => foodPrompt() }
  };
  const { schema, prompt: buildPrompt } = MODES[mode] ?? MODES.food;
  const prompt = buildPrompt(context);

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
