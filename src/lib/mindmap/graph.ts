import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export interface ModuleNode {
	key: string;
	label: string;
	href: string;
	count: number;
}

const MODULES: { key: string; label: string; href: string; tables: string[] }[] = [
	{ key: 'finance', label: 'Finance', href: '/finance', tables: ['accounts', 'transactions'] },
	{ key: 'journal', label: 'Journal', href: '/journal', tables: ['journal_entries'] },
	{ key: 'todos', label: 'To-dos', href: '/todos', tables: ['todos'] },
	{ key: 'goals', label: 'Goals', href: '/goals', tables: ['goals'] },
	{ key: 'health', label: 'Health', href: '/fitness', tables: ['health_logs'] },
	{ key: 'fitness', label: 'Fitness', href: '/fitness', tables: ['fitness_logs'] },
	{ key: 'notes', label: 'Notes', href: '/notes', tables: ['notes'] }
];

async function countTable(table: string): Promise<number> {
	const { count, error } = await db().from(table).select('*', { count: 'exact', head: true });
	if (error) return 0;
	return count ?? 0;
}

export async function moduleNodes(): Promise<ModuleNode[]> {
	return Promise.all(
		MODULES.map(async (m) => {
			const counts = await Promise.all(m.tables.map(countTable));
			return { key: m.key, label: m.label, href: m.href, count: counts.reduce((a, b) => a + b, 0) };
		})
	);
}

export type Vitality = 'good' | 'warn' | 'bad';

export interface ModuleVital extends ModuleNode {
	level: number; // 0..1 fill
	state: Vitality;
}

// Soft "full tank" target per module — how much activity reads as a thriving area.
const VITAL_TARGETS: Record<string, number> = {
	finance: 30,
	journal: 10,
	todos: 12,
	goals: 6,
	health: 14,
	fitness: 12,
	notes: 10
};

// Liquid life-tanks: each module's fill + state from its activity vs target.
// Full = water (thriving), mid = fuel (topping up), near-empty = fire (needs you).
export async function moduleVitals(): Promise<ModuleVital[]> {
	const nodes = await moduleNodes();
	return nodes.map((n) => {
		const target = VITAL_TARGETS[n.key] ?? 10;
		const level = Math.max(0, Math.min(1, n.count / target));
		const state: Vitality = level < 0.18 ? 'bad' : level < 0.5 ? 'warn' : 'good';
		return { ...n, level, state };
	});
}

export interface ModuleChild {
	label: string;
	href: string;
}

// Sub-areas revealed when a module node is expanded in the life map. These are
// real facets of each module; clicking one navigates into that module.
export const MODULE_CHILDREN: Record<string, ModuleChild[]> = {
	finance: [
		{ label: 'Accounts', href: '/finance' },
		{ label: 'Transactions', href: '/finance' },
		{ label: 'Budgets', href: '/finance' },
		{ label: 'Savings', href: '/finance' },
		{ label: 'Investments', href: '/finance' }
	],
	journal: [
		{ label: 'Entries', href: '/journal' },
		{ label: 'By mood', href: '/journal' }
	],
	todos: [
		{ label: 'Active', href: '/todos' },
		{ label: 'Completed', href: '/todos' }
	],
	goals: [
		{ label: 'In progress', href: '/goals' },
		{ label: 'Achieved', href: '/goals' }
	],
	health: [
		{ label: 'Daily logs', href: '/fitness' },
		{ label: 'Trends', href: '/fitness' }
	],
	fitness: [
		{ label: 'Workouts', href: '/fitness' },
		{ label: 'History', href: '/fitness' }
	],
	notes: [
		{ label: 'Pinned', href: '/notes' },
		{ label: 'All', href: '/notes' }
	]
};

export interface GraphLink {
	id: string;
	source_type: string;
	source_id: string;
	relation: string;
	target_type: string;
	target_id: string;
}

// Any accumulated cross-entity links (the mindmap backbone).
export async function entityLinks(): Promise<GraphLink[]> {
	const { data, error } = await db().from('links').select('*').limit(200);
	if (error) return [];
	return (data ?? []) as GraphLink[];
}
