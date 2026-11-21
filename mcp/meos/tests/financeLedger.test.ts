import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';
import type { FinanceDocument } from '../src/schemas/finance.ts';

const call = async (h: Awaited<ReturnType<typeof createHarness>>, name: string, args: any = {}, scopes: any = ['read']) =>
  h.call(h.ctxFor('a', scopes), name, args);

test('ledger summary derives net worth from recorded accounts, not Fold', async () => {
  const h = await createHarness();
  try {
    const data = payload(await call(h, 'meos_finance_ledger_get_summary')).data;
    assert.equal(data.available, true);
    assert.equal(data.net_worth.paise, 9_030_000);
    assert.equal(data.assets.paise, 9_450_000);
    assert.equal(data.liabilities.paise, 420_000);
    assert.equal(data.liquid_cash.paise, 8_250_000);
    assert.equal(data.this_month.income_paise, 10_000_000);
    assert.equal(data.this_month.expenses_paise, 670_000);
    assert.equal(data.this_month.net_savings_paise, 9_330_000);
    assert.equal(data.investments.value_paise, 1_200_000);
    assert.equal(data.investments.invested_paise, 1_000_000);
    assert.equal(data.counts.transactions, 8);
  } finally {
    await h.close();
  }
});

test('accounts show signed balances and available credit, never a full number', async () => {
  const h = await createHarness();
  try {
    const data = payload(await call(h, 'meos_finance_ledger_list_accounts')).data;
    const bank = data.accounts.find((a: any) => a.id === 'acct-bank');
    const card = data.accounts.find((a: any) => a.id === 'acct-card');
    assert.equal(bank.balance_paise, 8_250_000);
    assert.equal(card.balance_paise, 0);
    assert.equal(card.available_credit_paise, 5_000_000);
    assert.equal(JSON.stringify(data).includes('account_number'), false);
  } finally {
    await h.close();
  }
});

test('transfers are labelled and filtered, never counted as spend', async () => {
  const h = await createHarness();
  try {
    const transfers = payload(
      await call(h, 'meos_finance_ledger_list_transactions', { type: 'transfer' })
    ).data;
    assert.equal(transfers.matching, 2);
    assert.ok(transfers.items.every((t: any) => t.is_transfer === true && t.is_expense === false));

    const food = payload(await call(h, 'meos_finance_ledger_list_transactions', { merchant: 'Cafe' })).data;
    assert.equal(food.matching, 2);
    assert.ok(food.items.every((t: any) => t.category === 'Food'));
  } finally {
    await h.close();
  }
});

test('spending excludes investment and transfers, subtracts refunds, separates loan interest', async () => {
  const h = await createHarness();
  try {
    const data = payload(await call(h, 'meos_finance_ledger_get_spending')).data;
    assert.equal(data.expenses_paise, 670_000);
    const food = data.by_category.find((c: any) => c.category === 'Food');
    assert.equal(food.amount_paise, 650_000);
    assert.equal(data.by_category.some((c: any) => c.category === 'Investment'), false);
    const loan = data.by_category.find((c: any) => c.category === 'Uncategorised');
    assert.equal(loan.amount_paise, 20_000);
  } finally {
    await h.close();
  }
});

test('budget actuals use the same expense rules', async () => {
  const h = await createHarness();
  try {
    const data = payload(await call(h, 'meos_finance_ledger_list_budgets')).data;
    assert.equal(data.budgets.length, 1);
    assert.equal(data.budgets[0].actual_paise, 650_000);
    assert.equal(data.budgets[0].remaining_paise, -50_000);
    assert.equal(data.budgets[0].progress_percent, 108.3);
  } finally {
    await h.close();
  }
});

