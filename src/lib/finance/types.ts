export type AccountType = 'bank' | 'cash' | 'upi' | 'credit_card' | 'wallet';
export type CategoryKind = 'expense' | 'income';
export type TxnType = 'income' | 'expense' | 'transfer';
export type RecurringKind = 'income' | 'expense' | 'subscription';
export type Cadence = 'monthly' | 'weekly' | 'custom';
export type InvestmentType = 'sip' | 'mutual_fund' | 'stock' | 'other';

export interface Account {
	id: string;
	user_id: string;
	name: string;
	type: AccountType;
	opening_balance_paise: number;
	balance_paise: number;
	currency: string;
	archived: boolean;
	created_at: string;
	updated_at: string;
}

export interface Category {
	id: string;
	user_id: string;
	name: string;
	kind: CategoryKind;
	icon: string | null;
	color: string | null;
	monthly_budget_paise: number;
	created_at: string;
	updated_at: string;
}

export interface Transaction {
	id: string;
	user_id: string;
	account_id: string;
	category_id: string | null;
	type: TxnType;
	amount_paise: number;
	transfer_account_id: string | null;
	note: string | null;
	occurred_on: string; // 'YYYY-MM-DD'
	recurring_id: string | null;
	created_at: string;
	updated_at: string;
}

export interface Recurring {
	id: string;
	user_id: string;
	kind: RecurringKind;
	name: string;
	amount_paise: number;
	account_id: string;
	category_id: string | null;
	cadence: Cadence;
	interval_days: number | null;
	next_run_on: string; // 'YYYY-MM-DD'
	active: boolean;
	vendor: string | null;
	plan: string | null;
	renews_on: string | null;
	investment_id: string | null;
	created_at: string;
	updated_at: string;
}

export interface SavingsGoal {
	id: string;
	user_id: string;
	name: string;
	target_paise: number;
	saved_paise: number;
	deadline: string | null;
	account_id: string | null;
	created_at: string;
	updated_at: string;
}

export interface Investment {
	id: string;
	user_id: string;
	name: string;
	type: InvestmentType;
	invested_paise: number;
	current_value_paise: number;
	sip_amount_paise: number | null;
	sip_day: number | null;
	created_at: string;
	updated_at: string;
}
