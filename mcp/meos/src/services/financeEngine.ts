/**
 * Pure finance projections for the MCP gateway.
 *
 * These mirror `apps/apple/MeOS/Core/Finance/FinanceEngine.swift`. The gateway
 * must answer from the same rules as the app: transfers are not income or
 * spending, card payments settle a liability, refunds reduce spend, investment
 * flows are capital, and loan principal is not an expense.
 */

import type {
  FinanceAccount,
  FinanceCategory,
  FinanceCertainty,
  FinanceDocument,
  FinanceInvestment,
  FinanceLiability,
  FinanceTransaction
} from '../schemas/finance.ts';

export interface FinanceTotals {
  incomePaise: number;
  expensePaise: number;
  refundPaise: number;
  investmentPaise: number;
  debtPrincipalPaise: number;
  debtInterestPaise: number;
  transferPaise: number;
  transactionCount: number;
  netSavingsPaise: number;
  savingsRate: number | null;
}

export interface MonthPoint {
  month: string;
  incomePaise: number;
  expensePaise: number;
  netPaise: number;
}

export interface CategorySlice {
  categoryID: string;
  name: string;
  group: string;
  paise: number;
  count: number;
  share: number;
}

const LIABILITY_TYPES = new Set(['creditCard']);
const CASH_TYPES = new Set(['savings', 'current', 'salary', 'cash', 'wallet']);

export function isIncome(t: FinanceTransaction): boolean {
  if (t.direction !== 'inflow') return false;
  return t.type === 'income' || t.type === 'interest' || t.type === 'dividend';
}

export function isExpense(t: FinanceTransaction): boolean {
  if (t.type === 'expense' || t.type === 'fee' || t.type === 'tax') return true;
  if (t.type === 'interest') return t.direction === 'outflow';
  if (t.type === 'loanRepayment') return (t.interestPaise ?? 0) > 0;
  return false;
}

export function expenseAmount(t: FinanceTransaction): number {
  if (!isExpense(t)) return 0;
  return t.type === 'loanRepayment' ? (t.interestPaise ?? 0) : t.amountPaise;
}

export function isInternalTransfer(t: FinanceTransaction): boolean {
  return t.type === 'transfer' || Boolean(t.transferID);
}

export function isInvestmentFlow(t: FinanceTransaction): boolean {
  return t.type === 'investmentPurchase' || t.type === 'investmentSale';
}

export function inRange(t: FinanceTransaction, start: string, end: string): boolean {
  return t.date >= start && t.date <= end;
}

export function toInr(paise: number): number {
  return Math.round(paise) / 100;
}

export function formatInr(paise: number): string {
  const rupees = paise / 100;
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 0
  }).format(rupees);
}

/* ------------------------------------------------------------------ */
/* Calendar (Asia/Kolkata civil dates are stored as plain keys)        */
/* ------------------------------------------------------------------ */

function parts(key: string): [number, number, number] {
  const [y, m, d] = key.split('-').map(Number);
  return [y ?? 1970, m ?? 1, d ?? 1];
}

function keyOf(y: number, m: number, d: number): string {
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

export function addDays(key: string, days: number): string {
  const [y, m, d] = parts(key);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + days);
  return keyOf(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
}

export function addMonths(key: string, months: number): string {
  const [y, m, d] = parts(key);
  const dt = new Date(Date.UTC(y, m - 1, 1));
  dt.setUTCMonth(dt.getUTCMonth() + months);
  const last = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth() + 1, 0)).getUTCDate();
  return keyOf(dt.getUTCFullYear(), dt.getUTCMonth() + 1, Math.min(d, last));
}

export function monthStart(key: string): string {
  const [y, m] = parts(key);
  return keyOf(y, m, 1);
}

export function monthEnd(key: string): string {
  const [y, m] = parts(key);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return keyOf(y, m, last);
}

export function monthKey(key: string): string {
  return key.slice(0, 7);
}

export function monthLabel(key: string): string {
  return new Intl.DateTimeFormat('en-IN', { month: 'short', year: 'numeric', timeZone: 'UTC' })
    .format(new Date(`${monthStart(key)}T00:00:00Z`));
}

