import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';

test('finance summary uses Fold values verbatim and never fabricates them', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const result = await h.call(ctx, 'meos_finance_get_summary', {});
    const data = payload(result).data;
    assert.equal(data.linked, true);
    assert.equal(data.net_worth, 1234567);
    assert.equal(data.liquid, 200000);
    assert.equal(data.investments, 1100000);
    assert.equal(data.debt, 65433);
    assert.equal(data.spent_this_month, 42000);
    assert.equal(data.provenance.balances, 'Fold snapshot stored in meos.fold');
    assert.equal(payload(result).metadata.source_kind, 'synced_external_snapshot');
  } finally {
    await h.close();
  }
});

test('an unlinked Fold snapshot is reported as unavailable, not zero', async () => {
  const h = await createHarness({ withoutFoldForB: true });
  try {
    const result = await h.call(h.ctxFor('b', ['read']), 'meos_finance_get_summary', {});
    const data = payload(result).data;
    assert.equal(data.linked, false);
    assert.equal('net_worth' in data, false);
    assert.equal(data.purchases.monthly_burn_inr, 0);
  } finally {
    await h.close();
  }
});

test('accounts are masked and investments expose totals only', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const accounts = payload(await h.call(ctx, 'meos_finance_list_accounts', {})).data;
    assert.equal(accounts.accounts.length, 2);
    assert.equal(accounts.accounts[0].masked_number, '••••1234');
    assert.equal(JSON.stringify(accounts).includes('"1234"'), false);

    const inv = payload(await h.call(ctx, 'meos_finance_get_investments', {})).data;
    assert.equal(inv.investments_total, 1100000);
    assert.equal(inv.stocks_value, 600000);
    assert.equal(inv.mutual_funds_value, 500000);
    assert.equal(inv.holdings_available, false);
  } finally {
    await h.close();
  }
});

test('spending separates refunds and interest from real spend', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read']), 'meos_finance_get_spending', {})).data;
    assert.deepEqual(data.by_category, [{ category: 'food', amount: 12000 }]);
    assert.deepEqual(data.non_spend, [
      { category: 'refunds', amount: 3000 },
      { category: 'interest', amount: 500 }
    ]);
  } finally {
    await h.close();
  }
});

test('purchase list, add, update and recycle-bin delete', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive']);
    const list = payload(await h.call(ctx, 'meos_finance_list_purchases', {})).data;
    assert.deepEqual(list.items.map((i: any) => i.id), ['buy1']);
    assert.equal(list.items[0].price_inr, 2499);
    assert.equal(list.items[0].roi.paid_off, false);

    const withRetired = payload(await h.call(ctx, 'meos_finance_list_purchases', { include_retired: true })).data;
    assert.equal(withRetired.items.length, 2);

    const added = await h.call(ctx, 'meos_finance_add_purchase', {
      name: 'Mechanical keyboard',
      price_inr: '₹7,499',
      category: 'gadgets',
      roi_months: 24,
      confirm: true
    });
    const item = payload(added).data;
    assert.equal(item.price_inr, 7499);
    assert.equal(item.category, 'gadgets');

    const updated = payload(
      await h.call(ctx, 'meos_finance_update_purchase', { id: item.id, retired: true, note: 'Sold', confirm: true })
    ).data;
    assert.equal(updated.retired, true);
    assert.equal(updated.note, 'Sold');

    const del = await h.call(ctx, 'meos_finance_delete_purchase', { id: item.id, confirm: true });
    assert.equal(payload(del).data.deleted, true);
    const remaining = payload(await h.call(ctx, 'meos_finance_list_purchases', { include_retired: true })).data;
    assert.equal(remaining.items.some((i: any) => i.id === item.id), false);

    const trash = payload(await h.call(ctx, 'meos_list_trash', {})).data;
    assert.equal(trash.items.some((e: any) => e.kind === 'belonging'), true);
  } finally {
    await h.close();
  }
});

test('purchase input is validated', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const badCategory = await h.call(ctx, 'meos_finance_add_purchase', {
      name: 'Thing',
      price_inr: 100,
      category: 'spaceship',
      confirm: true
    });
    assert.equal(errorCode(badCategory), 'invalid_input');

    const badLink = await h.call(ctx, 'meos_finance_add_purchase', {
      name: 'Thing',
      price_inr: 100,
      category: 'other',
      link: 'javascript:alert(1)',
      confirm: true
    });
    assert.equal(errorCode(badLink), 'invalid_input');
  } finally {
    await h.close();
  }
});
