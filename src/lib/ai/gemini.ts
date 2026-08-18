import { env } from '$env/dynamic/public';
import {
	CATEGORIZE_SYSTEM,
	extractJson,
	parseCategorizedEvent,
	resolveRelativeDate,
	type CategorizedEvent
} from './categorize';
import { SCAN_SYSTEM, parseScanResult, type ScanResult } from './scan';

export const GEMINI_MODEL = 'gemini-3.1-flash-lite';
const KEY_STORAGE = 'myos:gemini-key';
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

export function getGeminiKey(): string {
	if (typeof localStorage !== 'undefined') {
		const stored = localStorage.getItem(KEY_STORAGE)?.trim();
		if (stored) return stored;
	}
	return env.PUBLIC_GEMINI_API_KEY?.trim() ?? '';
}

export function setGeminiKey(key: string): void {
	if (typeof localStorage === 'undefined') return;
	const v = key.trim();
	if (v) localStorage.setItem(KEY_STORAGE, v);
	else localStorage.removeItem(KEY_STORAGE);
}

export function hasGeminiKey(): boolean {
	return getGeminiKey().length > 0;
}

type Part = { text: string } | { inline_data: { mime_type: string; data: string } };

async function generateJson(parts: Part[]): Promise<unknown> {
	const key = getGeminiKey();
	if (!key) throw new Error('Add a Gemini API key in Today → Settings.');
	const res = await fetch(`${ENDPOINT}?key=${encodeURIComponent(key)}`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			contents: [{ parts }],
			generationConfig: { responseMimeType: 'application/json', temperature: 0.2 }
		})
	});
	if (!res.ok) {
		const body = await res.text().catch(() => '');
		throw new Error(body.slice(0, 180) || `Gemini ${res.status}`);
	}
	const json = (await res.json()) as {
		candidates?: { content?: { parts?: { text?: string }[] } }[];
	};
	const text = json.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('') ?? '';
	const parsed = extractJson(text);
	if (parsed == null) throw new Error('Gemini returned no JSON');
	return parsed;
}

export async function categorizeEvent(text: string, today: string): Promise<CategorizedEvent> {
	const spoken = text.trim();
	if (!spoken) throw new Error('Nothing to add.');
	try {
		const raw = await generateJson([
			{ text: `${CATEGORIZE_SYSTEM}\n\nTODAY=${today}\nEVENT=${spoken}` }
		]);
		return parseCategorizedEvent(raw, today, spoken);
	} catch (err) {
		if (!hasGeminiKey()) throw err;
		// Offline / API blip: still capture as a dated todo so Siri/voice never drops the event.
		return parseCategorizedEvent(
			{ kind: 'todo', title: spoken, date: resolveRelativeDate(spoken, today) },
			today,
			spoken
		);
	}
}

function dataUrlToInline(dataUrl: string): { mime_type: string; data: string } {
	const m = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
	if (!m) throw new Error('Could not read the photo');
	return { mime_type: m[1], data: m[2] };
}

export async function analyzeImage(dataUrl: string): Promise<ScanResult> {
	const inline = dataUrlToInline(dataUrl);
	const raw = await generateJson([
		{ text: SCAN_SYSTEM },
		{ inline_data: inline }
	]);
	return parseScanResult(raw);
}

export async function decideJson(prompt: string): Promise<unknown> {
	return generateJson([{ text: prompt }]);
}