export function monthsBack(count: number, from: string): string[] {
  const out: string[] = [];
  for (let i = count - 1; i >= 0; i -= 1) out.push(addMonths(from, -i));
  return out;
}

export function monthsBetween(start: string, end: string): string[] {
  const out: string[] = [];
  let cursor = monthStart(start);
  const stop = monthStart(end);
  let guard = 0;
  while (cursor <= stop && guard < 1200) {
    out.push(cursor);
    cursor = addMonths(cursor, 1);
    guard += 1;
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* Balances and totals                                                 */
/* ------------------------------------------------------------------ */

export function accountBalance(doc: FinanceDocument, account: FinanceAccount, asOf: string): number {
  if (asOf < account.openingDate) return 0;
  const anchorDate = account.statementBalanceOn ?? account.openingDate;
  const beforeAnchor = asOf < anchorDate;
  const baseDate = beforeAnchor ? account.openingDate : anchorDate;
  const basePaise = beforeAnchor
    ? account.openingBalancePaise
    : (account.statementBalancePaise ?? account.openingBalancePaise);

  let flow = 0;
  for (const t of doc.transactions) {
    if (t.date <= baseDate || t.date > asOf) continue;
    const liability = LIABILITY_TYPES.has(account.type);
    if (t.accountID === account.id) {
      const signed = t.direction === 'inflow' ? t.amountPaise : -t.amountPaise;
      flow += liability ? -signed : signed;
    } else if (!t.transferID && t.transferAccountID === account.id) {
      flow += liability ? -t.amountPaise : t.amountPaise;
    }
  }
  const raw = basePaise + flow;
  const signed = LIABILITY_TYPES.has(account.type) ? -raw : raw;
  return signed === 0 ? 0 : signed;
}

export function accountTransactionCount(doc: FinanceDocument, accountID: string): number {
  return doc.transactions.filter((t) => t.accountID === accountID || t.transferAccountID === accountID).length;
}

export function periodTotals(doc: FinanceDocument, start: string, end: string): FinanceTotals {
  let incomePaise = 0;
  let expensePaise = 0;
  let refundPaise = 0;
  let investmentPaise = 0;
  let debtPrincipalPaise = 0;
  let debtInterestPaise = 0;
  let transferPaise = 0;
  let count = 0;

  for (const t of doc.transactions) {
    if (!inRange(t, start, end)) continue;
    count += 1;

    if (isIncome(t)) {
      incomePaise += t.amountPaise;
      continue;
    }
    if (t.type === 'refund') {
      refundPaise += t.amountPaise;
      continue;
    }
    if (isInternalTransfer(t)) {
      transferPaise += t.amountPaise;
      continue;
    }
    if (isInvestmentFlow(t)) {
      if (t.direction === 'outflow') investmentPaise += t.amountPaise;
      continue;
    }
    if (t.type === 'loanRepayment') {
      const principal = t.principalPaise ?? Math.max(0, t.amountPaise - (t.interestPaise ?? 0));
      const interest = t.interestPaise ?? 0;
      debtPrincipalPaise += principal;
      debtInterestPaise += interest;
      expensePaise += interest;
      continue;
    }
    if (t.type === 'loanDisbursement') continue;
    if (isExpense(t)) expensePaise += expenseAmount(t);
  }

  expensePaise = Math.max(0, expensePaise - refundPaise);
  const netSavingsPaise = incomePaise - expensePaise;
  return {
    incomePaise,
    expensePaise,
    refundPaise,
    investmentPaise,
    debtPrincipalPaise,
    debtInterestPaise,
    transferPaise,
    transactionCount: count,
    netSavingsPaise,
    savingsRate: incomePaise > 0 ? (netSavingsPaise / incomePaise) * 100 : null
  };
}

export function monthTotals(doc: FinanceDocument, containing: string): FinanceTotals {
  return periodTotals(doc, monthStart(containing), monthEnd(containing));
}

/* ------------------------------------------------------------------ */
/* Investments and liabilities                                         */
/* ------------------------------------------------------------------ */

export function investmentValue(doc: FinanceDocument, investment: FinanceInvestment, asOf: string): {
  paise: number;
  certainty: FinanceCertainty;
} {
  const values = doc.valuations
    .filter((v) => v.investmentID === investment.id && v.date <= asOf)
    .sort((a, b) => a.date.localeCompare(b.date));
  const latest = values[values.length - 1];
  if (latest) {
    return { paise: latest.valuePaise, certainty: latest.date === asOf ? 'verified' : 'estimated' };
  }
  if (investment.purchaseDate && investment.purchaseDate > asOf) return { paise: 0, certainty: 'verified' };
  if (investment.currentValueOn > asOf) return { paise: investment.investedPaise, certainty: 'estimated' };
  return {
    paise: investment.currentValuePaise,
    certainty: investment.currentValueOn === asOf ? 'calculated' : 'estimated'
  };
}

export function investmentSummaries(doc: FinanceDocument, asOf: string) {
  return doc.investments
    .filter((i) => !i.archived)
    .map((investment) => {
      const value = investmentValue(doc, investment, asOf);
      const invested = Math.max(0, investment.investedPaise);
      const gain = value.paise - invested;
      return {
        investment,
        valuePaise: value.paise,
        investedPaise: invested,
        unrealisedPaise: gain,
        returnPercent: invested > 0 ? (gain / invested) * 100 : null,
        certainty: value.certainty
      };
    })
    .sort((a, b) => b.valuePaise - a.valuePaise);
}

export function portfolio(doc: FinanceDocument, asOf: string) {
  const summaries = investmentSummaries(doc, asOf);
  const value = summaries.reduce((sum, s) => sum + s.valuePaise, 0);
  const invested = summaries.reduce((sum, s) => sum + s.investedPaise, 0);
  const byClass = new Map<string, number>();
  for (const s of summaries) {
    byClass.set(s.investment.assetClass, (byClass.get(s.investment.assetClass) ?? 0) + s.valuePaise);
  }
  return {
    valuePaise: value,
    investedPaise: invested,
    unrealisedPaise: value - invested,
    certainty: worstCertainty(summaries.map((s) => s.certainty)),
    allocation: [...byClass.entries()]
      .map(([assetClass, paise]) => ({ assetClass, paise, share: value > 0 ? (paise / value) * 100 : 0 }))
      .sort((a, b) => b.paise - a.paise)
  };
}

export function liabilityOutstanding(doc: FinanceDocument, liability: FinanceLiability, asOf: string): number {
  if (liability.kind === 'creditCard' && liability.accountID) {
    const account = doc.accounts.find((a) => a.id === liability.accountID);
    return account ? Math.max(0, -accountBalance(doc, account, asOf)) : 0;
  }
  const payments = doc.debtPayments.filter(
    (p) => p.liabilityID === liability.id && p.date > liability.asOf && p.date <= asOf
  );
  let principalPaid = payments.reduce((sum, p) => sum + p.principalPaise, 0);
  const recorded = new Set(payments.map((p) => p.transactionID).filter(Boolean));
  const derived = doc.transactions.filter(
    (t) =>
      t.liabilityID === liability.id &&
      t.type === 'loanRepayment' &&
      t.date > liability.asOf &&
      t.date <= asOf &&
      !recorded.has(t.id)
  );
  principalPaid += derived.reduce(
    (sum, t) => sum + (t.principalPaise ?? Math.max(0, t.amountPaise - (t.interestPaise ?? 0))),
    0
  );
  return Math.max(0, liability.outstandingPaise - principalPaid);
}

export function liabilitySummaries(doc: FinanceDocument, asOf: string) {
  return doc.liabilities
    .map((liability) => {
      const payments = doc.debtPayments.filter((p) => p.liabilityID === liability.id && p.date <= asOf);
      const principalPaid = payments.reduce((sum, p) => sum + p.principalPaise, 0);
      const interestPaid = payments.reduce((sum, p) => sum + p.interestPaise, 0);
      const outstandingPaise = liabilityOutstanding(doc, liability, asOf);
      const effectivePaid = Math.max(principalPaid, Math.max(0, liability.originalPrincipalPaise - outstandingPaise));
      const progress = liability.originalPrincipalPaise > 0
        ? Math.min(1, Math.max(0, effectivePaid / liability.originalPrincipalPaise))
        : 0;
      return { liability, outstandingPaise, paidPrincipalPaise: principalPaid, paidInterestPaise: interestPaid, progress };
    })
    .sort((a, b) => b.outstandingPaise - a.outstandingPaise);
}

export function totalLiabilities(doc: FinanceDocument, asOf: string): number {
  return liabilitySummaries(doc, asOf).reduce((sum, s) => {
    if (s.liability.ownership === 'personal') return sum + s.outstandingPaise;
    if (s.liability.ownership === 'household' && doc.settings.includeHouseholdInNetWorth) {
      return sum + s.outstandingPaise;
    }
    return sum;
  }, 0);
}

export function totalAssets(doc: FinanceDocument, asOf: string): number {
  let value = 0;
  for (const account of doc.accounts) {
    if (account.status === 'closed' || LIABILITY_TYPES.has(account.type)) continue;
    value += accountBalance(doc, account, asOf);
  }
  for (const s of investmentSummaries(doc, asOf)) value += s.valuePaise;
  return value;
}

export function netWorth(doc: FinanceDocument, asOf: string) {
  const assetsPaise = totalAssets(doc, asOf);
  const liabilitiesPaise = totalLiabilities(doc, asOf);
  return { assetsPaise, liabilitiesPaise, netWorthPaise: assetsPaise - liabilitiesPaise };
}

export function liquidAssets(doc: FinanceDocument, asOf: string): number {
  return doc.accounts
    .filter((a) => CASH_TYPES.has(a.type) && a.status === 'active')
    .reduce((sum, a) => sum + accountBalance(doc, a, asOf), 0);
}

/* ------------------------------------------------------------------ */
/* Reporting                                                           */
/* ------------------------------------------------------------------ */

export function expenseByCategory(doc: FinanceDocument, start: string, end: string): CategorySlice[] {
  const sums = new Map<string, { paise: number; count: number }>();
  const refunds = new Map<string, number>();
  for (const t of doc.transactions) {
    if (!inRange(t, start, end)) continue;
    if (isExpense(t)) {
      const id = t.categoryID ?? '__uncategorised__';
      const row = sums.get(id) ?? { paise: 0, count: 0 };
      row.paise += expenseAmount(t);
      row.count += 1;
      sums.set(id, row);
    } else if (t.type === 'refund' && t.categoryID) {
      refunds.set(t.categoryID, (refunds.get(t.categoryID) ?? 0) + t.amountPaise);
    }
  }
  for (const [id, value] of refunds) {
    const row = sums.get(id);
    if (row) row.paise = Math.max(0, row.paise - value);
  }
  const total = [...sums.values()].reduce((sum, r) => sum + r.paise, 0);
  return [...sums.entries()]
    .map(([id, row]) => {
      const category: FinanceCategory | undefined = doc.categories.find((c) => c.id === id);
      return {
        categoryID: id,
        name: category?.name ?? 'Uncategorised',
        group: category?.group ?? 'Other',
        paise: row.paise,
        count: row.count,
        share: total > 0 ? (row.paise / total) * 100 : 0
      };
    })
    .filter((s) => s.paise > 0)
    .sort((a, b) => b.paise - a.paise);
}

export function merchantBreakdown(doc: FinanceDocument, start: string, end: string) {
  const rows = new Map<string, { paise: number; count: number }>();
  for (const t of doc.transactions) {
    if (!inRange(t, start, end) || !isExpense(t)) continue;
    const name = t.merchant || doc.categories.find((c) => c.id === t.categoryID)?.name || 'Unknown';
    const row = rows.get(name) ?? { paise: 0, count: 0 };
    row.paise += expenseAmount(t);
    row.count += 1;
    rows.set(name, row);
  }
  return [...rows.entries()]
    .map(([merchant, row]) => ({ merchant, ...row }))
    .sort((a, b) => b.paise - a.paise);
}

export function monthlyCashflow(doc: FinanceDocument, months: string[]): MonthPoint[] {
  return months.map((month) => {
    const totals = monthTotals(doc, month);
    return {
      month: monthStart(month),
      incomePaise: totals.incomePaise,
      expensePaise: totals.expensePaise,
      netPaise: totals.netSavingsPaise
    };
  });
}

export function netWorthHistory(doc: FinanceDocument, start: string, end: string) {
  const points: Array<{
    date: string;
    assetsPaise: number;
    liabilitiesPaise: number;
    netWorthPaise: number;
    certainty: FinanceCertainty;
  }> = [];

  for (const month of monthsBetween(start, end)) {
    const date = monthEnd(month);
    if (date > end) continue;
    const snapshot = doc.snapshots.find((s) => s.date === date);
    if (snapshot) {
      points.push({
        date,
        assetsPaise: snapshot.assetsPaise,
        liabilitiesPaise: snapshot.liabilitiesPaise,
        netWorthPaise: snapshot.netWorthPaise,
        certainty: snapshot.certainty
      });
      continue;
    }
    const hasAny =
      doc.accounts.some((a) => a.openingDate <= date) ||
      doc.transactions.some((t) => t.date <= date) ||
      doc.investments.some((i) => (i.purchaseDate ?? i.createdAt.slice(0, 10)) <= date);
    if (!hasAny) continue;
    const nw = netWorth(doc, date);
    points.push({ date, ...nw, certainty: 'calculated' });
  }

  const known = new Set(points.map((p) => p.date));
  for (const s of doc.snapshots) {
    if (s.date >= start && s.date <= end && !known.has(s.date)) {
      points.push({
        date: s.date,
        assetsPaise: s.assetsPaise,
        liabilitiesPaise: s.liabilitiesPaise,
        netWorthPaise: s.netWorthPaise,
        certainty: s.certainty
      });
    }
  }
  return points.sort((a, b) => a.date.localeCompare(b.date));
}

export function timeline(doc: FinanceDocument) {
  const entries: Array<Record<string, unknown>> = [];
  for (const m of doc.milestones) {
    entries.push({
      date: String(m.date ?? ''),
      title: String(m.title ?? ''),
      detail: String(m.detail ?? ''),
      kind: String(m.kind ?? 'custom'),
      certainty: String(m.certainty ?? 'verified'),
      automatic: false
    });
  }
  const firstAccount = [...doc.accounts].sort((a, b) => a.openingDate.localeCompare(b.openingDate))[0];
  if (firstAccount) {
    entries.push({
      date: firstAccount.openingDate,
      title: `Opened ${firstAccount.name}`,
      detail: firstAccount.institution,
      kind: 'firstAccount',
      certainty: 'verified',
      automatic: true
    });
  }
  const firstIncome = [...doc.transactions].filter(isIncome).sort((a, b) => a.date.localeCompare(b.date))[0];
  if (firstIncome) {
    entries.push({
      date: firstIncome.date,
      title: 'First recorded income',
      detail: firstIncome.merchant,
      kind: 'firstIncome',
      certainty: 'calculated',
      amountPaise: firstIncome.amountPaise,
      automatic: true
    });
  }
  const firstInvestment = [...doc.investments].sort((a, b) =>
    (a.purchaseDate ?? '').localeCompare(b.purchaseDate ?? '')
  )[0];
  if (firstInvestment?.purchaseDate) {
    entries.push({
      date: firstInvestment.purchaseDate,
      title: 'First investment',
      detail: firstInvestment.name,
      kind: 'firstInvestment',
      certainty: 'verified',
      amountPaise: firstInvestment.investedPaise,
      automatic: true
    });
  }
  return entries.sort((a, b) => String(b.date).localeCompare(String(a.date)));
}

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */
/* ------------------------------------------------------------------ */

export function worstCertainty(values: FinanceCertainty[]): FinanceCertainty {
  if (!values.length) return 'unknown';
  const rank: Record<FinanceCertainty, number> = { verified: 3, calculated: 2, estimated: 1, unknown: 0 };
  return values.reduce((worst, c) => (rank[c] < rank[worst] ? c : worst), values[0]!);
}

export function categoryName(doc: FinanceDocument, categoryID: string | null | undefined): string {
  if (!categoryID) return 'Uncategorised';
  return doc.categories.find((c) => c.id === categoryID)?.name ?? 'Uncategorised';
}

export function accountName(doc: FinanceDocument, accountID: string | null | undefined): string {
  if (!accountID) return '';
  return doc.accounts.find((a) => a.id === accountID)?.name ?? '';
}
