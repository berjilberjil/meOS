/**
 * Finance document mirrors.
 *
 * These are structural mirrors of `apps/apple/MeOS/Core/Finance/FinanceModels.swift`.
 * The live document is encrypted and owned by the native app; the MCP gateway
 * unlocks it with the owner's vault passphrase and must preserve unknown fields.
 *
 * Every non-optional Swift field must be present when the gateway creates a
 * record. Swift's synthesized Decodable does not fill in property defaults for
 * missing keys, so a partially-shaped object would make the whole module
 * unreadable in the app.
 */

import { nowStamp, todayKey } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';

export type FinanceAccountType =
  | 'savings' | 'current' | 'salary' | 'cash' | 'creditCard' | 'wallet'
  | 'fixedDeposit' | 'recurringDeposit' | 'brokerage' | 'investment' | 'other';

export type FinanceAccountStatus = 'active' | 'archived' | 'closed';
export type FinanceCategoryKind = 'income' | 'expense';
export type FinanceTxnType =
  | 'income' | 'expense' | 'transfer' | 'refund'
  | 'investmentPurchase' | 'investmentSale'
  | 'loanDisbursement' | 'loanRepayment'
  | 'interest' | 'dividend' | 'fee' | 'tax' | 'adjustment';
export type FinanceDirection = 'inflow' | 'outflow';
export type FinanceSource = 'manual' | 'imported' | 'recurring' | 'demo' | 'adjustment' | 'migration';
export type FinanceVerification = 'unverified' | 'needsReview' | 'verified' | 'reconciled';
export type FinancePaymentMethod =
  | 'upi' | 'card' | 'netBanking' | 'cash' | 'autoDebit' | 'cheque' | 'bankTransfer' | 'other';
export type FinanceCertainty = 'verified' | 'calculated' | 'estimated' | 'unknown';
export type FinanceAssetClass =
  | 'equity' | 'mutualFund' | 'etf' | 'gold' | 'silver'
  | 'fixedDeposit' | 'recurringDeposit' | 'bond' | 'other';
export type FinanceLiabilityKind =
  | 'creditCard' | 'personalLoan' | 'educationLoan' | 'homeLoan'
  | 'goldLoan' | 'vehicleLoan' | 'informal' | 'other';
export type FinanceOwnership = 'personal' | 'household' | 'shared';
export type FinanceAuditAction =
  | 'created' | 'updated' | 'deleted' | 'imported' | 'matched' | 'reconciled' | 'restored' | 'bulkUpdated';

export interface FinanceSettings {
  trackingStartDate: string;
  birthDate?: string | null;
  currency: string;
  locale: string;
  includeHouseholdInNetWorth: boolean;
  emergencyFundMonths: number;
  hideBalances: boolean;
  demoMode: boolean;
  demoSeededAt?: string | null;
  [key: string]: unknown;
}

export interface FinanceAccount {
  id: string;
  name: string;
  institution: string;
  type: FinanceAccountType;
  currency: string;
  openingDate: string;
  openingBalancePaise: number;
  statementBalancePaise?: number | null;
  statementBalanceOn?: string | null;
  statementBalanceSource: FinanceCertainty;
  creditLimitPaise?: number | null;
  status: FinanceAccountStatus;
  notes: string;
  lastReconciledOn?: string | null;
  isDemo: boolean;
  createdAt: string;
  updatedAt: string;
  [key: string]: unknown;
}

export interface FinanceCategory {
  id: string;
  name: string;
  kind: FinanceCategoryKind;
  group: string;
  icon: string;
  parentID?: string | null;
  isSystem: boolean;
  archived: boolean;
  isDemo: boolean;
  createdAt: string;
  [key: string]: unknown;
}

