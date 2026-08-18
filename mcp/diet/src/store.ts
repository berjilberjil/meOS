import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import {
	addSlotFood,
	catalog,
	clearSlot,
	clearWeek,
	deleteLogItem,
	emptyNutrition,
	foodById,
	logFood,
	logPlannedMeal,
	normalizeMeal,
	planItems,
	removeSlotFood,
	searchFoods,
	setSlot,
	todayIso,
	totalsForItems,
	type NutritionState,
	weekdayFromDate
} from './plan';
import {
	isEnvelope,
	openValue,
	sealValue,
	unlockDek,
	unlockDekWithRecovery,
	type CryptoMeta
} from './crypto';

const LOCALS = ['http://127.0.0.1:17881', 'http://[::1]:17881'];
let localBase = LOCALS[0]!;

function env(name: string, fallback = ''): string {
	return (process.env[name] ?? fallback).trim();
}

function loadDotenv() {
	const path = new URL('../.env', import.meta.url);
	try {
		const text = readFileSync(path, 'utf8');
		for (const line of text.split('\n')) {
			const t = line.trim();
			if (!t || t.startsWith('#') || !t.includes('=')) continue;
			const i = t.indexOf('=');
			const k = t.slice(0, i).trim();
			const v = t.slice(i + 1).trim();
			if (!process.env[k]) process.env[k] = v;
		}
	} catch {
		/* optional */
	}
}

function mcpToken(): string {
	const fromEnv = env('MYOS_MCP_TOKEN');
	if (fromEnv) return fromEnv;
	const r = spawnSync('defaults', ['read', 'com.berjil.myos', 'myos.mcp.token'], { encoding: 'utf8' });
	return (r.stdout ?? '').trim();
}

async function local<T = unknown>(path: string, method = 'GET', body?: unknown): Promise<T> {
	const token = mcpToken();
	if (!token) throw new Error('no local token');
	const res = await fetch(localBase + path, {
		method,
		headers: {
			Authorization: `Bearer ${token}`,
			Accept: 'application/json',
			...(body ? { 'Content-Type': 'application/json' } : {})
		},
		body: body ? JSON.stringify(body) : undefined
	});
	const text = await res.text();
	let data: unknown = text;
	try {
		data = JSON.parse(text);
	} catch {
		/* raw */
	}
	if (!res.ok) throw new Error(typeof data === 'object' && data && 'error' in data ? String((data as { error: string }).error) : text);
	return data as T;
}

async function localUp(): Promise<boolean> {
	try {
		const token = mcpToken();
		if (!token) return false;
		for (const base of LOCALS) {
			try {
				const res = await fetch(base + '/health', { headers: { Authorization: `Bearer ${token}` } });
				if (res.ok) {
					localBase = base;
					return true;
				}
			} catch {
				/* try next */
			}
		}
		return false;
	} catch {
		return false;
	}
}

type Remote = { base: string; cookie: string; dek: Buffer };

async function connectRemote(): Promise<Remote> {
	const base = env('MYOS_BASE_URL', 'https://myos-berjil.netlify.app').replace(/\/$/, '');
	const user = env('MYOS_USERNAME', 'berjil');
	const pass = env('MYOS_PASSWORD');
	const phrase = env('MYOS_VAULT_PASSPHRASE');
	const recovery = env('MYOS_VAULT_RECOVERY');
	if (!pass) throw new Error('Mac app is not running. Set MYOS_PASSWORD + MYOS_VAULT_PASSPHRASE in mcp/diet/.env, or open native MyOS on this Mac.');
	const login = await fetch(base + '/api/auth/login', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
		body: JSON.stringify({ username: user, password: pass })
	});
	if (!login.ok) throw new Error(`login failed (${login.status})`);
	const cookie = login.headers.getSetCookie?.().join('; ') ?? login.headers.get('set-cookie') ?? '';
	const raw = await (await fetch(base + '/api/state', { headers: { Accept: 'application/json', Cookie: cookie } })).json();
	const meta = raw['myos.crypto'] as CryptoMeta | undefined;
	if (!meta) throw new Error('no vault on this account');
	const dek = phrase
		? await unlockDek(meta, phrase)
		: recovery
			? await unlockDekWithRecovery(meta, recovery)
			: (() => {
					throw new Error('Set MYOS_VAULT_PASSPHRASE (or MYOS_VAULT_RECOVERY)');
				})();
	return { base, cookie, dek };
}

