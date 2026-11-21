import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';
import { nextOccurrence, occurrences } from '../src/utils/recurrence.ts';
import { addDays, todayKey } from '../src/utils/dates.ts';

test('event detail projects recurrence without exposing media bytes', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const birthday = payload(await h.call(ctx, 'meos_events_get', { id: 'event-birthday' })).data;
    assert.equal(birthday.recurrence_description, 'Every year');
    assert.equal(birthday.next_occurrence, nextOccurrence({ date: '1990-05-20', recurrence: { unit: 'yearly', interval: 1 } }, todayKey()));
    assert.ok(birthday.upcoming_occurrences.length >= 1);

    const trip = payload(await h.call(ctx, 'meos_events_get', { id: 'event-trip' })).data;
    assert.equal(trip.media_count, 1);
    assert.equal(JSON.stringify(trip).includes('r2Key'), false);
    assert.equal(JSON.stringify(trip).includes('event-media'), false);
  } finally {
    await h.close();
  }
});

test('monthly recurrence clamps the day to each month, always from the anchor', () => {
  const event = { date: '2026-01-31', recurrence: { unit: 'monthly' as const, interval: 1 } };
  assert.deepEqual(occurrences(event, '2026-01-31', '2026-04-30'), [
    '2026-01-31',
    '2026-02-28',
    '2026-03-31',
    '2026-04-30'
  ]);
});

test('a yearly 29 February birthday returns on the next leap year', () => {
  const event = { date: '2024-02-29', recurrence: { unit: 'yearly' as const, interval: 1 } };
  assert.equal(nextOccurrence(event, '2026-01-01'), '2026-02-28');
  assert.equal(nextOccurrence(event, '2027-03-01'), '2028-02-29');
});

test('upcoming expands occurrences inside the horizon', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read']), 'meos_events_get_upcoming', { days: 30 })).data;
    const trip = data.items.find((e: any) => e.id === 'event-trip');
    assert.equal(trip.occurrence, todayKey());
    assert.equal(trip.days_until, 0);
    assert.equal(data.items.some((e: any) => e.id === 'event-birthday'), false);
  } finally {
    await h.close();
  }
});

test('updating one event preserves its reminders and every other event', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const updated = payload(await h.call(ctx, 'meos_events_update', { id: 'event-trip', title: 'Trip to Goa' })).data;
    assert.equal(updated.event.title, 'Trip to Goa');
    assert.deepEqual(updated.event.reminders, ['sameDay']);

    const birthday = payload(await h.call(ctx, 'meos_events_get', { id: 'event-birthday' })).data;
    assert.deepEqual(birthday.reminders, ['oneWeek', 'sameDay']);
  } finally {
    await h.close();
  }
});

test('setting reminders changes only the named event', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const set = payload(await h.call(ctx, 'meos_reminders_set', { event_id: 'event-trip', reminders: ['oneDay', 'oneWeek'] })).data;
    assert.deepEqual(set.reminders.map((r: any) => r.lead), ['oneDay', 'oneWeek']);

    const birthday = payload(await h.call(ctx, 'meos_events_get', { id: 'event-birthday' })).data;
    assert.deepEqual(birthday.reminders, ['oneWeek', 'sameDay']);
  } finally {
    await h.close();
  }
});

test('reminder plan lists the soonest fire for each lead', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read']), 'meos_reminders_list', { days: 365 })).data;
    assert.ok(data.items.some((r: any) => r.event_id === 'event-birthday' && r.lead === 'oneWeek'));
    assert.ok(data.total_matching >= 2);
  } finally {
    await h.close();
  }
});

test('creating an event validates tags and stores recurrence/reminders', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const bad = await h.call(ctx, 'meos_events_create', { date: todayKey(), title: 'X', tag_ids: ['nope'] });
    assert.equal(errorCode(bad), 'invalid_input');

    const good = payload(
      await h.call(ctx, 'meos_events_create', {
        date: addDays(todayKey(), 3),
        title: 'Dentist',
        time: '11:00',
        tag_ids: ['personal'],
        recurrence: { unit: 'monthly', interval: 2 },
        reminders: ['oneDay']
      })
    ).data;
    assert.equal(good.event.recurrence.unit, 'monthly');
    assert.equal(good.event.recurrence.interval, 2);
    assert.deepEqual(good.event.reminders, ['oneDay']);
    assert.equal(good.event.time, '11:00');
  } finally {
    await h.close();
  }
});

test('deleting an event keeps media keys until the bin entry is purged', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive']);
    const deleted = payload(await h.call(ctx, 'meos_events_delete', { id: 'event-trip', confirm: true })).data;
    assert.equal(deleted.media_keys_held, 1);
    assert.equal(h.deletedEventMedia.length, 0);

    await h.call(ctx, 'meos_purge_from_trash', { entry_id: deleted.recycle_bin_entry, confirm: true });
    assert.equal(h.deletedEventMedia.length, 1);
    assert.match(h.deletedEventMedia[0]!, /event-media/);
  } finally {
    await h.close();
  }
});

test('events can be filtered by tag and re-read after deletion', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive']);
    const travel = payload(await h.call(ctx, 'meos_events_list', { tag: 'travel' })).data;
    assert.deepEqual(travel.items.map((e: any) => e.id), ['event-trip']);

    await h.call(ctx, 'meos_events_delete', { id: 'event-trip', confirm: true });
    const missing = await h.call(ctx, 'meos_events_get', { id: 'event-trip' });
    assert.equal(errorCode(missing), 'not_found');
  } finally {
    await h.close();
  }
});