export interface FinanceTransaction {
  id: string;
  date: string;
  postedDate?: string | null;
  amountPaise: number;
  currency: string;
  direction: FinanceDirection;
  type: FinanceTxnType;
  accountID: string;
  transferAccountID?: string | null;
  categoryID?: string | null;
  subcategoryID?: string | null;
  merchant: string;
  paymentMethod: FinancePaymentMethod;
  note: string;
  reference: string;
  tags: string[];
  source: FinanceSource;
  statementID?: string | null;
  importBatchID?: string | null;
  verification: FinanceVerification;
  transferID?: string | null;
  linkedTransactionID?: string | null;
  investmentID?: string | null;
  liabilityID?: string | null;
  principalPaise?: number | null;
  interestPaise?: number | null;
  costBasisPaise?: number | null;
  realisedGainPaise?: number | null;
  isDemo: boolean;
  createdAt: string;
  updatedAt: string;
  [key: string]: unknown;
}

export interface FinanceTransfer {
  id: string;
  fromAccountID: string;
  toAccountID: string;
  amountPaise: number;
  date: string;
  feePaise: number;
  reference: string;
  note: string;
  fromTransactionID?: string | null;
  toTransactionID?: string | null;
  feeTransactionID?: string | null;
  reconciled: boolean;
  isDemo: boolean;
  createdAt: string;
  [key: string]: unknown;
}

export interface FinanceInvestment {
  id: string;
  name: string;
  assetClass: FinanceAssetClass;
  institution: string;
  units?: number | null;
  purchaseDate?: string | null;
  purchasePricePaise?: number | null;
  investedPaise: number;
  currentValuePaise: number;
  currentValueOn: string;
  realisedGainPaise: number;
  dividendsPaise: number;
  interestPaise: number;
  notes: string;
  accountID?: string | null;
  archived: boolean;
  isDemo: boolean;
  createdAt: string;
  updatedAt: string;
  [key: string]: unknown;
}

export interface FinanceValuation {
  id: string;
  investmentID: string;
  date: string;
  valuePaise: number;
  source: 'manual' | 'statement' | 'provider';
  note: string;
  isDemo: boolean;
  createdAt: string;
  [key: string]: unknown;
}

export interface FinanceLiability {
  id: string;
  name: string;
  kind: FinanceLiabilityKind;
  lender: string;
  ownership: FinanceOwnership;
  originalPrincipalPaise: number;
  outstandingPaise: number;
  asOf: string;
  interestRateBps: number;
  emiPaise: number;
  dueDay: number;
  startDate: string;
  maturityDate?: string | null;
  accountID?: string | null;
  notes: string;
  closed: boolean;
  isDemo: boolean;
  createdAt: string;
  updatedAt: string;
  [key: string]: unknown;
}

export interface FinanceDebtPayment {
  id: string;
  liabilityID: string;
  transactionID?: string | null;
  date: string;
  amountPaise: number;
  principalPaise: number;
  interestPaise: number;
  note: string;
  isDemo: boolean;
  createdAt: string;
  [key: string]: unknown;
}

export interface FinanceAuditEntry {
  id: string;
  entityType: string;
  entityID: string;
  action: FinanceAuditAction;
  field?: string | null;
  oldValue?: string | null;
  newValue?: string | null;
  reason: string;
  actor: string;
  at: string;
  sourceTransactionID?: string | null;
  isDemo: boolean;
  [key: string]: unknown;
}

export interface FinanceSnapshot {
  id: string;
  date: string;
  netWorthPaise: number;
  assetsPaise: number;
  liabilitiesPaise: number;
  certainty: FinanceCertainty;
  note: string;
  isDemo: boolean;
  [key: string]: unknown;
}

export interface FinanceDocument {
  schemaVersion: number;
  updatedAt: string;
  settings: FinanceSettings;
  accounts: FinanceAccount[];
  categories: FinanceCategory[];
  transactions: FinanceTransaction[];
  transfers: FinanceTransfer[];
  budgets: Array<Record<string, unknown>>;
  investments: FinanceInvestment[];
  valuations: FinanceValuation[];
  liabilities: FinanceLiability[];
  debtPayments: FinanceDebtPayment[];
  goals: Array<Record<string, unknown>>;
  recurring: Array<Record<string, unknown>>;
  statements: Array<Record<string, unknown>>;
  importBatches: Array<Record<string, unknown>>;
  importRows: Array<Record<string, unknown>>;
  reconciliations: Array<Record<string, unknown>>;
  audit: FinanceAuditEntry[];
  snapshots: FinanceSnapshot[];
  milestones: Array<Record<string, unknown>>;
  [key: string]: unknown;
}

