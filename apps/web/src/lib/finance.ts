// Shared finance vocabulary + prompt building blocks for the AI routes
// (parse, parse-image, advise). One source of truth so the Swift picker,
// the text parser, and the screenshot reader all agree on categories.

// Spending / income categories. The Swift app mirrors this exact list in
// Support/Models.swift (Categories.all). Keep them in sync.
export const CATEGORIES = [
  'food', // eating out, restaurants, swiggy/zomato, cafe, tea
  'groceries', // supermarket, vegetables, provisions, milk
  'transport', // daily auto/bus/metro/petrol, short Ola/Uber
  'travel', // trips, flights, trains, hotels, long-distance cabs
  'shopping', // clothes, footwear, general retail, apparel
  'gadgets', // electronics, phone, accessories, chargers
  'health', // medicines, doctor, pharmacy, hospital
  'fitness', // gym, supplements, protein, sports
  'bills', // electricity, water, mobile recharge, internet, DTH
  'rent', // house rent
  'subscriptions', // OTT, Spotify, SaaS, memberships
  'entertainment', // movies, games, outings, events
  'education', // courses, books, tuition
  'editor', // ₹500/reel video editor
  'family', // money given to parents/family
  'loan', // loan / EMI payment (gold loan, personal loan, etc.)
  'investment', // money moved into SIP / stocks / MF / gold / FD
  'salary', // monthly salary (income)
  'freelance', // side/freelance income
  'refund', // money returned / refunded (income)
  'misc'
] as const;

export const CATEGORY_HINTS = [
  '"auto"/"bus"/"metro"/"petrol"/short Ola-Uber -> transport; a trip/flight/train/hotel -> travel',
  '"swiggy"/"zomato"/restaurant/tea/cafe -> food; supermarket/vegetables/milk -> groceries',
  'clothes/footwear/apparel -> shopping; phone/electronics/accessories -> gadgets',
  'medicine/doctor/pharmacy -> health; gym/protein/supplement -> fitness',
  'electricity/recharge/wifi/DTH -> bills; Netflix/Spotify/SaaS -> subscriptions',
  'movie/game/outing -> entertainment; course/book/tuition -> education',
  '"reel editor" -> editor; "gold loan"/"emi" -> loan; SIP/stocks/MF/FD/gold buy -> investment',
  'salary -> salary (income); freelance/gig -> freelance (income); refund/cashback returned -> refund (income)'
].join('. ');

// Spending-quality judgement. useless = avoidable/impulse, useful = needed for
// living, investment = builds future wealth / skills / health.
export const QUALITIES = ['useless', 'useful', 'investment'] as const;

export const QUALITY_HINTS = [
  'useless: impulse or avoidable — junk food, unnecessary shopping, an unused subscription, a want he could skip',
  'useful: a genuine need — groceries, rent, bills, daily transport, medicines, family support',
  'investment: builds future wealth, skills, health or income — the investment category, education/courses, fitness, tools/gadgets that earn, the reel editor (his content engine)'
].join(' | ');

// Holding types for portfolio screenshots. Mirrored in Swift HoldingType.
export const HOLDING_TYPES = ['stock', 'mutualFund', 'etf', 'gold', 'crypto', 'other'] as const;

// Generic money-coaching principles that ground every finance answer. These are
// universal — no person, no numbers. All personal facts (the user's actual loan,
// income, protection status) come from their live DATA snapshot at request time,
// never from this file.
export function financePrinciples(): string {
  return [
    `Money coaching principles — apply them to the user's ACTUAL numbers in their data snapshot; never`,
    `invent figures or assume a situation the data does not show:`,
    ``,
    `1. Clearing high-interest debt — especially costly secured debt (e.g. a loan against gold/assets) —`,
    `   usually beats new market investing. Interest saved is a guaranteed return; a SIP's return is not.`,
    `   If they carry expensive debt, prioritise killing it.`,
    `2. Protect first: adequate term life cover (if anyone depends on them), their own health insurance, and`,
    `   an emergency fund (a few months of expenses) come before discretionary investing.`,
    `3. Do NOT push new SIPs / equity while the emergency fund is missing AND expensive debt is large. If they`,
    `   are already investing in that situation, nudge them to redirect to protection + debt first.`,
    `4. The biggest lever is usually raising income, not shaving small expenses.`,
    ``,
    `Tone: a blunt mentor invested in them getting richer and healthier. No flattery — if a holding or habit`,
    `is wrong, say so. Use the currency shown in their data.`
  ].join('\n');
}
