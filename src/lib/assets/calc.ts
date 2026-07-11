// Pure cost-per-day / ROI / daily-burn math. No I/O — every function is a
// deterministic map from stored inputs (+ `today`) to derived figures, so the
// UI stays dumb and the whole model is unit-testable. Money is integer paise.
import type { Asset, AssetSettings, Period } from './types';

const DAY_MS = 86_400_000;

/** Integer ceiling of a/b for non-negative a and positive b (0 otherwise). */
export function ceilDiv(a: number, b: number): number {
	if (a <= 0 || b <= 0) return 0;
	return Math.floor((a + b - 1) / b);
}

function parseUTC(iso: string): number {
	const [y, m, d] = iso.split('-').map(Number);
	return Date.UTC(y, m - 1, d);
}

/** Whole calendar days from `fromIso` to `toIso` (DST-safe: both at UTC midnight). */
export function daysBetween(fromIso: string, toIso: string): number {
	return Math.round((parseUTC(toIso) - parseUTC(fromIso)) / DAY_MS);
}

export const PERIOD_DAYS: Record<Period, number> = {
	daily: 1,
	weekly: 7,
	monthly: 30,
	yearly: 365
};

/** days_remaining → "now" / "5 days" / "~3 months" / "~3.9 years" / "10+ years". */
export function humanDays(d: number): string {
	if (d <= 0) return 'now';
	if (d < 30) return `${d} day${d === 1 ? '' : 's'}`;
	if (d < 345) {
		const m = Math.round(d / 30);
		return `~${m} month${m === 1 ? '' : 's'}`;
	}
	if (d <= 3650) {
		const y = Math.round((d / 365) * 10) / 10;
		const label = Number.isInteger(y) ? String(y) : y.toFixed(1);
		return `~${label} year${y === 1 ? '' : 's'}`;
	}
	return '10+ years';
}

export type Band = 'good' | 'warning' | 'bad' | 'unset';

export interface AssetMetrics {
	asset: Asset;
	isLiability: boolean;
	retired: boolean;
	active: boolean; // contributes to daily burn right now
	daysOwned: number;
	netPricePaise: number; // price − salvage, floored at 0 (assets); 0 for liabilities
	costPerDayPaise: number; // current decaying cost/day (asset) or flat cost/day (liability)
	daysNeeded: number; // days to reach the "cheap" threshold (assets only)
	daysRemaining: number;
	isPaidOff: boolean;
	impliedTargetPaise: number; // effective ₹/day target the item is measured against
	progressPct: number; // 0..100 toward good ROI
	recoveredPaise: number; // how much of net price has "paid for itself"
	burnPaise: number; // steady amortized contribution to true daily burn
}

/** All derived figures for a single asset or liability, as of `today` (ISO date). */
export function assetMetrics(a: Asset, settings: AssetSettings, today: string): AssetMetrics {
	const retired = a.retired_on != null;

	if (a.kind === 'liability') {
		const periodDays = PERIOD_DAYS[a.billing_period ?? 'monthly'];
		const cpd = ceilDiv(a.price_paise, periodDays);
		const active = !retired && (a.end_date == null || today <= a.end_date);
		return {
			asset: a,
			isLiability: true,
			retired,
			active,
			daysOwned: Math.max(0, daysBetween(a.purchase_date, retired ? a.retired_on! : today)),
			netPricePaise: 0,
			costPerDayPaise: cpd,
			daysNeeded: 0,
			daysRemaining: 0,
			isPaidOff: false,
			impliedTargetPaise: 0,
			progressPct: 0,
			recoveredPaise: 0,
			burnPaise: active ? cpd : 0
		};
	}

	// --- Asset ---
	const end = retired ? a.retired_on! : today;
	const daysOwned = Math.max(1, daysBetween(a.purchase_date, end)); // bought today ⇒ 1
	const netPrice = Math.max(0, a.price_paise - a.salvage_value_paise);
	const cpd = ceilDiv(netPrice, daysOwned);

	// "Cheap" threshold resolution: per-item target > lifespan > global default.
	let daysNeeded: number;
	if (a.target_cost_per_day_paise) daysNeeded = ceilDiv(netPrice, a.target_cost_per_day_paise);
	else if (a.expected_lifespan_days) daysNeeded = a.expected_lifespan_days;
	else daysNeeded = ceilDiv(netPrice, settings.global_target_cpd_paise);
	daysNeeded = Math.max(0, daysNeeded);

	const daysRemaining = Math.max(0, daysNeeded - daysOwned);
	const isPaidOff = daysOwned >= daysNeeded;
	const impliedTarget = daysNeeded > 0 ? ceilDiv(netPrice, daysNeeded) : 0;
	const progressPct = daysNeeded === 0 ? 100 : Math.min(100, Math.floor((100 * daysOwned) / daysNeeded));
	const recovered = isPaidOff
		? netPrice
		: daysNeeded > 0
			? Math.floor((netPrice * daysOwned) / daysNeeded)
			: netPrice;

	// Amortized "true" contribution: a steady rate over the horizon, then released
	// to 0 once fully paid — the honest shape of a spending rate.
	const horizon = a.expected_lifespan_days ?? daysNeeded;
	const burn =
		retired || netPrice === 0 || horizon <= 0 || daysOwned > horizon ? 0 : ceilDiv(netPrice, horizon);

	return {
		asset: a,
		isLiability: false,
		retired,
		active: !retired,
		daysOwned,
		netPricePaise: netPrice,
		costPerDayPaise: cpd,
		daysNeeded,
		daysRemaining,
		isPaidOff,
		impliedTargetPaise: impliedTarget,
		progressPct,
		recoveredPaise: recovered,
		burnPaise: burn
	};
}