export const DEFAULT_FINANCE_SETTINGS: FinanceSettings = {
  trackingStartDate: todayKey(),
  birthDate: null,
  currency: 'INR',
  locale: 'en_IN',
  includeHouseholdInNetWorth: false,
  emergencyFundMonths: 6,
  hideBalances: false,
  demoMode: false,
  demoSeededAt: null
};

export function defaultFinance(): FinanceDocument {
  return {
    schemaVersion: 1,
    updatedAt: nowStamp(),
    settings: { ...DEFAULT_FINANCE_SETTINGS },
    accounts: [],
    categories: [],
    transactions: [],
    transfers: [],
    budgets: [],
    investments: [],
    valuations: [],
    liabilities: [],
    debtPayments: [],
    goals: [],
    recurring: [],
    statements: [],
    importBatches: [],
    importRows: [],
    reconciliations: [],
    audit: [],
    snapshots: [],
    milestones: []
  };
}

export function normalizeFinance(raw: unknown): FinanceDocument {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return defaultFinance();
  const source = raw as Record<string, unknown>;
  const base = defaultFinance();
  const settings = source.settings && typeof source.settings === 'object'
    ? { ...base.settings, ...(source.settings as Record<string, unknown>) }
    : base.settings;
  const arr = (key: keyof FinanceDocument): any[] =>
    Array.isArray(source[key as string]) ? (source[key as string] as any[]) : [];
  return {
    ...base,
    ...source,
    schemaVersion: typeof source.schemaVersion === 'number' ? source.schemaVersion : 1,
    updatedAt: typeof source.updatedAt === 'string' ? source.updatedAt : nowStamp(),
    settings: settings as FinanceSettings,
    accounts: arr('accounts') as FinanceAccount[],
    categories: arr('categories') as FinanceCategory[],
    transactions: arr('transactions') as FinanceTransaction[],
    transfers: arr('transfers') as FinanceTransfer[],
    budgets: arr('budgets'),
    investments: arr('investments') as FinanceInvestment[],
    valuations: arr('valuations') as FinanceValuation[],
    liabilities: arr('liabilities') as FinanceLiability[],
    debtPayments: arr('debtPayments') as FinanceDebtPayment[],
    goals: arr('goals'),
    recurring: arr('recurring'),
    statements: arr('statements'),
    importBatches: arr('importBatches'),
    importRows: arr('importRows'),
    reconciliations: arr('reconciliations'),
    audit: arr('audit') as FinanceAuditEntry[],
    snapshots: arr('snapshots') as FinanceSnapshot[],
    milestones: arr('milestones')
  };
}

export function makeAccount(input: {
  name: string;
  institution?: string;
  type: FinanceAccountType;
  openingDate?: string;
  openingBalancePaise?: number;
  creditLimitPaise?: number | null;
  notes?: string;
}): FinanceAccount {
  const ts = nowStamp();
  return {
    id: newId(),
    name: input.name,
    institution: input.institution ?? '',
    type: input.type,
    currency: 'INR',
    openingDate: input.openingDate ?? todayKey(),
    openingBalancePaise: input.openingBalancePaise ?? 0,
    statementBalancePaise: null,
    statementBalanceOn: null,
    statementBalanceSource: 'verified',
    creditLimitPaise: input.creditLimitPaise ?? null,
    status: 'active',
    notes: input.notes ?? '',
    lastReconciledOn: null,
    isDemo: false,
    createdAt: ts,
    updatedAt: ts
  };
}

