// Assets & liabilities: things you own (one-time price) and recurring costs.
// Money is integer paise everywhere. Derived figures live in calc.ts.

export type AssetKind = 'asset' | 'liability';
export type Period = 'daily' | 'weekly' | 'monthly' | 'yearly';

export interface Asset {
	id: string;
	user_id: string;
	name: string;
	kind: AssetKind;
	// asset: one-time price; liability: amount charged per `billing_period`.
	price_paise: number;
	purchase_date: string; // 'YYYY-MM-DD'
	category: string;
	billing_period: Period | null; // liabilities only
	end_date: string | null; // liabilities: EMI/contract end date
	expected_lifespan_days: number | null; // asset: optional amortization horizon
	target_cost_per_day_paise: number | null; // asset: optional per-item "cheap" threshold
	salvage_value_paise: number; // expected resale value; reduces the amount to amortize
	retired_on: string | null; // sold/binned; frozen + excluded from burn
	notes: string | null;
	created_at: string;
	updated_at: string;
}

export interface AssetSettings {
	income_amount_paise: number; // 0 = unset
	income_period: Period;
	global_target_cpd_paise: number; // app-wide "cheap" threshold, default ₹10/day
}

export const ASSET_CATEGORIES = [
	'electronics',
	'kitchen',
	'furniture',
	'clothing',
	'transport',
	'fitness',
	'other'
];

export const LIABILITY_CATEGORIES = ['subscription', 'emi', 'rent', 'insurance', 'other'];
