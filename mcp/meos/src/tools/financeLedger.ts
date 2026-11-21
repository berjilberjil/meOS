import { z } from 'zod';
import { STATE_KEYS } from '../schemas/models.ts';
import {
  makeAccount,
  makeAudit,
  makeInvestment,
  makeLiability,
  makeTransaction,
  normalizeFinance,
  type FinanceAccountType,
  type FinanceAssetClass,
  type FinanceDirection,
  type FinanceDocument,
  type FinanceInvestment,
  type FinanceLiability,
  type FinanceLiabilityKind,
  type FinancePaymentMethod,
  type FinanceSource,
  type FinanceTransaction,
  type FinanceTxnType,
  type FinanceVerification
} from '../schemas/finance.ts';
import {
  accountBalance,
  accountName,
  categoryName,
  expenseByCategory,
  formatInr,
  investmentSummaries,
  isExpense,
  isIncome,
  isInternalTransfer,
  isInvestmentFlow,
  liabilitySummaries,
  liquidAssets,
  merchantBreakdown,
  monthEnd,
  monthStart,
  monthTotals,
  netWorth,
  netWorthHistory,
  periodTotals,
  portfolio,
  timeline,
  toInr,
  totalAssets,
  totalLiabilities
} from '../services/financeEngine.ts';
import { assertDateKey, nowStamp, todayKey } from '../utils/dates.ts';
import { cleanText, requireId } from './shared.ts';
import { paginate } from '../utils/pagination.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import type { ToolDefinition, ToolContext } from './registry.ts';
import { newId } from '../utils/ids.ts';

const ACCOUNT_TYPES: readonly FinanceAccountType[] = [
  'savings', 'current', 'salary', 'cash', 'creditCard', 'wallet',
  'fixedDeposit', 'recurringDeposit', 'brokerage', 'investment', 'other'
];
const TXN_TYPES: readonly FinanceTxnType[] = [
  'income', 'expense', 'transfer', 'refund',
  'investmentPurchase', 'investmentSale', 'loanDisbursement', 'loanRepayment',
  'interest', 'dividend', 'fee', 'tax', 'adjustment'
];
const DIRECTIONS: readonly FinanceDirection[] = ['inflow', 'outflow'];
const PAYMENT_METHODS: readonly FinancePaymentMethod[] = [
  'upi', 'card', 'netBanking', 'cash', 'autoDebit', 'cheque', 'bankTransfer', 'other'
];
const SOURCES: readonly FinanceSource[] = ['manual', 'imported', 'recurring', 'demo', 'adjustment', 'migration'];
const VERIFICATIONS: readonly FinanceVerification[] = ['unverified', 'needsReview', 'verified', 'reconciled'];
const ASSET_CLASSES: readonly FinanceAssetClass[] = [
  'equity', 'mutualFund', 'etf', 'gold', 'silver',
  'fixedDeposit', 'recurringDeposit', 'bond', 'other'
];
const LIABILITY_KINDS: readonly FinanceLiabilityKind[] = [
  'creditCard', 'personalLoan', 'educationLoan', 'homeLoan',
  'goldLoan', 'vehicleLoan', 'informal', 'other'
];
const OWNERSHIPS = ['personal', 'household', 'shared'] as const;

const Money = z.union([z.number(), z.string()]).describe('Amount in rupees, e.g. 2499 or "₹2,499".');
const DateKey = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe('Civil date in Asia/Kolkata, yyyy-MM-dd.');
const CursorShape = {
  limit: z.number().int().min(1).max(100).optional(),
  cursor: z.string().optional()
};
const FINANCE_PLAINTEXT_LIMIT = 1_300_000;

function parseMoney(value: number | string | undefined, field: string, required = false): number | undefined {
  if (value === undefined) {
    if (required) throw errors.invalidInput(`${field} is required`);
    return undefined;
  }
  const text = typeof value === 'number' ? String(value) : String(value).replace(/[^0-9.-]/g, '');
  const n = Number(text);
  if (!Number.isFinite(n) || n < 0 || n > 1_000_000_000_000) {
    throw errors.invalidInput(`${field} must be a sensible positive amount`);
  }
  return Math.round(n * 100);
}

function cleanId(value: string, field = 'id'): string {
  return requireId(value, field);
}

async function readFinance(ctx: ToolContext): Promise<FinanceDocument> {
  const raw = await ctx.services.store.read<unknown>(STATE_KEYS.finance);
  return normalizeFinance(raw);
}

async function saveFinance(ctx: ToolContext, doc: FinanceDocument): Promise<void> {
  doc.updatedAt = nowStamp();
  const bytes = Buffer.byteLength(JSON.stringify(doc), 'utf8');
  if (bytes > FINANCE_PLAINTEXT_LIMIT) {
    throw errors.invalidInput(
      `This write would make the finance document ${bytes} bytes, above the ${FINANCE_PLAINTEXT_LIMIT}-byte sync guard. ` +
        'Export a backup and move to year-sharded storage before adding more history.'
    );
  }
  await ctx.services.store.write(STATE_KEYS.finance, doc);
}

function hasRecords(doc: FinanceDocument): boolean {
  return doc.accounts.length > 0 || doc.transactions.length > 0 || doc.investments.length > 0;
}

function txForClient(doc: FinanceDocument, t: FinanceTransaction): Record<string, unknown> {
  return {
    id: t.id,
    date: t.date,
    posted_date: t.postedDate ?? null,
    amount_paise: t.amountPaise,
    amount_inr: toInr(t.amountPaise),
    amount_formatted: formatInr(t.amountPaise),
    currency: t.currency,
    direction: t.direction,
    type: t.type,
    account_id: t.accountID,
    account: accountName(doc, t.accountID),
    transfer_account_id: t.transferAccountID ?? null,
    category_id: t.categoryID ?? null,
    category: categoryName(doc, t.categoryID),
    merchant: t.merchant,
    payment_method: t.paymentMethod,
    note: t.note,
    reference: t.reference,
    tags: t.tags,
    source: t.source,
    verification: t.verification,
    transfer_id: t.transferID ?? null,
    linked_transaction_id: t.linkedTransactionID ?? null,
    investment_id: t.investmentID ?? null,
    liability_id: t.liabilityID ?? null,
    principal_paise: t.principalPaise ?? null,
    interest_paise: t.interestPaise ?? null,
    cost_basis_paise: t.costBasisPaise ?? null,
    realised_gain_paise: t.realisedGainPaise ?? null,
    is_demo: t.isDemo,
    is_income: isIncome(t),
    is_expense: isExpense(t),
    is_transfer: isInternalTransfer(t),
    is_investment_flow: isInvestmentFlow(t),
    created_at: t.createdAt,
    updated_at: t.updatedAt
  };
}

