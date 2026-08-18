// TipTap document JSON.
export type JournalDoc = Record<string, unknown>;

export interface JournalEntry {
	id: string;
	user_id: string;
	title: string;
	body_json: JournalDoc;
	body_text: string;
	mood: string | null;
	occurred_on: string; // 'YYYY-MM-DD'
	created_at: string;
	updated_at: string;
}

export const MOODS = ['great', 'good', 'okay', 'low', 'bad'] as const;
export type Mood = (typeof MOODS)[number];