function decodeKey(raw: Record<string, unknown>, dek: Buffer, key: string): unknown {
	const v = raw[key];
	if (isEnvelope(v)) return JSON.parse(openValue(v, dek, key).toString('utf8'));
	return v ?? null;
}

async function remoteNutrition(r: Remote): Promise<{ raw: Record<string, unknown>; nutrition: NutritionState }> {
	const res = await fetch(r.base + '/api/state', { headers: { Accept: 'application/json', Cookie: r.cookie } });
	const raw = (await res.json()) as Record<string, unknown>;
	const n = (decodeKey(raw, r.dek, 'myos.nutrition') as NutritionState) ?? emptyNutrition();
	n.customFoods ??= [];
	n.log ??= {};
	n.mealPlan ??= {};
	return { raw, nutrition: n };
}

async function putNutrition(r: Remote, n: NutritionState): Promise<void> {
	const envl = sealValue(Buffer.from(JSON.stringify(n)), r.dek, 'myos.nutrition');
	const res = await fetch(r.base + '/api/state/myos.nutrition', {
		method: 'PUT',
		headers: { 'Content-Type': 'application/json', Cookie: r.cookie },
		body: JSON.stringify(envl)
	});
	if (!res.ok) throw new Error(`put nutrition failed (${res.status})`);
}

