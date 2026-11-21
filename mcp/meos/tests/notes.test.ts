import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';
import { openValue, unlockDek, type SealedEnvelope } from '../../diet/src/crypto.ts';

async function readNotes(h: Awaited<ReturnType<typeof createHarness>>) {
  const cell = h.userState('a')['meos.notes'] as SealedEnvelope;
  const dek = await unlockDek(h.meta, 'vault-pass-A');
  return JSON.parse(openValue(cell, dek, 'meos.notes').toString('utf8')) as any[];
}

test('notes list puts pinned first and redacts locked bodies', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read']), 'meos_notes_list', {})).data;
    assert.deepEqual(data.items.map((n: any) => n.id), ['note-locked', 'note-normal']);
    assert.equal(data.items[0].redacted, true);
    assert.equal(data.items[0].body, null);
    assert.match(payload(await h.call(h.ctxFor('a', ['read']), 'meos_notes_list', {})).metadata.locked_notes, /redacted/);
  } finally {
    await h.close();
  }
});

test('note search covers title and body but not locked notes without secret', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const byBody = payload(await h.call(ctx, 'meos_notes_search', { query: 'eggs' })).data;
    assert.deepEqual(byBody.items.map((n: any) => n.id), ['note-normal']);
    const byTitle = payload(await h.call(ctx, 'meos_notes_search', { query: 'grocer' })).data;
    assert.deepEqual(byTitle.items.map((n: any) => n.id), ['note-normal']);

    const secret = h.ctxFor('a', ['read', 'secret']);
    const locked = payload(await h.call(secret, 'meos_notes_search', { query: 'LOCKED_BODY_TEXT' })).data;
    assert.deepEqual(locked.items.map((n: any) => n.id), ['note-locked']);
  } finally {
    await h.close();
  }
});

test('updating a note body preserves rich attachments and clears the stale paragraph', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const result = await h.call(ctx, 'meos_notes_update', {
      id: 'note-normal',
      title: 'Groceries',
      body: 'Milk, eggs and bread'
    });
    assert.equal(payload(result).data.body, 'Milk, eggs and bread');

    const stored = (await readNotes(h)).find((n) => n.id === 'note-normal');
    assert.equal(stored.body, 'Milk, eggs and bread');
    assert.deepEqual(
      stored.content.blocks.map((b: any) => b.type),
      ['paragraph', 'image']
    );
    assert.equal(stored.content.blocks[1].src, 'ATTACHMENT_BASE64');
    assert.deepEqual(
      stored.content.blocks[0].spans.map((s: any) => s.text),
      ['Milk, eggs and bread']
    );
  } finally {
    await h.close();
  }
});

test('creating a note mirrors plain text into blocks and can be pinned', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const created = payload(
      await h.call(ctx, 'meos_notes_create', { title: 'Plan', body: 'Line one\nLine two', pinned: true })
    ).data;
    assert.equal(created.pinned, true);

    const stored = (await readNotes(h)).find((n) => n.id === created.id);
    assert.equal(stored.content.blocks.length, 2);
    assert.equal(stored.content.blocks[1].spans[0].text, 'Line two');

    const unpinned = payload(await h.call(ctx, 'meos_notes_pin', { id: created.id, pinned: false })).data;
    assert.equal(unpinned.pinned, false);
  } finally {
    await h.close();
  }
});

test('locking a note requires the secret scope', async () => {
  const h = await createHarness();
  try {
    const denied = await h.call(h.ctxFor('a', ['read', 'write']), 'meos_notes_lock', { id: 'note-normal', locked: true });
    assert.equal(errorCode(denied), 'forbidden');

    const allowed = await h.call(
      h.ctxFor('a', ['read', 'write', 'secret']),
      'meos_notes_lock',
      { id: 'note-normal', locked: true }
    );
    assert.equal(payload(allowed).data.locked, true);
  } finally {
    await h.close();
  }
});

test('locked note delete keeps the payload in the bin and restores intact', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive', 'secret']);
    const deleted = payload(await h.call(ctx, 'meos_notes_delete', { id: 'note-locked', confirm: true })).data;
    const entryId = deleted.recycle_bin_entry;

    const trashReadOnly = await h.call(h.ctxFor('a', ['read']), 'meos_list_trash', {});
    const row = payload(trashReadOnly).data.items.find((e: any) => e.entry_id === entryId);
    assert.equal(row.title, '[locked]');

    const restored = payload(await h.call(ctx, 'meos_restore_from_trash', { entry_id: entryId })).data;
    assert.equal(restored.restored, true);
    const note = payload(await h.call(ctx, 'meos_notes_get', { id: 'note-locked' })).data;
    assert.equal(note.body, 'LOCKED_BODY_TEXT');
  } finally {
    await h.close();
  }
});

test('note creation with locked=true is refused without secret', async () => {
  const h = await createHarness();
  try {
    const result = await h.call(h.ctxFor('a', ['read', 'write']), 'meos_notes_create', {
      title: 'Hidden',
      body: 'x',
      locked: true
    });
    assert.equal(errorCode(result), 'forbidden');
  } finally {
    await h.close();
  }
});
