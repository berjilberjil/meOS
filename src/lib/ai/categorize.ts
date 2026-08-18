import { addDays } from '$lib/today/today';

export const EVENT_KINDS = ['todo', 'finance', 'journal', 'fitness', 'note'] as const;
export type EventKind = (typeof EVENT_KINDS)[number];

export interface CategorizedEvent {
	kind: EventKind;
	title: string;
	date: string;
	category: string | null;
	amount_paise: number | null;
	priority: 0 | 1 | 2 | 3;
	notes: string | null;
}

export function extractJson(text: string): unknown {
	const trimmed = text.trim();
	const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
	const candidate = fenced ? fenced[1].trim() : trimmed;
	const start = candidate.indexOf('{');
	const end = candidate.lastIndexOf('}');
	if (start < 0 || end <= start) return null;
	try {
		return JSON.parse(candidate.slice(start, end + 1));
	} catch {
		return null;
	}
}

export function resolveRelativeDate(text: string, today: string): string {
	const lower = text.toLowerCase();
	const iso = text.match(/\d{4}-\d{2}-\d{2}/);
	if (iso) return iso[0];
	if (/\btomorrow\b/.test(lower)) return addDays(today, 1);
	if (/\btoday\b/.test(lower)) return today;
	return today;
}

function asKind(v: unknown): EventKind {
	return EVENT_KINDS.includes(v as EventKind) ? (v as EventKind) : 'todo';
}

function asPriority(v: unknown): 0 | 1 | 2 | 3 {
	const n = Number(v);
	if (n === 1 || n === 2 || n === 3) return n;
	return 0;
}

function asIsoDate(v: unknown, today: string): string {
	if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
	return today;
}

export function parseCategorizedEvent(
	raw: unknown,
	today: string,
	spoken?: string
): CategorizedEvent {
	const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	const title =
		(typeof o.title === 'string' && o.title.trim()) ||
		(spoken && spoken.trim()) ||
		'New item';
	return {
		kind: asKind(o.kind),
		title,
		date: asIsoDate(o.date, today),
		category: typeof o.category === 'string' && o.category.trim() ? o.category.trim() : null,
		amount_paise:
			typeof o.amount_paise === 'number' && Number.isFinite(o.amount_paise)
				? Math.round(o.amount_paise)
				: null,
		priority: asPriority(o.priority),
		notes: typeof o.notes === 'string' && o.notes.trim() ? o.notes.trim() : null
	};
}

export const CATEGORIZE_SYSTEM = `You classify a single spoken or typed life event for a personal OS.
Return ONLY JSON with this shape:
{
  "kind": "todo" | "finance" | "journal" | "fitness" | "note",
  "title": "short title",
  "date": "YYYY-MM-DD",
  "category": "finance category name or meal name or null",
  "amount_paise": number or null,
  "priority": 0 | 1 | 2 | 3,
  "notes": "optional extra or null"
}
Rules:
- kind=finance when it is money (spent, paid, earned, billed). amount_paise is integer paise (₹1 = 100).
- kind=fitness when it is a workout, run, lift, walk for exercise.
- kind=journal when they want to remember a feeling or a day, not a task.
- kind=note when it is a fact to keep, not actionable.
- otherwise kind=todo (appointments, errands, calls, deadlines).
- date: resolve relative words (today, tomorrow, next Friday) against TODAY.
- category: for finance pick one of Salary, Other income, Groceries, Rent, Food & dining, Transport, Bills & utilities, Subscriptions, Health, Investments, Shopping, Misc.
- priority 3 = must do, 2 = should, 1 = nice, 0 = none.`;
