import { SupabaseRepository } from '$lib/data/repository';
import { extractText } from '$lib/journal/text';
import type { JournalDoc } from '$lib/journal/types';

export interface Note {
	id: string;
	user_id: string;
	title: string;
	body_json: JournalDoc;
	body_text: string;
	pinned: boolean;
	created_at: string;
	updated_at: string;
}

export const notesRepo = new SupabaseRepository<Note>('notes');

export async function listNotes(): Promise<Note[]> {
	const notes = await notesRepo.list();
	return notes.sort((a, b) => {
		if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
		return b.updated_at.localeCompare(a.updated_at);
	});
}

export interface NoteInput {
	id?: string;
	title: string;
	body_json: JournalDoc;
	pinned: boolean;
}

export async function createNote(input: NoteInput): Promise<Note> {
	return notesRepo.create({
		id: input.id ?? crypto.randomUUID(),
		title: input.title,
		body_json: input.body_json,
		body_text: extractText(input.body_json),
		pinned: input.pinned
	} as Partial<Note>);
}

export async function updateNote(id: string, input: NoteInput): Promise<Note> {
	return notesRepo.update(id, {
		title: input.title,
		body_json: input.body_json,
		body_text: extractText(input.body_json),
		pinned: input.pinned
	} as Partial<Note>);
}
