import { describe, it, expect } from 'vitest';
import {
	ceilDiv,
	daysBetween,
	humanDays,
	assetMetrics,
	dashboard,
	PERIOD_DAYS
} from '$lib/assets/calc';
import type { Asset, AssetSettings } from '$lib/assets/types';

const SETTINGS: AssetSettings = {
	income_amount_paise: 6_000_000, // ₹60,000/month → ₹2,000/day
	income_period: 'monthly',
	global_target_cpd_paise: 1000 // ₹10/day
};
const TODAY = '2026-07-10';

function asset(p: Partial<Asset>): Asset {
	return {
		id: 'a',
		user_id: 'u',
		name: 'thing',
		kind: 'asset',
		price_paise: 0,
		purchase_date: TODAY,
		category: 'other',
		billing_period: null,
		end_date: null,
		expected_lifespan_days: null,
		target_cost_per_day_paise: null,
		salvage_value_paise: 0,
		retired_on: null,
		notes: null,
		created_at: '',
		updated_at: '',
		...p
	};
}

// purchase_date N days before TODAY
function daysAgo(n: number): string {
	const d = new Date(Date.UTC(2026, 6, 10) - n * 86_400_000);
	return d.toISOString().slice(0, 10);
}

describe('primitives', () => {
	it('ceilDiv rounds up, guards zero/negative', () => {
		expect(ceilDiv(30000, 60)).toBe(500);
		expect(ceilDiv(1420000, 1000)).toBe(1420);
		expect(ceilDiv(10, 3)).toBe(4);
		expect(ceilDiv(0, 5)).toBe(0);
		expect(ceilDiv(5, 0)).toBe(0);
	});
	it('daysBetween counts calendar days', () => {
		expect(daysBetween('2026-07-01', '2026-07-10')).toBe(9);
		expect(daysBetween('2026-07-10', '2026-07-10')).toBe(0);
		expect(daysBetween('2026-07-11', '2026-07-10')).toBe(-1); // future guard handled upstream
	});
	it('PERIOD_DAYS uses simple constants', () => {
		expect(PERIOD_DAYS).toEqual({ daily: 1, weekly: 7, monthly: 30, yearly: 365 });
	});
});

describe('humanDays', () => {
	it('phrases days / months / years', () => {
		expect(humanDays(0)).toBe('now');
		expect(humanDays(1)).toBe('1 day');
		expect(humanDays(23)).toBe('23 days');
		expect(humanDays(60)).toBe('~2 months');
		expect(humanDays(1419)).toBe('~3.9 years');
		expect(humanDays(365)).toBe('~1 year');
		expect(humanDays(4000)).toBe('10+ years');
	});
});

describe('assetMetrics — bottle (₹300, 60 days ago)', () => {
	const m = assetMetrics(asset({ price_paise: 30000, purchase_date: daysAgo(60) }), SETTINGS, TODAY);
	it('is ₹5/day and already paid off', () => {
		expect(m.daysOwned).toBe(60);
		expect(m.costPerDayPaise).toBe(500); // ₹5.00/day
		expect(m.daysNeeded).toBe(30); // 30000 / 1000
		expect(m.daysRemaining).toBe(0);
		expect(m.isPaidOff).toBe(true);
		expect(m.progressPct).toBe(100);
		expect(m.burnPaise).toBe(0); // fully amortized → releases from burn
	});
});

describe('assetMetrics — headphones (₹14,200, bought today)', () => {
	const m = assetMetrics(asset({ price_paise: 1420000, purchase_date: TODAY }), SETTINGS, TODAY);
	it('is ₹14,200/day on day 1 and ~3.9 years from cheap', () => {
		expect(m.daysOwned).toBe(1);
		expect(m.costPerDayPaise).toBe(1420000);
		expect(m.daysNeeded).toBe(1420);
		expect(m.daysRemaining).toBe(1419);
		expect(humanDays(m.daysRemaining)).toBe('~3.9 years');
		expect(m.isPaidOff).toBe(false);
		expect(m.progressPct).toBe(0);
		expect(m.burnPaise).toBe(1000); // amortized ≈ ₹10/day, not the ₹14,200 spike
	});
});