export function makeTransaction(input: {
  date: string;
  amountPaise: number;
  direction: FinanceDirection;
  type: FinanceTxnType;
  accountID: string;
  categoryID?: string | null;
  merchant?: string;
  paymentMethod?: FinancePaymentMethod;
  note?: string;
  reference?: string;
  tags?: string[];
  transferAccountID?: string | null;
  transferID?: string | null;
  linkedTransactionID?: string | null;
  investmentID?: string | null;
  liabilityID?: string | null;
  principalPaise?: number | null;
  interestPaise?: number | null;
  costBasisPaise?: number | null;
  realisedGainPaise?: number | null;
  source?: FinanceSource;
  verification?: FinanceVerification;
}): FinanceTransaction {
  const ts = nowStamp();
  return {
    id: newId(),
    date: input.date,
    postedDate: null,
    amountPaise: input.amountPaise,
    currency: 'INR',
    direction: input.direction,
    type: input.type,
    accountID: input.accountID,
    transferAccountID: input.transferAccountID ?? null,
    categoryID: input.categoryID ?? null,
    subcategoryID: null,
    merchant: input.merchant ?? '',
    paymentMethod: input.paymentMethod ?? 'other',
    note: input.note ?? '',
    reference: input.reference ?? '',
    tags: input.tags ?? [],
    source: input.source ?? 'manual',
    statementID: null,
    importBatchID: null,
    verification: input.verification ?? 'verified',
    transferID: input.transferID ?? null,
    linkedTransactionID: input.linkedTransactionID ?? null,
    investmentID: input.investmentID ?? null,
    liabilityID: input.liabilityID ?? null,
    principalPaise: input.principalPaise ?? null,
    interestPaise: input.interestPaise ?? null,
    costBasisPaise: input.costBasisPaise ?? null,
    realisedGainPaise: input.realisedGainPaise ?? null,
    isDemo: false,
    createdAt: ts,
    updatedAt: ts
  };
}

export function makeAudit(
  entityType: string,
  entityID: string,
  action: FinanceAuditAction,
  reason: string,
  input: { field?: string | null; oldValue?: string | null; newValue?: string | null; sourceTransactionID?: string | null } = {}
): FinanceAuditEntry {
  return {
    id: newId(),
    entityType,
    entityID,
    action,
    field: input.field ?? null,
    oldValue: input.oldValue ?? null,
    newValue: input.newValue ?? null,
    reason,
    actor: 'MCP',
    at: nowStamp(),
    sourceTransactionID: input.sourceTransactionID ?? null,
    isDemo: false
  };
}

export function makeInvestment(input: {
  name: string;
  assetClass: FinanceAssetClass;
  institution?: string;
  units?: number | null;
  purchaseDate?: string | null;
  investedPaise: number;
  currentValuePaise: number;
  currentValueOn?: string;
  notes?: string;
}): FinanceInvestment {
  const ts = nowStamp();
  return {
    id: newId(),
    name: input.name,
    assetClass: input.assetClass,
    institution: input.institution ?? '',
    units: input.units ?? null,
    purchaseDate: input.purchaseDate ?? null,
    purchasePricePaise: null,
    investedPaise: input.investedPaise,
    currentValuePaise: input.currentValuePaise,
    currentValueOn: input.currentValueOn ?? todayKey(),
    realisedGainPaise: 0,
    dividendsPaise: 0,
    interestPaise: 0,
    notes: input.notes ?? '',
    accountID: null,
    archived: false,
    isDemo: false,
    createdAt: ts,
    updatedAt: ts
  };
}

export function makeLiability(input: {
  name: string;
  kind: FinanceLiabilityKind;
  lender?: string;
  ownership?: FinanceOwnership;
  originalPrincipalPaise: number;
  outstandingPaise: number;
  asOf?: string;
  interestRateBps?: number;
  emiPaise?: number;
  dueDay?: number;
  startDate?: string;
  maturityDate?: string | null;
  accountID?: string | null;
  notes?: string;
}): FinanceLiability {
  const ts = nowStamp();
  return {
    id: newId(),
    name: input.name,
    kind: input.kind,
    lender: input.lender ?? '',
    ownership: input.ownership ?? 'personal',
    originalPrincipalPaise: input.originalPrincipalPaise,
    outstandingPaise: input.outstandingPaise,
    asOf: input.asOf ?? todayKey(),
    interestRateBps: input.interestRateBps ?? 0,
    emiPaise: input.emiPaise ?? 0,
    dueDay: input.dueDay ?? 5,
    startDate: input.startDate ?? todayKey(),
    maturityDate: input.maturityDate ?? null,
    accountID: input.accountID ?? null,
    notes: input.notes ?? '',
    closed: false,
    isDemo: false,
    createdAt: ts,
    updatedAt: ts
  };
}
