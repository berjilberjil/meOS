import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';
import { sanitizeFields } from '../src/services/logger.ts';

test('app status reports reachability and vault state without secrets', async () => {
  const h = await createHarness();
  try {
    const result = await h.call(h.ctxFor('a', ['read']), 'meos_get_app_status', {});
    const data = payload(result).data;
    assert.equal(data.backend.reachable, true);
    assert.equal(data.user.username, 'owner-a');
    assert.equal(data.vault, 'unlocked');
    assert.equal(data.modules_present.includes('notes'), true);
    const serialized = JSON.stringify(data);
    for (const secret of ['pass-a', 'vault-pass-A', 'meos_session', 'wrappedByPass', 'token']) {
      assert.equal(serialized.includes(secret), false);
    }
  } finally {
    await h.close();
  }
});

test('module status counts readable modules and reports presence', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read']), 'meos_get_module_status', {})).data.modules;
    assert.equal(data.notes.present, true);
    assert.equal(data.notes.sealed, true);
    assert.equal(data.notes.count, 2);
    assert.equal(data.events.count, 2);
    assert.equal(data.fold.count, 15);
  } finally {
    await h.close();
  }
});

test('storage usage is aggregate only and requires health scope', async () => {
  const h = await createHarness();
  try {
    const denied = await h.call(h.ctxFor('a', ['read']), 'meos_get_storage_usage', {});
    assert.equal(errorCode(denied), 'forbidden');

    const result = await h.call(h.ctxFor('a', ['read', 'health']), 'meos_get_storage_usage', {});
    const data = payload(result).data;
    assert.equal(data.media.body_photos.count, 2);
    assert.equal(data.media.body_photos.total_bytes, 3000);
    assert.equal(JSON.stringify(data).includes('signed.example'), false);
  } finally {
    await h.close();
  }
});

test('AI models are masked and routing removes secret-looking fields', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const models = payload(await h.call(ctx, 'meos_ai_get_available_models', {})).data;
    assert.equal(models.providers[0].masked_key, 'AIza••••1234');
    assert.deepEqual(models.models, ['gemini-2.5-flash', 'gemini-2.5-pro']);
    assert.equal(JSON.stringify(models).includes('AIza'), true);
    assert.equal(JSON.stringify(models).match(/AIza[A-Za-z0-9_-]{30,}/), null);

    const routes = payload(await h.call(ctx, 'meos_ai_get_routes', {})).data.routes;
    assert.equal(routes.default.model, 'gemini-2.5-flash');
    assert.equal('secret' in routes.default, false);
  } finally {
    await h.close();
  }
});

test('memory search ranks relevant facts and create refuses secrets and duplicates', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const searched = payload(await h.call(ctx, 'meos_memory_search', { query: 'PostgreSQL' })).data;
    assert.equal(searched.memories[0].id, 'mem1');

    const created = payload(
      await h.call(ctx, 'meos_memory_create', {
        content: 'Prefers dark mode in every editor',
        category: 'preference',
        importance: 2
      })
    ).data;
    assert.equal(created.source, 'manual');
    assert.equal(created.confidence, 1);

    const duplicate = await h.call(ctx, 'meos_memory_create', { content: 'Prefers dark mode in every editor' });
    assert.equal(errorCode(duplicate), 'conflict');

    const secret = await h.call(ctx, 'meos_memory_create', { content: 'My password is hunter2 for the bank' });
    assert.equal(errorCode(secret), 'invalid_input');
  } finally {
    await h.close();
  }
});

test('memory update changes only supplied fields', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const updated = payload(
      await h.call(ctx, 'meos_memory_update', { id: 'mem2', importance: 2, pinned: true })
    ).data;
    assert.equal(updated.importance, 2);
    assert.equal(updated.pinned, true);
    assert.equal(updated.content, 'Building MeOS as a personal operating system');
    assert.equal(updated.category, 'project');
  } finally {
    await h.close();
  }
});

test('trash list redacts locked note titles and purge releases media', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive', 'secret']);
    const deleted = payload(await h.call(ctx, 'meos_events_delete', { id: 'event-trip', confirm: true })).data;
    const bin = payload(await h.call(ctx, 'meos_list_trash', {})).data;
    const row = bin.items.find((e: any) => e.entry_id === deleted.recycle_bin_entry);
    assert.equal(row.kind, 'event');
    assert.equal(row.payload, undefined);

    const purged = payload(await h.call(ctx, 'meos_purge_from_trash', { entry_id: deleted.recycle_bin_entry, confirm: true })).data;
    assert.equal(purged.purged, true);
    assert.equal(h.deletedEventMedia.length, 1);
    assert.equal(h.deletedBodyPhotos.length, 0);
  } finally {
    await h.close();
  }
});

test('devices and safe settings are readable', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const devices = payload(await h.call(ctx, 'meos_list_devices', {})).data;
    assert.equal(devices.items[0].name, 'Berjil Mac');
    const one = payload(await h.call(ctx, 'meos_get_device', { id: 'dev1' })).data;
    assert.equal(one.kind, 'mac');

    const settings = payload(await h.call(ctx, 'meos_get_settings', {})).data;
    assert.equal(settings.fitness.goal, 'cut');
    assert.deepEqual(settings.habits, ['Gym', 'Read']);
  } finally {
    await h.close();
  }
});

test('capability inventory is explicit about absent finance features', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read']), 'meos_get_capabilities', {})).data;
    assert.equal(data.modules.finance.unavailable.includes('transaction_ledger'), true);
    assert.equal(data.modules.notes.unavailable.includes('tags'), true);
    assert.equal(data.modules.events.unavailable.includes('standalone_reminder_records'), true);
    assert.equal(data.modules.removed.includes('journal'), true);
  } finally {
    await h.close();
  }
});

test('log sanitiser drops secrets and personal payload keys', () => {
  const fields = sanitizeFields({
    tool: 'meos_notes_get',
    client: 'claude',
    token: 'secret',
    authorization: 'Bearer x',
    body: 'private',
    content: 'private',
    health: 'private',
    password: 'x',
    args: { note: 'private' },
    count: 3
  });
  assert.deepEqual(fields, { tool: 'meos_notes_get', client: 'claude', count: 3 });
});