export interface Dashboard {
	items: AssetMetrics[]; // sorted worst-first
	trueDailyBurnPaise: number; // headline: amortized burn (assets) + flat liabilities
	currentOwnershipPaise: number; // secondary: decaying cost-of-ownership, "and falling"
	assetBurnPaise: number; // split chip: amortized asset burn
	liabilityBurnPaise: number; // split chip: liabilities
	recoveredPaise: number;
	basisPaise: number; // total net price of non-retired assets
	dailyIncomePaise: number;
	burnPct: number | null; // null when income unset
	leftoverPaise: number;
	band: Band;
}

function classifyBand(burnPct: number | null): Band {
	if (burnPct == null) return 'unset';
	if (burnPct <= 30) return 'good';
	if (burnPct <= 50) return 'warning';
	return 'bad';
}

// Worst-first: unpaid assets, then active liabilities, then paid-off assets,
// then retired — each bucket by current cost/day, highest first.
function sortRank(m: AssetMetrics): number {
	if (m.retired) return 3;
	if (m.isLiability) return 1;
	return m.isPaidOff ? 2 : 0;
}

export function dashboard(assets: Asset[], settings: AssetSettings, today: string): Dashboard {
	const items = assets.map((a) => assetMetrics(a, settings, today));

	let assetBurn = 0;
	let liabilityBurn = 0;
	let ownership = 0;
	let recovered = 0;
	let basis = 0;
	for (const m of items) {
		if (m.isLiability) {
			liabilityBurn += m.burnPaise;
			if (m.active) ownership += m.costPerDayPaise;
		} else if (!m.retired) {
			assetBurn += m.burnPaise;
			ownership += m.costPerDayPaise;
			recovered += m.recoveredPaise;
			basis += m.netPricePaise;
		}
	}

	const trueDailyBurn = assetBurn + liabilityBurn;
	const dailyIncome =
		settings.income_amount_paise > 0
			? Math.floor(settings.income_amount_paise / PERIOD_DAYS[settings.income_period])
			: 0;
	const burnPct = dailyIncome > 0 ? Math.floor((100 * trueDailyBurn) / dailyIncome) : null;

	items.sort((x, y) => sortRank(x) - sortRank(y) || y.costPerDayPaise - x.costPerDayPaise);

	return {
		items,
		trueDailyBurnPaise: trueDailyBurn,
		currentOwnershipPaise: ownership,
		assetBurnPaise: assetBurn,
		liabilityBurnPaise: liabilityBurn,
		recoveredPaise: recovered,
		basisPaise: basis,
		dailyIncomePaise: dailyIncome,
		burnPct,
		leftoverPaise: dailyIncome - trueDailyBurn,
		band: classifyBand(burnPct)
	};
}