function defaultDirection(type: FinanceTxnType, supplied?: FinanceDirection): FinanceDirection {
  if (supplied) return supplied;
  if (['income', 'refund', 'investmentSale', 'loanDisbursement', 'interest', 'dividend'].includes(type)) return 'inflow';
  return 'outflow';
}

function accountForClient(doc: FinanceDocument, account: FinanceDocument['accounts'][number], asOf: string) {
  const balance = accountBalance(doc, account, asOf);
  const debt = account.type === 'creditCard' ? Math.max(0, -balance) : null;
  return {
    id: account.id,
    name: account.name,
    institution: account.institution,
    type: account.type,
    currency: account.currency,
    status: account.status,
    opening_date: account.openingDate,
    opening_balance_paise: account.openingBalancePaise,
    balance_paise: balance,
    balance_inr: toInr(balance),
    balance_formatted: formatInr(balance),
    available_credit_paise: account.creditLimitPaise != null && debt != null
      ? Math.max(0, account.creditLimitPaise - debt)
      : null,
    credit_limit_paise: account.creditLimitPaise ?? null,
    transaction_count: doc.transactions.filter((t) => t.accountID === account.id || t.transferAccountID === account.id).length,
    last_reconciled_on: account.lastReconciledOn ?? null,
    certainty: account.statementBalanceOn && account.statementBalancePaise != null ? 'verified' : 'calculated',
    is_demo: account.isDemo,
    notes: account.notes
  };
}

function budgetRange(budget: Record<string, unknown>, containing: string): { start: string; end: string } {
  const period = String(budget.period ?? 'monthly');
  if (period === 'monthly') return { start: monthStart(containing), end: monthEnd(containing) };
  if (period === 'quarterly') {
    const month = Number(containing.slice(5, 7));
    const first = Math.floor((month - 1) / 3) * 3 + 1;
    const start = `${containing.slice(0, 4)}-${String(first).padStart(2, '0')}-01`;
    const endMonth = new Date(Date.UTC(Number(start.slice(0, 4)), first - 1 + 2, 1));
    const end = monthEnd(`${endMonth.getUTCFullYear()}-${String(endMonth.getUTCMonth() + 1).padStart(2, '0')}-01`);
    return { start, end };
  }
  if (period === 'annual') {
    return { start: `${containing.slice(0, 4)}-01-01`, end: `${containing.slice(0, 4)}-12-31` };
  }
  return {
    start: String(budget.startDate ?? monthStart(containing)),
    end: String(budget.endDate ?? monthEnd(containing))
  };
}

function budgetActual(doc: FinanceDocument, budget: Record<string, unknown>, range: { start: string; end: string }): number {
  const categoryID = budget.categoryID ? String(budget.categoryID) : null;
  let actual = 0;
  for (const t of doc.transactions) {
    if (t.date < range.start || t.date > range.end) continue;
    if (categoryID && t.categoryID !== categoryID) continue;
    if (isExpense(t)) actual += t.type === 'loanRepayment' ? (t.interestPaise ?? 0) : t.amountPaise;
    else if (t.type === 'refund') actual -= t.amountPaise;
  }
  return Math.max(0, actual);
}