test('adds an account and a transaction with a complete Swift-shaped record', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const addedAccount = payload(
      await h.call(ctx, 'meos_finance_ledger_add_account', {
        name: 'Cash wallet',
        type: 'cash',
        opening_balance_inr: 2000
      })
    ).data.account;
    assert.equal(addedAccount.balance_paise, 200_000);

    const added = payload(
      await h.call(ctx, 'meos_finance_ledger_add_transaction', {
        date: '2026-11-20',
        amount_inr: '₹250.50',
        type: 'expense',
        account_id: addedAccount.id,
        category_id: 'cat-food',
        merchant: 'Chai stall',
        payment_method: 'cash'
      })
    ).data.transaction;
    assert.equal(added.amount_paise, 25_050);
    assert.equal(added.is_expense, true);

    const stored = await ctx.services.store.read<FinanceDocument>('meos.finance');
    const row = stored?.transactions.find((t) => t.id === added.id);
    assert.ok(row);
    for (const key of [
      'id', 'date', 'amountPaise', 'currency', 'direction', 'type', 'accountID',
      'merchant', 'paymentMethod', 'note', 'reference', 'tags', 'source',
      'verification', 'isDemo', 'createdAt', 'updatedAt'
    ]) {
      assert.ok(Object.prototype.hasOwnProperty.call(row, key), `missing ${key}`);
    }
    assert.ok(stored?.audit.some((a) => a.entityID === added.id && a.action === 'created'));
  } finally {
    await h.close();
  }
});

test('adds a linked transfer without changing net worth or spend', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const savings = payload(
      await h.call(ctx, 'meos_finance_ledger_add_account', {
        name: 'Rainy day', type: 'savings', opening_balance_inr: 0, opening_date: '2026-01-01'
      })
    ).data.account;

    const before = payload(await h.call(ctx, 'meos_finance_ledger_get_summary')).data;
    const transfer = payload(
      await h.call(ctx, 'meos_finance_ledger_add_transfer', {
        from_account_id: 'acct-bank',
        to_account_id: savings.id,
        amount_inr: 1000,
        date: '2026-11-20'
      })
    ).data.transfer;
    assert.equal(transfer.amount_paise, 100_000);

    const after = payload(await h.call(ctx, 'meos_finance_ledger_get_summary')).data;
    assert.equal(after.net_worth.paise, before.net_worth.paise);
    assert.equal(after.this_month.expenses_paise, before.this_month.expenses_paise);
    assert.equal(after.this_month.income_paise, before.this_month.income_paise);

    const rows = payload(
      await h.call(ctx, 'meos_finance_ledger_list_transactions', { type: 'transfer' })
    ).data;
    assert.equal(rows.matching, 4);
    const pair = rows.items.filter((t: any) => t.transfer_id === transfer.id);
    assert.equal(pair.length, 2);
  } finally {
    await h.close();
  }
});

test('corrections append audit entries with old and new values', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const updated = payload(
      await h.call(ctx, 'meos_finance_ledger_update_transaction', {
        id: 'txn-food',
        note: 'Corrected payee',
        category_id: 'cat-food',
        reason: 'Statement description was ambiguous'
      })
    ).data.transaction;
    assert.equal(updated.note, 'Corrected payee');
    const detail = payload(await h.call(ctx, 'meos_finance_ledger_get_transaction', { id: 'txn-food' })).data;
    const audit = detail.audit.find((a: any) => a.field === 'note');
    assert.ok(audit);
    assert.equal(audit.old_value, '');
    assert.equal(audit.new_value, 'Corrected payee');
    assert.equal(audit.actor, 'MCP');
  } finally {
    await h.close();
  }
});

test('MCP-created investments, valuations and liabilities are Swift-decodable shapes', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const investment = payload(await h.call(ctx, 'meos_finance_ledger_add_investment', {
      name: 'Gold ETF',
      asset_class: 'etf',
      invested_inr: 5000,
      current_value_inr: 5600,
      value_date: '2026-11-20',
      institution: 'Meridian'
    })).data.investment;
    for (const key of [
      'id', 'name', 'assetClass', 'institution', 'investedPaise', 'currentValuePaise',
      'currentValueOn', 'realisedGainPaise', 'dividendsPaise', 'interestPaise',
      'notes', 'archived', 'isDemo', 'createdAt', 'updatedAt'
    ]) {
      assert.ok(Object.prototype.hasOwnProperty.call(investment, key), `investment missing ${key}`);
    }

    const valuation = payload(await h.call(ctx, 'meos_finance_ledger_add_valuation', {
      investment_id: investment.id,
      value_inr: 5800,
      date: '2026-11-21',
      source: 'manual'
    })).data;
    assert.equal(valuation.value_paise, 580_000);

    const liability = payload(await h.call(ctx, 'meos_finance_ledger_add_liability', {
      name: 'Camera loan',
      kind: 'personalLoan',
      original_principal_inr: 20000,
      outstanding_inr: 15000,
      interest_rate_percent: 11.5,
      emi_inr: 2000
    })).data.liability;
    for (const key of [
      'id', 'name', 'kind', 'lender', 'ownership', 'originalPrincipalPaise',
      'outstandingPaise', 'asOf', 'interestRateBps', 'emiPaise', 'dueDay',
      'startDate', 'notes', 'closed', 'isDemo', 'createdAt', 'updatedAt'
    ]) {
      assert.ok(Object.prototype.hasOwnProperty.call(liability, key), `liability missing ${key}`);
    }
    assert.equal(liability.interestRateBps, 1150);

    const holdings = payload(await h.call(ctx, 'meos_finance_ledger_get_investments')).data;
    assert.equal(holdings.value_paise, 1_780_000);
    assert.equal(holdings.holdings.length, 2);
  } finally {
    await h.close();
  }
});

