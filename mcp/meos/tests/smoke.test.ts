import test from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { allTools } from '../src/tools/index.ts';
import { createHarness, payload } from './support/harness.ts';
import { addDays, todayKey } from '../src/utils/dates.ts';

test('tool registry invariants hold for every tool', () => {
  const names = new Set<string>();
  assert.ok(allTools.length >= 50, `expected a broad gateway, got ${allTools.length} tools`);
  for (const tool of allTools) {
    assert.match(tool.name, /^meos_[a-z0-9_]+$/);
    assert.equal(names.has(tool.name), false, `duplicate tool ${tool.name}`);
    names.add(tool.name);
    assert.ok(tool.description.length > 20, `${tool.name} needs a real description`);
    assert.ok(tool.scopes.length > 0, `${tool.name} needs scopes`);
    assert.ok(tool.title.length > 0);

    if (tool.destructive) {
      assert.ok(tool.scopes.includes('destructive'), `${tool.name} must require destructive scope`);
      assert.ok(tool.inputSchema?.confirm, `${tool.name} must accept confirm`);
    }
    if (tool.scopes.includes('write')) {
      assert.ok(tool.inputSchema, `${tool.name} must have an input schema`);
    }
    // Every schema must compile to a Zod object; a bad shape would break tools/list.
    assert.doesNotThrow(() => z.object(tool.inputSchema ?? {}), `${tool.name} schema is invalid`);
  }
});

test('remaining read tools return structured data', async () => {
  const h = await createHarness();
  try {
    const read = h.ctxFor('a', ['read', 'health']);
    const calls: Array<[string, Record<string, unknown>]> = [
      ['meos_goals_get', { goal_ref: 'short:0' }],
      ['meos_tasks_summary', {}],
      ['meos_finance_get_purchase', { id: 'buy1' }],
      ['meos_finance_list_categories', {}],
      ['meos_finance_get_purchase_summary', {}],
      ['meos_finance_get_net_worth', {}],
      ['meos_events_list_tags', {}],
      ['meos_memory_list', { limit: 5 }],
      ['meos_memory_get', { id: 'mem1' }],
      ['meos_notes_get', { id: 'note-normal' }],
      ['meos_health_list_daily_metrics', { limit: 5 }],
      ['meos_health_get_daily_metrics', { date: todayKey() }],
      ['meos_health_get_body_metrics', {}],
      ['meos_fitness_get_profile', {}],
      ['meos_fitness_get_goals', {}],
      ['meos_diet_list_recent_foods', { limit: 5 }],
      ['meos_diet_get_day_log', { date: todayKey() }],
      ['meos_knowledge_list_videos', {}],
      ['meos_get_settings', {}],
      ['meos_get_capabilities', {}]
    ];
    for (const [name, args] of calls) {
      const result = await h.call(read, name, args);
      assert.equal(result.isError, undefined, `${name} failed: ${JSON.stringify(result.structuredContent)}`);
      assert.equal((result.structuredContent as any).success, true, name);
    }
  } finally {
    await h.close();
  }
});

test('event list can expand recurrence inside a range', async () => {
  const h = await createHarness();
  try {
    const result = await h.call(h.ctxFor('a', ['read']), 'meos_events_list', {
      from: '2026-01-01',
      to: '2026-12-31',
      expand: true
    });
    const data = payload(result).data;
    assert.equal(data.expanded, true);
    assert.ok(data.items.some((e: any) => e.id === 'event-birthday' && e.date === '2026-05-20'));
    assert.ok(data.items.some((e: any) => e.id === 'event-trip' && e.date === todayKey()));
  } finally {
    await h.close();
  }
});

test('diet slot add, remove and clear round-trip', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const weekday = new Date(Date.UTC(Number(todayKey().slice(0, 4)), Number(todayKey().slice(5, 7)) - 1, Number(todayKey().slice(8, 10)))).getUTCDay();

    const added = payload(
      await h.call(ctx, 'meos_diet_add_food_to_slot', { weekday, meal: 'dinner', food_id: 'seed-food-1', quantity: 1 })
    ).data;
    assert.equal(added.items.length, 1);
    const itemId = added.items[0].id;

    const removed = payload(await h.call(ctx, 'meos_diet_remove_slot_food', { item_id: itemId })).data;
    assert.equal(removed.removed, true);

    const cleared = payload(await h.call(ctx, 'meos_diet_clear_meal_slot', { weekday, meal: 'breakfast' })).data;
    assert.equal(cleared.cleared, true);
  } finally {
    await h.close();
  }
});

test('knowledge videos can be added, updated and deleted into the bin', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive']);
    const added = payload(
      await h.call(ctx, 'meos_knowledge_add_video', {
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'A talk',
        category: 'tech'
      })
    ).data;
    assert.equal(added.video_id, 'dQw4w9WgXcQ');

    const updated = payload(await h.call(ctx, 'meos_knowledge_update_video', { id: added.id, watched: true, takeaway: 'Useful' })).data;
    assert.equal(updated.watched, true);
    assert.equal(updated.takeaway, 'Useful');

    const deleted = payload(await h.call(ctx, 'meos_knowledge_delete_video', { id: added.id, confirm: true })).data;
    assert.equal(deleted.deleted, true);
    const bin = payload(await h.call(ctx, 'meos_list_trash', {})).data;
    assert.ok(bin.items.some((e: any) => e.kind === 'watch'));
  } finally {
    await h.close();
  }
});

test('event delete and restore round-trips through the bin', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive']);
    const deleted = payload(await h.call(ctx, 'meos_events_delete', { id: 'event-trip', confirm: true })).data;
    const restored = payload(await h.call(ctx, 'meos_restore_from_trash', { entry_id: deleted.recycle_bin_entry })).data;
    assert.equal(restored.kind, 'event');
    const event = payload(await h.call(ctx, 'meos_events_get', { id: 'event-trip' })).data;
    assert.equal(event.title, 'Trip');
  } finally {
    await h.close();
  }
});

test('future dates are accepted for events but not past purchases', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const okEvent = await h.call(ctx, 'meos_events_create', { date: addDays(todayKey(), 30), title: 'Future' });
    assert.equal(payload(okEvent).success, true);
    const badPurchase = await h.call(ctx, 'meos_finance_add_purchase', {
      name: 'Time machine',
      price_inr: 10,
      category: 'other',
      bought_on: addDays(todayKey(), 10)
    });
    assert.equal((badPurchase.structuredContent as any).error.code, 'invalid_input');
  } finally {
    await h.close();
  }
});