export const financeLedgerTools: ToolDefinition[] = [
  {
    name: 'meos_finance_ledger_get_summary',
    title: 'Get the Finance ledger summary',
    description:
      'Read the owner\'s actual MeOS Finance ledger: net worth, assets, liabilities, cash, investments, this month\'s income/expenses/net savings, counts and data coverage. This is derived from recorded accounts and transactions, unlike the Fold snapshot. If there are no records, say so; never invent a balance.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const doc = await readFinance(ctx);
      const asOf = todayKey();
      if (!hasRecords(doc)) {
        return ok(
          { available: false, currency: 'INR', as_of: asOf, counts: { accounts: 0, transactions: 0 } },
          {
            source_kind: 'encrypted_finance_ledger',
            note: 'No Finance records exist. Fold may still have a separate read-only snapshot; do not treat it as this ledger.'
          }
        );
      }
      const nw = netWorth(doc, asOf);
      const p = portfolio(doc, asOf);
      const month = monthTotals(doc, asOf);
      return ok(
        {
          available: true,
          currency: 'INR',
          as_of: asOf,
          demo_data: doc.settings.demoMode,
          net_worth: { paise: nw.netWorthPaise, inr: toInr(nw.netWorthPaise), formatted: formatInr(nw.netWorthPaise) },
          assets: { paise: nw.assetsPaise, inr: toInr(nw.assetsPaise), formatted: formatInr(nw.assetsPaise) },
          liabilities: { paise: nw.liabilitiesPaise, inr: toInr(nw.liabilitiesPaise), formatted: formatInr(nw.liabilitiesPaise) },
          liquid_cash: { paise: liquidAssets(doc, asOf), formatted: formatInr(liquidAssets(doc, asOf)) },
          investments: {
            value_paise: p.valuePaise,
            value_formatted: formatInr(p.valuePaise),
            invested_paise: p.investedPaise,
            invested_formatted: formatInr(p.investedPaise),
            unrealised_paise: p.unrealisedPaise,
            unrealised_formatted: formatInr(p.unrealisedPaise),
            certainty: p.certainty
          },
          this_month: {
            income_paise: month.incomePaise,
            income_formatted: formatInr(month.incomePaise),
            expenses_paise: month.expensePaise,
            expenses_formatted: formatInr(month.expensePaise),
            net_savings_paise: month.netSavingsPaise,
            net_savings_formatted: formatInr(month.netSavingsPaise),
            savings_rate_percent: month.savingsRate
          },
          counts: {
            accounts: doc.accounts.filter((a) => a.status === 'active').length,
            transactions: doc.transactions.length,
            investments: doc.investments.filter((i) => !i.archived).length,
            liabilities: doc.liabilities.length,
            budgets: doc.budgets.length,
            goals: doc.goals.length
          },
          coverage: {
            tracking_start: doc.settings.trackingStartDate,
            first_transaction: [...doc.transactions].sort((a, b) => a.date.localeCompare(b.date))[0]?.date ?? null,
            last_transaction: [...doc.transactions].sort((a, b) => b.date.localeCompare(a.date))[0]?.date ?? null
          }
        },
        {
          source_kind: 'encrypted_finance_ledger',
          note: 'Transfers, card settlements, refunds, investment flows and loan principal follow the same rules as the native app.'
        }
      );
    }
  },

  {
    name: 'meos_finance_ledger_list_accounts',
    title: 'List Finance ledger accounts',
    description:
      'List the accounts in the MeOS Finance ledger with current balances, institution, type, transaction count and reconciliation date. No full account numbers exist in MeOS; never ask for or invent one.',
    inputSchema: {
      include_archived: z.boolean().optional(),
      as_of: DateKey.optional(),
      account_type: z.enum(ACCOUNT_TYPES as unknown as [FinanceAccountType, ...FinanceAccountType[]]).optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const asOf = args.as_of ?? todayKey();
      const includeArchived = args.include_archived === true;
      const type = args.account_type as FinanceAccountType | undefined;
      const accounts = doc.accounts
        .filter((a) => (includeArchived || a.status === 'active') && (!type || a.type === type))
        .map((a) => accountForClient(doc, a, asOf))
        .sort((a, b) => Math.abs(Number(b.balance_paise)) - Math.abs(Number(a.balance_paise)));
      return ok(
        {
          available: accounts.length > 0,
          as_of: asOf,
          currency: 'INR',
          total_assets_formatted: formatInr(totalAssets(doc, asOf)),
          total_liabilities_formatted: formatInr(totalLiabilities(doc, asOf)),
          accounts
        },
        { source_kind: 'encrypted_finance_ledger', note: 'Balances are signed: assets positive, credit-card debt negative.' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_list_transactions',
    title: 'List Finance transactions',
    description:
      'List the actual MeOS transaction ledger, newest first, with filters for date range, account, category, type, direction, source, verification, payee and amount. Transfers and investment flows are labelled so an agent does not count them as spending.',
    inputSchema: {
      start: DateKey.optional(),
      end: DateKey.optional(),
      account_id: z.string().min(1).optional(),
      category_id: z.string().min(1).optional(),
      type: z.enum(TXN_TYPES as unknown as [FinanceTxnType, ...FinanceTxnType[]]).optional(),
      direction: z.enum(DIRECTIONS as unknown as [FinanceDirection, FinanceDirection]).optional(),
      source: z.enum(SOURCES as unknown as [FinanceSource, ...FinanceSource[]]).optional(),
      verification: z.enum(VERIFICATIONS as unknown as [FinanceVerification, ...FinanceVerification[]]).optional(),
      merchant: z.string().max(120).optional(),
      min_inr: Money.describe('Minimum amount in rupees.').optional(),
      max_inr: Money.describe('Maximum amount in rupees.').optional(),
      ...CursorShape
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const start = args.start ? assertDateKey(args.start, 'start') : undefined;
      const end = args.end ? assertDateKey(args.end, 'end') : undefined;
      const min = parseMoney(args.min_inr, 'min_inr');
      const max = parseMoney(args.max_inr, 'max_inr');
      const merchant = String(args.merchant ?? '').trim().toLowerCase();

      let rows = doc.transactions.filter((t) => {
        if (start && t.date < start) return false;
        if (end && t.date > end) return false;
        if (args.account_id && t.accountID !== cleanId(String(args.account_id), 'account_id')) return false;
        if (args.category_id && t.categoryID !== cleanId(String(args.category_id), 'category_id')) return false;
        if (args.type && t.type !== args.type) return false;
        if (args.direction && t.direction !== args.direction) return false;
        if (args.source && t.source !== args.source) return false;
        if (args.verification && t.verification !== args.verification) return false;
        if (min !== undefined && t.amountPaise < min) return false;
        if (max !== undefined && t.amountPaise > max) return false;
        if (merchant && !t.merchant.toLowerCase().includes(merchant)) return false;
        return true;
      });
      rows = rows.sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
      const page = paginate(rows, args.limit, args.cursor);
      return ok(
        {
          currency: 'INR',
          matching: rows.length,
          ...page,
          items: page.items.map((t) => txForClient(doc, t)),
          filters: { start: start ?? null, end: end ?? null, account_id: args.account_id ?? null, category_id: args.category_id ?? null }
        },
        { source_kind: 'encrypted_finance_ledger' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_get_transaction',
    title: 'Get one Finance transaction',
    description: 'Read one transaction with its audit history. Use the audit entries to explain corrections; never describe a correction as if it were the original value.',
    inputSchema: { id: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const id = cleanId(String(args.id));
      const t = doc.transactions.find((row) => row.id === id);
      if (!t) throw errors.notFound('Transaction');
      return ok(
        {
          transaction: txForClient(doc, t),
          audit: doc.audit
            .filter((a) => a.entityID === id)
            .sort((a, b) => b.at.localeCompare(a.at))
            .map((a) => ({
              action: a.action,
              field: a.field ?? null,
              old_value: a.oldValue ?? null,
              new_value: a.newValue ?? null,
              reason: a.reason,
              actor: a.actor,
              at: a.at
            }))
        },
        { source_kind: 'encrypted_finance_ledger' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_search',
    title: 'Search the Finance ledger',
    description:
      'Search recorded transactions by payee, note, reference, tag, category, account or type. Returns matching rows with classification flags. Use this for questions about a specific merchant or payment.',
    inputSchema: {
      query: z.string().min(1).max(200),
      ...CursorShape
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const q = String(args.query).trim().toLowerCase();
      const rows = doc.transactions.filter((t) => {
        const haystack = [
          t.merchant,
          t.note,
          t.reference,
          t.tags.join(' '),
          categoryName(doc, t.categoryID),
          accountName(doc, t.accountID),
          t.type
        ].join(' ').toLowerCase();
        return haystack.includes(q);
      }).sort((a, b) => b.date.localeCompare(a.date));
      const page = paginate(rows, args.limit, args.cursor);
      return ok(
        {
          query: args.query,
          matching: rows.length,
          ...page,
          items: page.items.map((t) => txForClient(doc, t))
        },
        { source_kind: 'encrypted_finance_ledger', note: 'If matching is zero, say nothing was found rather than inventing a payment.' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_get_spending',
    title: 'Get Finance spending',
    description:
      'Spending from the actual MeOS ledger for a date range: totals, category breakdown, top payees and monthly cash flow. Transfers and investment purchases are excluded; refunds reduce spending.',
    inputSchema: {
      start: DateKey.optional(),
      end: DateKey.optional(),
      months: z.number().int().min(1).max(60).optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const end = args.end ? assertDateKey(args.end, 'end') : todayKey();
      const start = args.start
        ? assertDateKey(args.start, 'start')
        : monthStart(addMonthsSafe(end, -(Math.min(args.months ?? 1, 60) - 1)));
      const totals = periodTotals(doc, start, end);
      return ok(
        {
          period: { start, end },
          currency: 'INR',
          income_paise: totals.incomePaise,
          income_formatted: formatInr(totals.incomePaise),
          expenses_paise: totals.expensePaise,
          expenses_formatted: formatInr(totals.expensePaise),
          refunds_paise: totals.refundPaise,
          net_savings_paise: totals.netSavingsPaise,
          savings_rate_percent: totals.savingsRate,
          by_category: expenseByCategory(doc, start, end).map((s) => ({
            category_id: s.categoryID,
            category: s.name,
            group: s.group,
            amount_paise: s.paise,
            amount_formatted: formatInr(s.paise),
            share_percent: Number(s.share.toFixed(1)),
            count: s.count
          })),
          top_payees: merchantBreakdown(doc, start, end).slice(0, 10).map((m) => ({
            payee: m.merchant,
            amount_paise: m.paise,
            amount_formatted: formatInr(m.paise),
            count: m.count
          }))
        },
        { source_kind: 'encrypted_finance_ledger' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_get_net_worth',
    title: 'Get Finance net worth',
    description:
      'Net worth from recorded accounts, investments and liabilities, plus month-end history. Assets minus liabilities; credit cards are liabilities. Missing months are skipped, never interpolated.',
    inputSchema: {
      as_of: DateKey.optional(),
      months: z.number().int().min(1).max(120).optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const asOf = args.as_of ? assertDateKey(args.as_of, 'as_of') : todayKey();
      const nw = netWorth(doc, asOf);
      const start = addMonthsSafe(monthStart(asOf), -(Math.min(args.months ?? 12, 120) - 1));
      const history = netWorthHistory(doc, start, asOf);
      return ok(
        {
          available: hasRecords(doc),
          as_of: asOf,
          currency: 'INR',
          net_worth_paise: nw.netWorthPaise,
          net_worth_formatted: formatInr(nw.netWorthPaise),
          assets_paise: nw.assetsPaise,
          assets_formatted: formatInr(nw.assetsPaise),
          liabilities_paise: nw.liabilitiesPaise,
          liabilities_formatted: formatInr(nw.liabilitiesPaise),
          history: history.map((p) => ({
            date: p.date,
            assets_paise: p.assetsPaise,
            liabilities_paise: p.liabilitiesPaise,
            net_worth_paise: p.netWorthPaise,
            net_worth_formatted: formatInr(p.netWorthPaise),
            certainty: p.certainty
          }))
        },
        { source_kind: 'encrypted_finance_ledger', note: 'Missing months are genuinely absent, not zero.' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_get_investments',
    title: 'Get Finance investments',
    description:
      'Holdings, invested capital, current value, unrealised gain/loss, return and allocation from the MeOS ledger. Values are manual or statement-based; no live provider is connected.',
    inputSchema: { as_of: DateKey.optional() },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const asOf = args.as_of ? assertDateKey(args.as_of, 'as_of') : todayKey();
      const p = portfolio(doc, asOf);
      const summaries = investmentSummaries(doc, asOf);
      return ok(
        {
          available: summaries.length > 0,
          as_of: asOf,
          currency: 'INR',
          value_paise: p.valuePaise,
          value_formatted: formatInr(p.valuePaise),
          invested_paise: p.investedPaise,
          invested_formatted: formatInr(p.investedPaise),
          unrealised_paise: p.unrealisedPaise,
          unrealised_formatted: formatInr(p.unrealisedPaise),
          certainty: p.certainty,
          allocation: p.allocation.map((a) => ({
            asset_class: a.assetClass,
            value_paise: a.paise,
            share_percent: Number(a.share.toFixed(1))
          })),
          holdings: summaries.map((s) => ({
            id: s.investment.id,
            name: s.investment.name,
            asset_class: s.investment.assetClass,
            institution: s.investment.institution,
            units: s.investment.units,
            invested_paise: s.investedPaise,
            invested_formatted: formatInr(s.investedPaise),
            value_paise: s.valuePaise,
            value_formatted: formatInr(s.valuePaise),
            unrealised_paise: s.unrealisedPaise,
            unrealised_formatted: formatInr(s.unrealisedPaise),
            return_percent: s.returnPercent,
            certainty: s.certainty
          }))
        },
        {
          source_kind: 'encrypted_finance_ledger',
          note: 'No live market feed. Do not claim a price is current unless a valuation is dated today.'
        }
      );
    }
  },

  {
    name: 'meos_finance_ledger_get_liabilities',
    title: 'Get Finance liabilities',
    description:
      'Outstanding debt, original principal, interest rate, EMI, repayment progress and ownership from the MeOS ledger. Personal debt is included in net worth; household debt only if the owner opted in.',
    inputSchema: { as_of: DateKey.optional() },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const asOf = args.as_of ? assertDateKey(args.as_of, 'as_of') : todayKey();
      const summaries = liabilitySummaries(doc, asOf);
      return ok(
        {
          available: summaries.length > 0,
          as_of: asOf,
          currency: 'INR',
          total_in_net_worth_paise: totalLiabilities(doc, asOf),
          total_in_net_worth_formatted: formatInr(totalLiabilities(doc, asOf)),
          include_household: doc.settings.includeHouseholdInNetWorth,
          liabilities: summaries.map((s) => ({
            id: s.liability.id,
            name: s.liability.name,
            kind: s.liability.kind,
            ownership: s.liability.ownership,
            lender: s.liability.lender,
            original_principal_paise: s.liability.originalPrincipalPaise,
            outstanding_paise: s.outstandingPaise,
            outstanding_formatted: formatInr(s.outstandingPaise),
            interest_rate_percent: s.liability.interestRateBps / 100,
            emi_paise: s.liability.emiPaise,
            emi_formatted: formatInr(s.liability.emiPaise),
            progress_percent: Number((s.progress * 100).toFixed(1)),
            paid_principal_paise: s.paidPrincipalPaise,
            paid_interest_paise: s.paidInterestPaise
          }))
        },
        { source_kind: 'encrypted_finance_ledger' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_list_budgets',
    title: 'List Finance budgets',
    description: 'Budget plans with actual spend, remaining amount and variance for the period containing a date. Actuals use the same expense rules as reports.',
    inputSchema: {
      on: DateKey.optional(),
      include_archived: z.boolean().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const on = args.on ? assertDateKey(args.on, 'on') : todayKey();
      const budgets = doc.budgets
        .filter((b) => args.include_archived === true || b.archived !== true)
        .map((b) => {
          const range = budgetRange(b, on);
          const actual = budgetActual(doc, b, range);
          const planned = Number(b.plannedPaise ?? 0);
          return {
            id: String(b.id ?? ''),
            name: String(b.name ?? ''),
            category_id: b.categoryID ? String(b.categoryID) : null,
            category: b.categoryID ? categoryName(doc, String(b.categoryID)) : 'All spending',
            period: String(b.period ?? 'monthly'),
            range,
            planned_paise: planned,
            planned_formatted: formatInr(planned),
            actual_paise: actual,
            actual_formatted: formatInr(actual),
            remaining_paise: planned - actual,
            remaining_formatted: formatInr(planned - actual),
            progress_percent: planned > 0 ? Number(((actual / planned) * 100).toFixed(1)) : null
          };
        });
      return ok({ budgets }, { source_kind: 'encrypted_finance_ledger' });
    }
  },

  {
    name: 'meos_finance_ledger_list_goals',
    title: 'List Finance goals',
    description: 'Financial goals with target, current allocation, deadline, monthly contribution and progress. An allocation is a planning figure, not a separate asset.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const doc = await readFinance(ctx);
      return ok(
        {
          goals: doc.goals.map((g) => {
            const target = Number(g.targetPaise ?? 0);
            const current = Number(g.currentPaise ?? 0);
            return {
              id: String(g.id ?? ''),
              name: String(g.name ?? ''),
              kind: String(g.kind ?? 'custom'),
              target_paise: target,
              target_formatted: formatInr(target),
              current_paise: current,
              current_formatted: formatInr(current),
              progress_percent: target > 0 ? Number(Math.min(100, (current / target) * 100).toFixed(1)) : null,
              deadline: g.deadline ?? null,
              monthly_contribution_paise: Number(g.monthlyContributionPaise ?? 0),
              achieved: Boolean(g.achieved)
            };
          })
        },
        { source_kind: 'encrypted_finance_ledger' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_get_timeline',
    title: 'Get the financial timeline',
    description: 'Milestones and automatic first-events from the ledger: first account, first income, first investment, plus user milestones. Certainty labels distinguish what is verified from what is calculated.',
    inputSchema: { limit: z.number().int().min(1).max(100).optional() },
    scopes: ['read'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const entries = timeline(doc).slice(0, Math.min(args.limit ?? 50, 100));
      return ok({ entries }, { source_kind: 'encrypted_finance_ledger' });
    }
  },

  {
    name: 'meos_finance_ledger_add_account',
    title: 'Add a Finance account',
    description:
      'Create an owned account in the MeOS Finance ledger. This is a real write that syncs to the native app. Use opening_balance_inr as the amount owed for a credit card, otherwise the opening asset balance.',
    inputSchema: {
      name: z.string().min(1).max(120),
      type: z.enum(ACCOUNT_TYPES as unknown as [FinanceAccountType, ...FinanceAccountType[]]),
      institution: z.string().max(120).optional(),
      opening_date: DateKey.optional(),
      opening_balance_inr: Money.optional(),
      credit_limit_inr: Money.optional(),
      notes: z.string().max(2000).optional()
    },
    scopes: ['read', 'write'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const name = cleanText(String(args.name), 'name', 120);
      const opening = parseMoney(args.opening_balance_inr, 'opening_balance_inr') ?? 0;
      const account = makeAccount({
        name,
        institution: String(args.institution ?? '').slice(0, 120),
        type: args.type,
        openingDate: args.opening_date ? assertDateKey(args.opening_date, 'opening_date') : todayKey(),
        openingBalancePaise: opening,
        creditLimitPaise: parseMoney(args.credit_limit_inr, 'credit_limit_inr') ?? null,
        notes: String(args.notes ?? '').slice(0, 2000)
      });
      doc.accounts.push(account);
      doc.audit.push(makeAudit('account', account.id, 'created', 'Account created by MCP', { newValue: account.name }));
      await saveFinance(ctx, doc);
      return ok({ account: accountForClient(doc, account, todayKey()) }, { written: STATE_KEYS.finance });
    }
  },

  {
    name: 'meos_finance_ledger_add_transaction',
    title: 'Add a Finance transaction',
    description:
      'Record an ordinary income, expense, refund, fee, tax, interest or dividend transaction in the ledger. Use add_transfer for internal transfers. Investment purchases and loan repayments link to an existing holding/liability and update their capital/debt. This is a real write that syncs to the native app.',
    inputSchema: {
      date: DateKey,
      amount_inr: Money,
      type: z.enum(TXN_TYPES.filter((t) => t !== 'transfer') as unknown as [FinanceTxnType, ...FinanceTxnType[]]),
      account_id: z.string().min(1),
      direction: z.enum(DIRECTIONS as unknown as [FinanceDirection, FinanceDirection]).optional(),
      category_id: z.string().min(1).optional(),
      merchant: z.string().max(200).optional(),
      payment_method: z.enum(PAYMENT_METHODS as unknown as [FinancePaymentMethod, ...FinancePaymentMethod[]]).optional(),
      note: z.string().max(4000).optional(),
      reference: z.string().max(200).optional(),
      tags: z.array(z.string().max(40)).max(20).optional(),
      investment_id: z.string().min(1).optional(),
      liability_id: z.string().min(1).optional(),
      principal_inr: Money.optional(),
      interest_inr: Money.optional()
    },
    scopes: ['read', 'write'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const amount = parseMoney(args.amount_inr, 'amount_inr', true)!;
      if (amount <= 0) throw errors.invalidInput('amount_inr must be greater than zero');
      const date = assertDateKey(String(args.date), 'date');
      const accountId = cleanId(String(args.account_id), 'account_id');
      const account = doc.accounts.find((a) => a.id === accountId);
      if (!account) throw errors.notFound('Account');
      const type = args.type as FinanceTxnType;

      const categoryId = args.category_id ? cleanId(String(args.category_id), 'category_id') : null;
      if (categoryId && !doc.categories.some((c) => c.id === categoryId)) throw errors.notFound('Category');

      let principal: number | null = null;
      let interest: number | null = null;
      let investment: FinanceInvestment | undefined;
      let liability: FinanceLiability | undefined;

      if (type === 'investmentPurchase' || type === 'investmentSale') {
        if (!args.investment_id) throw errors.invalidInput('investment_id is required for investment flows');
        investment = doc.investments.find((i) => i.id === cleanId(String(args.investment_id), 'investment_id'));
        if (!investment) throw errors.notFound('Investment');
      }

      if (type === 'loanRepayment') {
        if (!args.liability_id) throw errors.invalidInput('liability_id is required for a loan repayment');
        liability = doc.liabilities.find((l) => l.id === cleanId(String(args.liability_id), 'liability_id'));
        if (!liability) throw errors.notFound('Liability');
        principal = parseMoney(args.principal_inr, 'principal_inr') ?? Math.max(0, amount - (parseMoney(args.interest_inr, 'interest_inr') ?? 0));
        interest = parseMoney(args.interest_inr, 'interest_inr') ?? 0;
        if (principal + interest !== amount) {
          throw errors.invalidInput('principal_inr + interest_inr must equal amount_inr');
        }
      }

      if (type === 'loanDisbursement' && args.liability_id) {
        liability = doc.liabilities.find((l) => l.id === cleanId(String(args.liability_id), 'liability_id'));
        if (!liability) throw errors.notFound('Liability');
      }

      const txn = makeTransaction({
        date,
        amountPaise: amount,
        direction: defaultDirection(type, args.direction as FinanceDirection | undefined),
        type,
        accountID: accountId,
        categoryID: categoryId,
        merchant: String(args.merchant ?? '').slice(0, 200),
        paymentMethod: (args.payment_method as FinancePaymentMethod | undefined) ?? 'other',
        note: String(args.note ?? '').slice(0, 4000),
        reference: String(args.reference ?? '').slice(0, 200),
        tags: Array.isArray(args.tags) ? args.tags.map((t: string) => String(t).slice(0, 40)).slice(0, 20) : [],
        investmentID: investment?.id ?? null,
        liabilityID: liability?.id ?? null,
        principalPaise: principal,
        interestPaise: interest,
        source: 'manual',
        verification: 'verified'
      });

      doc.transactions.push(txn);
      doc.audit.push(makeAudit('transaction', txn.id, 'created', 'Transaction created by MCP', {
        newValue: `${txn.type} ${formatInr(txn.amountPaise)}`,
        sourceTransactionID: txn.id
      }));

      if (investment) {
        if (type === 'investmentPurchase') {
          investment.investedPaise += amount;
          investment.updatedAt = nowStamp();
          doc.audit.push(makeAudit('investment', investment.id, 'updated', 'Purchase recorded by MCP', {
            field: 'invested', newValue: formatInr(investment.investedPaise), sourceTransactionID: txn.id
          }));
        } else {
          investment.investedPaise = Math.max(0, investment.investedPaise - amount);
          investment.updatedAt = nowStamp();
        }
      }

      if (liability && type === 'loanRepayment') {
        doc.debtPayments.push({
          id: newId(),
          liabilityID: liability.id,
          transactionID: txn.id,
          date,
          amountPaise: amount,
          principalPaise: principal ?? 0,
          interestPaise: interest ?? 0,
          note: 'Recorded by MCP',
          isDemo: false,
          createdAt: nowStamp()
        });
        liability.outstandingPaise = Math.max(0, liability.outstandingPaise - (principal ?? 0));
        liability.asOf = date;
        liability.updatedAt = nowStamp();
        doc.audit.push(makeAudit('liability', liability.id, 'updated', 'Repayment recorded by MCP', {
          field: 'principal_paid', newValue: formatInr(principal ?? 0), sourceTransactionID: txn.id
        }));
      }

      await saveFinance(ctx, doc);
      return ok({ transaction: txForClient(doc, txn) }, { written: STATE_KEYS.finance });
    }
  },

  {
    name: 'meos_finance_ledger_update_transaction',
    title: 'Correct a Finance transaction',
    description:
      'Correct one non-transfer transaction. Every changed field appends an immutable audit entry with the old and new value. Transfers must be corrected as a pair in the app. Imported records keep their source and return to review unless explicitly marked verified.',
    inputSchema: {
      id: z.string().min(1),
      date: DateKey.optional(),
      amount_inr: Money.optional(),
      category_id: z.string().min(1).nullable().optional(),
      merchant: z.string().max(200).optional(),
      note: z.string().max(4000).optional(),
      reference: z.string().max(200).optional(),
      tags: z.array(z.string().max(40)).max(20).optional(),
      verification: z.enum(VERIFICATIONS as unknown as [FinanceVerification, ...FinanceVerification[]]).optional(),
      reason: z.string().min(1).max(500)
    },
    scopes: ['read', 'write'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const id = cleanId(String(args.id));
      const index = doc.transactions.findIndex((t) => t.id === id);
      if (index < 0) throw errors.notFound('Transaction');
      const before = doc.transactions[index]!;
      if (before.transferID || before.type === 'transfer') {
        throw errors.invalidInput('A transfer is a linked pair; edit it from the MeOS app so both sides stay consistent');
      }

      const updated: FinanceTransaction = { ...before };
      const reason = cleanText(String(args.reason), 'reason', 500);
      const noteChange = (field: string, oldValue: string | null, newValue: string | null) => {
        if (oldValue === newValue) return;
        doc.audit.push(makeAudit('transaction', id, 'updated', reason, {
          field, oldValue, newValue, sourceTransactionID: id
        }));
      };

      if (args.date !== undefined) {
        const next = assertDateKey(String(args.date), 'date');
        noteChange('date', before.date, next);
        updated.date = next;
      }
      if (args.amount_inr !== undefined) {
        const next = parseMoney(args.amount_inr, 'amount_inr', true)!;
        if (next <= 0) throw errors.invalidInput('amount_inr must be greater than zero');
        noteChange('amount', formatInr(before.amountPaise), formatInr(next));
        updated.amountPaise = next;
      }
      if (args.category_id !== undefined) {
        const next = args.category_id === null ? null : cleanId(String(args.category_id), 'category_id');
        if (next && !doc.categories.some((c) => c.id === next)) throw errors.notFound('Category');
        noteChange('category', categoryName(doc, before.categoryID), categoryName(doc, next));
        updated.categoryID = next;
      }
      if (args.merchant !== undefined) {
        const next = String(args.merchant).slice(0, 200);
        noteChange('merchant', before.merchant, next);
        updated.merchant = next;
      }
      if (args.note !== undefined) {
        const next = String(args.note).slice(0, 4000);
        noteChange('note', before.note, next);
        updated.note = next;
      }
      if (args.reference !== undefined) {
        const next = String(args.reference).slice(0, 200);
        noteChange('reference', before.reference, next);
        updated.reference = next;
      }
      if (args.tags !== undefined) {
        const next = args.tags.map((t: string) => String(t).slice(0, 40)).slice(0, 20);
        noteChange('tags', before.tags.join(', '), next.join(', '));
        updated.tags = next;
      }
      if (args.verification !== undefined) {
        noteChange('verification', before.verification, String(args.verification));
        updated.verification = args.verification as FinanceVerification;
      }
      if (updated.source === 'imported' && !['verified', 'reconciled'].includes(updated.verification)) {
        updated.verification = 'needsReview';
      }
      updated.updatedAt = nowStamp();
      doc.transactions[index] = updated;

      if (before.type === 'investmentPurchase' && before.investmentID) {
        const investment = doc.investments.find((i) => i.id === before.investmentID);
        if (investment) {
          investment.investedPaise = Math.max(0, investment.investedPaise + (updated.amountPaise - before.amountPaise));
          investment.updatedAt = nowStamp();
        }
      }

      await saveFinance(ctx, doc);
      return ok({ transaction: txForClient(doc, updated) }, { written: STATE_KEYS.finance });
    }
  },

  {
    name: 'meos_finance_ledger_add_transfer',
    title: 'Add an internal transfer',
    description:
      'Record money moving between two owned accounts. Creates two linked transaction legs and a transfer record, so it is never counted as income or spending. A fee is booked separately as an expense.',
    inputSchema: {
      from_account_id: z.string().min(1),
      to_account_id: z.string().min(1),
      amount_inr: Money,
      date: DateKey,
      fee_inr: Money.optional(),
      reference: z.string().max(200).optional(),
      note: z.string().max(4000).optional()
    },
    scopes: ['read', 'write'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const from = cleanId(String(args.from_account_id), 'from_account_id');
      const to = cleanId(String(args.to_account_id), 'to_account_id');
      if (from === to) throw errors.invalidInput('from_account_id and to_account_id must differ');
      if (!doc.accounts.some((a) => a.id === from)) throw errors.notFound('Source account');
      if (!doc.accounts.some((a) => a.id === to)) throw errors.notFound('Destination account');
      const amount = parseMoney(args.amount_inr, 'amount_inr', true)!;
      if (amount <= 0) throw errors.invalidInput('amount_inr must be greater than zero');
      const date = assertDateKey(String(args.date), 'date');
      const fee = parseMoney(args.fee_inr, 'fee_inr') ?? 0;
      const transferID = newId();

      const out = makeTransaction({
        date, amountPaise: amount, direction: 'outflow', type: 'transfer',
        accountID: from, transferAccountID: to, merchant: 'Internal transfer',
        paymentMethod: 'bankTransfer', note: String(args.note ?? '').slice(0, 4000),
        reference: String(args.reference ?? '').slice(0, 200),
        transferID, verification: 'verified'
      });
      const incoming = makeTransaction({
        date, amountPaise: amount, direction: 'inflow', type: 'transfer',
        accountID: to, transferAccountID: from, merchant: 'Internal transfer',
        paymentMethod: 'bankTransfer', note: String(args.note ?? '').slice(0, 4000),
        reference: String(args.reference ?? '').slice(0, 200),
        transferID, verification: 'verified'
      });
      out.linkedTransactionID = incoming.id;
      incoming.linkedTransactionID = out.id;

      const transfer = {
        id: transferID,
        fromAccountID: from,
        toAccountID: to,
        amountPaise: amount,
        date,
        feePaise: fee,
        reference: String(args.reference ?? '').slice(0, 200),
        note: String(args.note ?? '').slice(0, 4000),
        fromTransactionID: out.id,
        toTransactionID: incoming.id,
        feeTransactionID: null as string | null,
        reconciled: true,
        isDemo: false,
        createdAt: nowStamp()
      };
      doc.transactions.push(out, incoming);
      doc.transfers.push(transfer as any);

      if (fee > 0) {
        const feeTxn = makeTransaction({
          date, amountPaise: fee, direction: 'outflow', type: 'fee',
          accountID: from, merchant: 'Transfer fee', paymentMethod: 'bankTransfer',
          note: 'Internal transfer fee', transferID, verification: 'verified'
        });
        doc.transactions.push(feeTxn);
        transfer.feeTransactionID = feeTxn.id;
      }

      doc.audit.push(makeAudit('transfer', transferID, 'created', 'Transfer created by MCP', {
        newValue: `${accountName(doc, from)} → ${accountName(doc, to)} ${formatInr(amount)}`
      }));
      await saveFinance(ctx, doc);
      return ok(
        {
          transfer: {
            id: transferID,
            from: accountName(doc, from),
            to: accountName(doc, to),
            amount_paise: amount,
            amount_formatted: formatInr(amount),
            fee_paise: fee,
            date,
            out_transaction_id: out.id,
            in_transaction_id: incoming.id
          }
        },
        { written: STATE_KEYS.finance, note: 'Excluded from income and spending.' }
      );
    }
  },

  {
    name: 'meos_finance_ledger_add_investment',
    title: 'Add an investment holding',
    description:
      'Add a holding with invested capital and a dated current valuation. This is a real write. Values are manual/statement-based; do not pretend a live market price exists.',
    inputSchema: {
      name: z.string().min(1).max(120),
      asset_class: z.enum(ASSET_CLASSES as unknown as [FinanceAssetClass, ...FinanceAssetClass[]]),
      invested_inr: Money,
      current_value_inr: Money,
      value_date: DateKey.optional(),
      institution: z.string().max(120).optional(),
      units: z.number().positive().optional(),
      purchase_date: DateKey.optional(),
      notes: z.string().max(2000).optional()
    },
    scopes: ['read', 'write'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const invested = parseMoney(args.invested_inr, 'invested_inr', true)!;
      const current = parseMoney(args.current_value_inr, 'current_value_inr', true)!;
      const valueDate = args.value_date ? assertDateKey(args.value_date, 'value_date') : todayKey();
      const investment = makeInvestment({
        name: cleanText(String(args.name), 'name', 120),
        assetClass: args.asset_class,
        institution: String(args.institution ?? '').slice(0, 120),
        units: args.units ?? null,
        purchaseDate: args.purchase_date ? assertDateKey(args.purchase_date, 'purchase_date') : null,
        investedPaise: invested,
        currentValuePaise: current,
        currentValueOn: valueDate,
        notes: String(args.notes ?? '').slice(0, 2000)
      });
      doc.investments.push(investment);
      doc.valuations.push({
        id: newId(),
        investmentID: investment.id,
        date: valueDate,
        valuePaise: current,
        source: 'manual',
        note: 'Opening valuation recorded by MCP',
        isDemo: false,
        createdAt: nowStamp()
      });
      doc.audit.push(makeAudit('investment', investment.id, 'created', 'Holding added by MCP', {
        newValue: `${investment.name} · ${formatInr(invested)}`
      }));
      await saveFinance(ctx, doc);
      return ok({ investment }, { written: STATE_KEYS.finance });
    }
  },

  {
    name: 'meos_finance_ledger_add_valuation',
    title: 'Record an investment valuation',
    description:
      'Record a dated valuation for an existing holding. Replaces a valuation on the same day rather than creating two points. This is a real write.',
    inputSchema: {
      investment_id: z.string().min(1),
      value_inr: Money,
      date: DateKey.optional(),
      source: z.enum(['manual', 'statement', 'provider']).optional(),
      note: z.string().max(500).optional()
    },
    scopes: ['read', 'write'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const id = cleanId(String(args.investment_id), 'investment_id');
      const investment = doc.investments.find((i) => i.id === id);
      if (!investment) throw errors.notFound('Investment');
      const value = parseMoney(args.value_inr, 'value_inr', true)!;
      const date = args.date ? assertDateKey(args.date, 'date') : todayKey();
      doc.valuations = doc.valuations.filter((v) => !(v.investmentID === id && v.date === date));
      doc.valuations.push({
        id: newId(),
        investmentID: id,
        date,
        valuePaise: value,
        source: (args.source as 'manual' | 'statement' | 'provider' | undefined) ?? 'manual',
        note: String(args.note ?? '').slice(0, 500),
        isDemo: false,
        createdAt: nowStamp()
      });
      if (date >= investment.currentValueOn) {
        investment.currentValuePaise = value;
        investment.currentValueOn = date;
      }
      investment.updatedAt = nowStamp();
      doc.audit.push(makeAudit('investment', id, 'updated', 'Valuation recorded by MCP', {
        field: 'valuation', newValue: formatInr(value)
      }));
      await saveFinance(ctx, doc);
      return ok(
        { investment_id: id, date, value_paise: value, value_formatted: formatInr(value) },
        { written: STATE_KEYS.finance }
      );
    }
  },

  {
    name: 'meos_finance_ledger_add_liability',
    title: 'Add a liability',
    description:
      'Add a loan, card debt or other liability. Ownership defaults to personal; household debt is excluded from net worth unless the owner opted in. Link a credit card liability to its card account to avoid double counting.',
    inputSchema: {
      name: z.string().min(1).max(120),
      kind: z.enum(LIABILITY_KINDS as unknown as [FinanceLiabilityKind, ...FinanceLiabilityKind[]]),
      original_principal_inr: Money,
      outstanding_inr: Money,
      as_of: DateKey.optional(),
      lender: z.string().max(120).optional(),
      ownership: z.enum(OWNERSHIPS).optional(),
      interest_rate_percent: z.number().min(0).max(100).optional(),
      emi_inr: Money.optional(),
      due_day: z.number().int().min(1).max(28).optional(),
      start_date: DateKey.optional(),
      maturity_date: DateKey.optional(),
      account_id: z.string().min(1).optional(),
      notes: z.string().max(2000).optional()
    },
    scopes: ['read', 'write'],
    async handler(args, ctx) {
      const doc = await readFinance(ctx);
      const accountId = args.account_id ? cleanId(String(args.account_id), 'account_id') : null;
      if (accountId && !doc.accounts.some((a) => a.id === accountId)) throw errors.notFound('Account');
      const liability = makeLiability({
        name: cleanText(String(args.name), 'name', 120),
        kind: args.kind,
        lender: String(args.lender ?? '').slice(0, 120),
        ownership: (args.ownership as 'personal' | 'household' | 'shared' | undefined) ?? 'personal',
        originalPrincipalPaise: parseMoney(args.original_principal_inr, 'original_principal_inr', true)!,
        outstandingPaise: parseMoney(args.outstanding_inr, 'outstanding_inr', true)!,
        asOf: args.as_of ? assertDateKey(args.as_of, 'as_of') : todayKey(),
        interestRateBps: Math.round((args.interest_rate_percent ?? 0) * 100),
        emiPaise: parseMoney(args.emi_inr, 'emi_inr') ?? 0,
        dueDay: args.due_day ?? 5,
        startDate: args.start_date ? assertDateKey(args.start_date, 'start_date') : todayKey(),
        maturityDate: args.maturity_date ? assertDateKey(args.maturity_date, 'maturity_date') : null,
        accountID: accountId,
        notes: String(args.notes ?? '').slice(0, 2000)
      });
      doc.liabilities.push(liability);
      doc.audit.push(makeAudit('liability', liability.id, 'created', 'Liability created by MCP', {
        newValue: `${liability.name} · ${formatInr(liability.outstandingPaise)}`
      }));
      await saveFinance(ctx, doc);
      return ok({ liability }, { written: STATE_KEYS.finance });
    }
  }
];

/** Month arithmetic is kept local so the tool file does not depend on a date library. */
function addMonthsSafe(key: string, months: number): string {
  const [y, m, d] = key.split('-').map(Number);
  const dt = new Date(Date.UTC(y!, m! - 1, 1));
  dt.setUTCMonth(dt.getUTCMonth() + months);
  const last = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth() + 1, 0)).getUTCDate();
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(Math.min(d!, last)).padStart(2, '0')}`;
}