test('MCP-created transfers are complete linked pairs', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const savings = payload(await h.call(ctx, 'meos_finance_ledger_add_account', {
      name: 'Savings', type: 'savings', opening_balance_inr: 0, opening_date: '2026-01-01'
    })).data.account;
    const transfer = payload(await h.call(ctx, 'meos_finance_ledger_add_transfer', {
      from_account_id: 'acct-bank', to_account_id: savings.id, amount_inr: 500, date: '2026-11-20'
    })).data.transfer;

    const stored = await ctx.services.store.read<FinanceDocument>('meos.finance');
    const legs = stored!.transactions.filter((t) => t.transferID === transfer.id);
    assert.equal(legs.length, 2);
    assert.equal(legs[0]!.linkedTransactionID, legs[1]!.id);
    assert.equal(legs[1]!.linkedTransactionID, legs[0]!.id);
    const record = stored!.transfers.find((t) => t.id === transfer.id);
    assert.ok(record);
    for (const key of ['id', 'fromAccountID', 'toAccountID', 'amountPaise', 'date', 'feePaise', 'reference', 'note', 'reconciled', 'isDemo', 'createdAt']) {
      assert.ok(Object.prototype.hasOwnProperty.call(record, key), `transfer missing ${key}`);
    }
  } finally {
    await h.close();
  }
});

test('read-only clients cannot write finance', async () => {
  const h = await createHarness();
  try {
    const result = await h.call(h.ctxFor('a', ['read']), 'meos_finance_ledger_add_account', {
      name: 'Nope', type: 'cash'
    });
    assert.equal(errorCode(result), 'forbidden');
  } finally {
    await h.close();
  }
});

test('one owner cannot read another owner finance ledger', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('b', ['read']), 'meos_finance_ledger_get_summary')).data;
    assert.equal(data.available, false);
    assert.equal(data.counts.accounts, 0);
  } finally {
    await h.close();
  }
});

test('investment and liability tools read the ledger rather than inventing holdings', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const inv = payload(await h.call(ctx, 'meos_finance_ledger_get_investments')).data;
    assert.equal(inv.value_paise, 1_200_000);
    assert.equal(inv.holdings[0].name, 'Index fund');
    assert.equal(inv.holdings[0].unrealised_paise, 200_000);
    assert.equal(inv.certainty, 'verified');

    const liabilities = payload(await h.call(ctx, 'meos_finance_ledger_get_liabilities')).data;
    assert.equal(liabilities.liabilities[0].outstanding_paise, 420_000);
    assert.equal(liabilities.liabilities[0].interest_rate_percent, 9.5);
  } finally {
    await h.close();
  }
});

test('net worth history returns dated points with certainty', async () => {
  const h = await createHarness();
  try {
    const data = payload(
      await call(h, 'meos_finance_ledger_get_net_worth', { months: 6 })
    ).data;
    assert.equal(data.net_worth_paise, 9_030_000);
    assert.ok(Array.isArray(data.history));
    assert.ok(data.history.length >= 1);
    assert.ok(['verified', 'calculated', 'estimated', 'unknown'].includes(data.history[0].certainty));
  } finally {
    await h.close();
  }
});
