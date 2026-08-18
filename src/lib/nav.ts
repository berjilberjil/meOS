import type { Component } from 'svelte';
import CalendarDays from '@lucide/svelte/icons/calendar-days';
import ScanLine from '@lucide/svelte/icons/scan-line';
import Wallet from '@lucide/svelte/icons/wallet';
import NotebookPen from '@lucide/svelte/icons/notebook-pen';
import ListChecks from '@lucide/svelte/icons/list-checks';
import Target from '@lucide/svelte/icons/target';
import HeartPulse from '@lucide/svelte/icons/heart-pulse';
import Dumbbell from '@lucide/svelte/icons/dumbbell';
import StickyNote from '@lucide/svelte/icons/sticky-note';
import Waypoints from '@lucide/svelte/icons/waypoints';
import SquareStack from '@lucide/svelte/icons/square-stack';
import Activity from '@lucide/svelte/icons/activity';
import Gauge from '@lucide/svelte/icons/gauge';

export interface NavMenuItem {
	label: string;
	href: string;
}

export interface NavItem {
	key: string;
	href: string;
	label: string;
	icon: Component;
	// Extra path prefixes that should also mark this item active (for grouped tabs).
	match?: string[];
	// Long-press fan menu: slide up + release to pick a sub-page / quick action.
	menu?: NavMenuItem[];
}

// Single source of truth for navigation + map iconography, so the shell and the
// life map read as one system (same icon per module in both places).
// Journal / Notes / To-dos / Goals are grouped under one "Workspace" tab.

/** Elevated center button. Journaling is the landing, so Today is opt-in. */
export const DASHBOARD: NavItem = {
	key: 'dashboard',
	href: '/dashboard',
	label: 'Today',
	icon: CalendarDays
};

/** Tabs left of the elevated center button. */
export const NAV_LEFT: NavItem[] = [
	{
		key: 'finance',
		href: '/finance',
		label: 'Finance',
		icon: Wallet,
		menu: [
			{ label: 'Transactions', href: '/finance/transactions' },
			{ label: 'Recurring', href: '/finance/recurring' },
			{ label: 'Accounts', href: '/finance/accounts' },
			{ label: 'Budgets', href: '/finance/budgets' },
			{ label: 'Goals', href: '/finance/goals' },
			{ label: 'Investments', href: '/finance/investments' }
		]
	},
	{
		key: 'workspace',
		href: '/journal',
		label: 'Workspace',
		icon: SquareStack,
		// /todos & /goals stay matched so Workspace highlights on those deep pages,
		// but capture now happens inline via the editor's "/" slash menu.
		match: ['/journal', '/notes', '/todos', '/goals'],
		menu: [
			{ label: 'New journal', href: '/journal/new' },
			{ label: 'New note', href: '/notes/new' }
		]
	}
];

/** Tabs right of the elevated center button. */
export const NAV_RIGHT: NavItem[] = [
	{
		key: 'scan',
		href: '/scan',
		label: 'Scan',
		icon: ScanLine
	},
	{
		key: 'fitness',
		href: '/fitness',
		label: 'Fitness',
		icon: Activity,
		match: ['/fitness', '/health'],
		menu: [
			{ label: 'Log food', href: '/fitness/food' },
			{ label: 'Diet plan', href: '/fitness/diet' },
			{ label: 'Start workout', href: '/fitness/workouts' },
			{ label: 'Add photo', href: '/fitness?add=photo' }
		]
	},
	{
		key: 'assets',
		href: '/assets',
		label: 'Assets',
		icon: Gauge,
		// Belongings (inventory) + Assets (ROI / liabilities) live under one tab.
		match: ['/assets', '/belongings'],
		menu: [
			{ label: 'Add asset', href: '/assets?add=asset' },
			{ label: 'Add liability', href: '/assets?add=liability' },
			{ label: 'Add purchase', href: '/belongings?add=purchase' },
			{ label: 'Add wardrobe', href: '/belongings?add=wardrobe' }
		]
	}
];

/** Lives in the top bar, not the bottom dock. */
export const LIFE_MAP: NavItem = { key: 'mindmap', href: '/mindmap', label: 'Life map', icon: Waypoints };

/** Full bottom-dock order (left · center · right), for active-state lookups. */
export const NAV: NavItem[] = [...NAV_LEFT, DASHBOARD, ...NAV_RIGHT];

// Icon per mindmap module key (graph.ts MODULES keys).
export const MODULE_ICONS: Record<string, Component> = {
	finance: Wallet,
	journal: NotebookPen,
	todos: ListChecks,
	goals: Target,
	health: HeartPulse,
	fitness: Dumbbell,
	notes: StickyNote
};