export async function createStore() {
	loadDotenv();

	const useLocal = async () => localUp();

	return {
		async getContext() {
			if (await useLocal()) return local('/context', 'GET');
			const r = await connectRemote();
			const { raw, nutrition } = await remoteNutrition(r);
			const profile = decodeKey(raw, r.dek, 'myos.profile') as Record<string, unknown> | null;
			const fp = decodeKey(raw, r.dek, 'myos.fitnessProfile') as Record<string, unknown> | null;
			const date = todayIso();
			const wd = weekdayFromDate(date);
			const todayItems = ['breakfast', 'lunch', 'dinner', 'snacks'].flatMap((m) =>
				planItems(nutrition, wd, m)
			);
			return {
				date,
				weekday: wd,
				profile,
				goals: fp,
				today_plan: { weekday: wd, totals: totalsForItems(todayItems, nutrition.customFoods) }
			};
		},
		async getWeekPlan() {
			if (await useLocal()) return local('/week', 'GET');
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			const days = ['0', '1', '2', '3', '4', '5', '6'].map((wd) => {
				const meals: Record<string, unknown> = {};
				const items = ['breakfast', 'lunch', 'dinner', 'snacks'].flatMap((m) => {
					const rows = planItems(nutrition, wd, m);
					meals[m] = rows.map((it) => ({
						...it,
						food_id: it.foodId,
						name: foodById(it.foodId, nutrition.customFoods)?.name ?? 'unknown'
					}));
					return rows;
				});
				return { weekday: Number(wd), totals: totalsForItems(items, nutrition.customFoods), meals };
			});
			return { weekdays: '0=Sun … 6=Sat', days };
		},
		async getDayLog(date: string) {
			if (await useLocal()) return local(`/day?date=${encodeURIComponent(date)}`, 'GET');
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			const day = nutrition.log[date] ?? { meals: {}, skipped: [] };
			return { date, ...day };
		},
		async searchFoods(query: string, limit = 12) {
			if (await useLocal()) return local(`/foods?q=${encodeURIComponent(query)}&limit=${limit}`, 'GET');
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			return searchFoods(query, limit, nutrition.customFoods).map((f) => ({
				id: f.id,
				name: f.name,
				category: f.category,
				serving: f.servingLabel,
				kcal: f.perServing.calories,
				protein: f.perServing.protein
			}));
		},
		async listRecentFoods(limit = 10) {
			if (await useLocal()) {
				const ctx = (await local('/context', 'GET')) as { date?: string };
				const day = (await local(`/day?date=${encodeURIComponent(ctx.date ?? todayIso())}`, 'GET')) as {
					meals?: Record<string, Array<{ food_id?: string; foodId?: string }>>;
				};
				const ids: string[] = [];
				for (const items of Object.values(day.meals ?? {})) {
					for (const it of items) {
						const id = it.food_id ?? it.foodId;
						if (id && !ids.includes(id)) ids.push(id);
					}
				}
				const foods = catalog();
				return ids
					.slice(0, limit)
					.map((id) => foods.find((f) => f.id === id))
					.filter(Boolean);
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			const seen: string[] = [];
			const dates = Object.keys(nutrition.log).sort().reverse();
			for (const d of dates) {
				for (const items of Object.values(nutrition.log[d]!.meals)) {
					for (const it of items) {
						if (!seen.includes(it.foodId)) seen.push(it.foodId);
						if (seen.length >= limit) break;
					}
				}
			}
			return seen.map((id) => foodById(id, nutrition.customFoods)).filter(Boolean);
		},
		async setSlot(input: { weekday?: number; date?: string; meal: string; foods: Array<{ food_id: string; quantity: number }> }) {
			if (await useLocal()) {
				await local('/slot', 'POST', { weekday: input.weekday, date: input.date, meal: input.meal, foods: input.foods });
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			const wd = input.weekday != null ? String(input.weekday) : weekdayFromDate(input.date ?? todayIso());
			await putNutrition(
				r,
				setSlot(
					nutrition,
					wd,
					input.meal,
					input.foods.map((f) => ({ foodId: f.food_id, quantity: f.quantity }))
				)
			);
			return { ok: true };
		},
		async addSlotFood(input: { weekday?: number; date?: string; meal: string; food_id: string; quantity: number }) {
			if (await useLocal()) {
				await local('/slot/add', 'POST', input);
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			const wd = input.weekday != null ? String(input.weekday) : weekdayFromDate(input.date ?? todayIso());
			await putNutrition(r, addSlotFood(nutrition, wd, input.meal, input.food_id, input.quantity));
			return { ok: true };
		},
		async removeSlotFood(id: string) {
			if (await useLocal()) {
				await local('/slot/remove', 'POST', { id });
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			await putNutrition(r, removeSlotFood(nutrition, id));
			return { ok: true };
		},
		async clearSlot(input: { weekday?: number; date?: string; meal: string }) {
			if (await useLocal()) {
				await local('/slot/clear', 'POST', input);
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			const wd = input.weekday != null ? String(input.weekday) : weekdayFromDate(input.date ?? todayIso());
			await putNutrition(r, clearSlot(nutrition, wd, input.meal));
			return { ok: true };
		},
		async clearWeek() {
			if (await useLocal()) {
				await local('/week/clear', 'POST', {});
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			await putNutrition(r, clearWeek(nutrition));
			return { ok: true };
		},
		async logFood(input: { food_id: string; quantity: number; meal: string; logged_on?: string }) {
			if (await useLocal()) {
				await local('/log', 'POST', input);
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			await putNutrition(r, logFood(nutrition, input.logged_on ?? todayIso(), input.meal, input.food_id, input.quantity));
			return { ok: true };
		},
		async logPlannedMeal(input: { meal: string; date?: string; weekday?: number }) {
			if (await useLocal()) {
				await local('/log/planned', 'POST', input);
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			const date = input.date ?? todayIso();
			const wd = input.weekday != null ? String(input.weekday) : weekdayFromDate(date);
			await putNutrition(r, logPlannedMeal(nutrition, date, wd, input.meal));
			return { ok: true };
		},
		async deleteLog(id: string) {
			if (await useLocal()) {
				await local('/log/delete', 'POST', { id });
				return { ok: true };
			}
			const r = await connectRemote();
			const { nutrition } = await remoteNutrition(r);
			await putNutrition(r, deleteLogItem(nutrition, id));
			return { ok: true };
		},
		async upsertFood(input: {
			name: string;
			category?: string;
			serving_label?: string;
			energy_kcal: number;
			protein_g?: number;
			carb_g?: number;
			fat_g?: number;
			fiber_g?: number;
		}) {
			if (await useLocal()) return local('/food', 'POST', input);
			throw new Error('upsert_food needs the Mac app running (open native MyOS)');
		},
		async setGoals(input: { energy_kcal?: number | null; protein_g?: number | null }) {
			if (await useLocal()) {
				await local('/goals', 'POST', input);
				return { ok: true };
			}
			throw new Error('set_goals needs the Mac app running (open native MyOS)');
		},
		async ping() {
			const localOk = await useLocal();
			return { native: true, bridge: localOk ? 'mac-local' : 'remote-vault' };
		}
	};
}

export type DietStore = Awaited<ReturnType<typeof createStore>>;
