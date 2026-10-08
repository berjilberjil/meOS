import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

/**
 * Client for the Stuff half of the Mac app's loopback bridge (127.0.0.1:17881).
 *
 * Unlike the diet MCP there is no remote/vault fallback here on purpose: the ROI
 * maths, the category guesser and the bill downscaling all live in Swift, and a
 * second implementation in TypeScript would be a second thing to keep correct.
 * So this needs native meOS open and unlocked, and says so plainly when it isn't.
 */

const LOCALS = ['http://127.0.0.1:17881', 'http://[::1]:17881'];
let base = LOCALS[0]!;

const CLOSED =
	'Native meOS is not running (or is locked). Open meOS on this Mac and unlock it, then try again.';

function token(): string {
	const fromEnv = (process.env.MEOS_MCP_TOKEN ?? '').trim();
	if (fromEnv) return fromEnv;
	const r = spawnSync('defaults', ['read', 'com.berjil.myos', 'myos.mcp.token'], { encoding: 'utf8' });
	return (r.stdout ?? '').trim();
}

async function call<T = unknown>(path: string, method = 'GET', body?: unknown): Promise<T> {
	const t = token();
	if (!t) throw new Error(CLOSED);
	let lastErr: unknown;
	for (const candidate of [base, ...LOCALS.filter((l) => l !== base)]) {
		try {
			const res = await fetch(candidate + path, {
				method,
				headers: {
					Authorization: `Bearer ${t}`,
					Accept: 'application/json',
					...(body ? { 'Content-Type': 'application/json' } : {})
				},
				body: body ? JSON.stringify(body) : undefined
			});
			base = candidate;
			const text = await res.text();
			let data: unknown = text;
			try {
				data = JSON.parse(text);
			} catch {
				/* raw */
			}
			if (!res.ok) {
				const msg =
					typeof data === 'object' && data && 'error' in data
						? String((data as { error: string }).error)
						: text;
				throw new Error(msg || `bridge ${res.status}`);
			}
			return data as T;
		} catch (e) {
			lastErr = e;
		}
	}
	// A connection refused means the app is closed; a real 4xx from the bridge
	// is the app talking, and that message is worth passing through.
	const msg = lastErr instanceof Error ? lastErr.message : String(lastErr);
	throw new Error(/fetch failed|ECONNREFUSED|Unable to connect/i.test(msg) ? CLOSED : msg);
}

/** A bill screenshot as base64, from a path on disk or an inline string. */
export function readBill(path?: string, inline?: string): string | undefined {
	if (inline && inline.trim()) return inline.trim();
	if (!path || !path.trim()) return undefined;
	try {
		return readFileSync(path.trim().replace(/^~/, process.env.HOME ?? '~')).toString('base64');
	} catch (e) {
		throw new Error(`Couldn't read the bill image at ${path}: ${(e as Error).message}`);
	}
}

export interface AddInput {
	name: string;
	link?: string;
	category?: string;
	price_inr?: number;
	bought_on?: string;
	roi_months?: number;
	note?: string;
	bill_image_base64?: string;
}

export const store = {
	health: () => call<{ ok: boolean; hydrated: boolean }>('/health'),
	summary: () => call<Record<string, unknown>>('/stuff/summary'),
	categories: () => call<{ categories: unknown[] }>('/stuff/categories'),
	list: (q: string, category: string, limit: number, includeRetired: boolean) =>
		call<{ items: unknown[] }>(
			`/stuff?q=${encodeURIComponent(q)}&category=${encodeURIComponent(category)}` +
				`&limit=${limit}&include_retired=${includeRetired}`
		),
	add: (input: AddInput) => call<{ item: unknown }>('/stuff', 'POST', input),
	update: (input: Record<string, unknown>) => call<{ item: unknown }>('/stuff/update', 'POST', input),
	remove: (id: string) => call<{ ok: boolean }>('/stuff/delete', 'POST', { id })
};