describe('assetMetrics — edge cases', () => {
	it('future purchase date clamps days_owned to 1', () => {
		const m = assetMetrics(asset({ price_paise: 100000, purchase_date: daysAgo(-5) }), SETTINGS, TODAY);
		expect(m.daysOwned).toBe(1);
	});
	it('salvage covering price makes it instantly paid off, zero burn', () => {
		const m = assetMetrics(
			asset({ price_paise: 50000, salvage_value_paise: 60000, purchase_date: daysAgo(10) }),
			SETTINGS,
			TODAY
		);
		expect(m.netPricePaise).toBe(0);
		expect(m.costPerDayPaise).toBe(0);
		expect(m.isPaidOff).toBe(true);
		expect(m.burnPaise).toBe(0);
	});
	it('per-item target overrides the global default', () => {
		const m = assetMetrics(
			asset({ price_paise: 1420000, target_cost_per_day_paise: 5000 }), // ₹50/day
			SETTINGS,
			TODAY
		);
		expect(m.daysNeeded).toBe(284); // 1420000 / 5000
	});
	it('expected lifespan drives amortized burn when set', () => {
		const m = assetMetrics(
			asset({ price_paise: 3650000, expected_lifespan_days: 3650, purchase_date: daysAgo(100) }),
			SETTINGS,
			TODAY
		);
		expect(m.burnPaise).toBe(1000); // 3,650,000 / 3650 = ₹10/day steady
	});
	it('retired items are frozen and excluded from burn', () => {
		const m = assetMetrics(
			asset({ price_paise: 200000, purchase_date: daysAgo(100), retired_on: daysAgo(10) }),
			SETTINGS,
			TODAY
		);
		expect(m.retired).toBe(true);
		expect(m.active).toBe(false);
		expect(m.daysOwned).toBe(90); // frozen at retirement, not 100
		expect(m.burnPaise).toBe(0);
	});
});

describe('assetMetrics — liability (Netflix ₹649/month)', () => {
	const m = assetMetrics(
		asset({ kind: 'liability', price_paise: 64900, billing_period: 'monthly', purchase_date: daysAgo(300) }),
		SETTINGS,
		TODAY
	);
	it('is a flat ₹21.64/day that never decays', () => {
		expect(m.isLiability).toBe(true);
		expect(m.costPerDayPaise).toBe(2164); // ceil(64900/30)
		expect(m.burnPaise).toBe(2164);
		expect(m.daysNeeded).toBe(0);
		expect(m.progressPct).toBe(0);
	});
	it('drops out of burn after its end_date', () => {
		const ended = assetMetrics(
			asset({ kind: 'liability', price_paise: 850000, billing_period: 'monthly', end_date: daysAgo(5) }),
			SETTINGS,
			TODAY
		);
		expect(ended.active).toBe(false);
		expect(ended.burnPaise).toBe(0);
	});
});

describe('dashboard — overspend headline', () => {
	const assets: Asset[] = [
		asset({ id: 'bottle', price_paise: 30000, purchase_date: daysAgo(60) }), // paid off, burn 0
		asset({ id: 'phones', price_paise: 1420000, purchase_date: TODAY }), // burn ₹10/day
		asset({ id: 'netflix', kind: 'liability', price_paise: 64900, billing_period: 'monthly' }) // ₹21.64/day
	];
	const d = dashboard(assets, SETTINGS, TODAY);

	it('headline true burn is amortized, not the purchase-day spike', () => {
		expect(d.assetBurnPaise).toBe(1000); // only the headphones amortized
		expect(d.liabilityBurnPaise).toBe(2164);
		expect(d.trueDailyBurnPaise).toBe(3164); // ₹31.64/day
	});
	it('current ownership shows the honest "and falling" spike', () => {
		// bottle ₹5 + phones ₹14,200 + netflix ₹21.64
		expect(d.currentOwnershipPaise).toBe(500 + 1420000 + 2164);
	});
	it('burn % vs ₹2,000/day income lands in the green band', () => {
		expect(d.dailyIncomePaise).toBe(200000); // ₹2,000/day
		expect(d.burnPct).toBe(1); // floor(100 * 3164 / 200000)
		expect(d.band).toBe('good');
		expect(d.leftoverPaise).toBe(200000 - 3164);
	});
	it('sorts worst-first: unpaid asset, liability, then paid-off asset', () => {
		expect(d.items.map((m) => m.asset.id)).toEqual(['phones', 'netflix', 'bottle']);
	});
	it('flags overspending when burn exceeds half of income', () => {
		const heavy = dashboard(
			[asset({ price_paise: 40000000, expected_lifespan_days: 20, purchase_date: TODAY })], // ₹2M/day burn
			SETTINGS,
			TODAY
		);
		expect(heavy.burnPct).toBeGreaterThan(50);
		expect(heavy.band).toBe('bad');
	});
	it('hides the ratio when income is unset', () => {
		const noIncome = dashboard(assets, { ...SETTINGS, income_amount_paise: 0 }, TODAY);
		expect(noIncome.burnPct).toBeNull();
		expect(noIncome.band).toBe('unset');
	});
});
