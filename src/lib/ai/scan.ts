export type Needed = 'yes' | 'no' | 'maybe';

export type ScanFood = {
	kind: 'food';
	name: string;
	serving: string;
	energy_kcal: number;
	protein_g: number;
	carb_g: number;
	fat_g: number;
	detail: string;
};

export type ScanObject = {
	kind: 'object';
	name: string;
	needed: Needed;
	why: string;
	useful: string;
};

export type ScanResult = ScanFood | ScanObject;

function num(v: unknown): number {
	const n = Number(v);
	return Number.isFinite(n) ? n : 0;
}

function str(v: unknown, fallback: string): string {
	return typeof v === 'string' && v.trim() ? v.trim() : fallback;
}

function needed(v: unknown): Needed {
	return v === 'yes' || v === 'no' || v === 'maybe' ? v : 'maybe';
}

export function parseScanResult(raw: unknown): ScanResult {
	const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	if (o.kind === 'food') {
		return {
			kind: 'food',
			name: str(o.name, 'Food'),
			serving: str(o.serving, '1 serving'),
			energy_kcal: Math.round(num(o.energy_kcal)),
			protein_g: num(o.protein_g),
			carb_g: num(o.carb_g),
			fat_g: num(o.fat_g),
			detail: str(o.detail, '')
		};
	}
	return {
		kind: 'object',
		name: str(o.name, 'Unknown object'),
		needed: needed(o.needed),
		why: str(o.why, 'Could not tell from the photo.'),
		useful: str(o.useful, '')
	};
}

export const SCAN_SYSTEM = `You analyze one photo for a personal life OS.
Decide if the main subject is edible food or some other object.
Return ONLY JSON.

If food:
{
  "kind": "food",
  "name": "common name",
  "serving": "what is in the photo, e.g. 1 plate / 1 cup",
  "energy_kcal": number,
  "protein_g": number,
  "carb_g": number,
  "fat_g": number,
  "detail": "1-2 sentences: what it is and a rough nutrition read"
}

If not food:
{
  "kind": "object",
  "name": "what it is",
  "needed": "yes" | "no" | "maybe",
  "why": "do I need this in a personal life (health, money, home, work)? be blunt",
  "useful": "how it could be useful if kept, or what to do instead"
}

needed=yes only if it clearly serves health, work, home, or money.
needed=no for junk, impulse gadgets, clutter.
Be specific to what is visible. Do not invent brands you cannot see.`;
