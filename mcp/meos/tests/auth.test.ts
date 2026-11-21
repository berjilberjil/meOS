import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';
import { authenticateBearer } from '../src/auth/authenticate.ts';
import { hashToken } from '../src/config/env.ts';
import { ServiceRegistry } from '../src/services/account.ts';
import { DynamicClientRegistry } from '../src/auth/dynamicClients.ts';
import { silentLogger } from '../src/services/logger.ts';
import { testConfig } from './support/harness.ts';
import type { ClientConfig } from '../src/config/types.ts';

test('bearer authentication accepts the configured token and rejects others', async () => {
  const client: ClientConfig = {
    id: 'claude',
    tokenHash: hashToken('correct-token'),
    scopes: ['read'],
    accountId: 'owner'
  };
  const config = testConfig({ clients: new Map([[client.id, client]]) });

  assert.equal((await authenticateBearer(config, 'Bearer correct-token')).id, 'claude');
  await assert.rejects(authenticateBearer(config, 'Bearer wrong-token'), /not authenticated|not valid/i);
  await assert.rejects(authenticateBearer(config, undefined), /not authenticated/i);
  await assert.rejects(authenticateBearer(config, 'Basic abc'), /Bearer/i);
});

test('a transient state-fetch failure is not remembered as an absent vault', async () => {
  const h = await createHarness();
  try {
    const services = h.ctxFor('a', ['read']).services;
    const original = services.api.getState.bind(services.api);
    let failOnce = true;
    services.api.getState = async (force?: boolean) => {
      if (failOnce) {
        failOnce = false;
        throw new Error('temporary network failure');
      }
      return original(force);
    };

    await assert.rejects(services.store.read('meos.notes'), /temporary network failure/);
    const notes = await services.store.read<any[]>('meos.notes');
    assert.ok(Array.isArray(notes));
    assert.equal(notes!.length, 2);
  } finally {
    await h.close();
  }
});

test('an expired bearer token is refused', async () => {
  const client: ClientConfig = {
    id: 'claude',
    tokenHash: hashToken('correct-token'),
    scopes: ['read'],
    accountId: 'owner',
    expiresAt: '2020-01-01T00:00:00.000Z'
  };
  const config = testConfig({ clients: new Map([[client.id, client]]) });
  await assert.rejects(authenticateBearer(config, 'Bearer correct-token'), /expired/i);
});

test('a read-only client cannot create a note', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const result = await h.call(ctx, 'meos_notes_create', { title: 'Nope', body: 'x' });
    assert.equal(result.isError, true);
    assert.equal(errorCode(result), 'forbidden');
  } finally {
    await h.close();
  }
});

test('destructive actions need the scope and explicit confirmation, and land in the recycle bin', async () => {
  const h = await createHarness();
  try {
    const readOnly = h.ctxFor('a', ['read', 'write']);
    const denied = await h.call(readOnly, 'meos_notes_delete', { id: 'note-normal', confirm: true });
    assert.equal(errorCode(denied), 'forbidden');

    const destructive = h.ctxFor('a', ['read', 'write', 'destructive']);
    const unconfirmed = await h.call(destructive, 'meos_notes_delete', { id: 'note-normal' });
    assert.equal(errorCode(unconfirmed), 'confirmation_required');

    const deleted = await h.call(destructive, 'meos_notes_delete', { id: 'note-normal', confirm: true });
    assert.equal(payload(deleted).success, true);
    const entryId = payload(deleted).data.recycle_bin_entry;
    assert.ok(entryId);

    const listed = await h.call(destructive, 'meos_notes_list', {});
    assert.equal(payload(listed).data.items.some((n: any) => n.id === 'note-normal'), false);

    const trash = await h.call(destructive, 'meos_list_trash', {});
    assert.equal(payload(trash).data.items.some((e: any) => e.entry_id === entryId), true);

    const restored = await h.call(destructive, 'meos_restore_from_trash', { entry_id: entryId });
    assert.equal(payload(restored).data.restored, true);

    const after = await h.call(destructive, 'meos_notes_get', { id: 'note-normal' });
    assert.equal(payload(after).data.title, 'Groceries');
  } finally {
    await h.close();
  }
});

test('rate limiting is enforced per client', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read'], { rateLimit: 1 });
    const first = await h.call(ctx, 'meos_get_profile', {});
    assert.equal(payload(first).success, true);
    const second = await h.call(ctx, 'meos_get_profile', {});
    assert.equal(errorCode(second), 'rate_limited');
  } finally {
    await h.close();
  }
});

test('one client cannot read another account\'s records', async () => {
  const h = await createHarness();
  try {
    const a = h.ctxFor('a', ['read']);
    const b = h.ctxFor('b', ['read']);
    const aNotes = await h.call(a, 'meos_notes_list', {});
    const bNotes = await h.call(b, 'meos_notes_list', {});
    assert.deepEqual(payload(aNotes).data.items.map((n: any) => n.id), ['note-locked', 'note-normal']);
    assert.deepEqual(payload(bNotes).data.items.map((n: any) => n.id), ['note-b']);

    const cross = await h.call(a, 'meos_notes_get', { id: 'note-b' });
    assert.equal(errorCode(cross), 'not_found');

    const bProfile = await h.call(b, 'meos_get_profile', {});
    assert.equal(payload(bProfile).data.name, 'Other Person');
  } finally {
    await h.close();
  }
});

test('locked note content needs the secret scope', async () => {
  const h = await createHarness();
  try {
    const redacted = await h.call(h.ctxFor('a', ['read']), 'meos_notes_get', { id: 'note-locked' });
    assert.equal(payload(redacted).data.redacted, true);
    assert.equal(payload(redacted).data.body, null);
    assert.equal(payload(redacted).data.title, '[locked]');

    const full = await h.call(h.ctxFor('a', ['read', 'secret']), 'meos_notes_get', { id: 'note-locked' });
    assert.equal(payload(full).data.body, 'LOCKED_BODY_TEXT');
    assert.equal(payload(full).data.title, 'Private');

    const searched = await h.call(h.ctxFor('a', ['read']), 'meos_notes_search', { query: 'LOCKED_BODY_TEXT' });
    assert.equal(payload(searched).data.items.length, 0);
  } finally {
    await h.close();
  }
});

test('health data needs the health scope', async () => {
  const h = await createHarness();
  try {
    const denied = await h.call(h.ctxFor('a', ['read']), 'meos_health_get_summary', {});
    assert.equal(errorCode(denied), 'forbidden');

    const allowed = await h.call(h.ctxFor('a', ['read', 'health']), 'meos_health_get_summary', {});
    assert.equal(payload(allowed).success, true);
  } finally {
    await h.close();
  }
});

test('profile contact details and private brief are redacted without the secret scope', async () => {
  const h = await createHarness();
  try {
    const basic = await h.call(h.ctxFor('a', ['read']), 'meos_get_profile', {});
    const data = payload(basic).data;
    assert.equal(data.name, 'Berjil');
    assert.equal(data.identity, undefined);
    assert.equal(data.about, undefined);
    assert.equal(JSON.stringify(data).includes('SECRET_PROFILE_PHOTO_BASE64'), false);

    const full = await h.call(h.ctxFor('a', ['read', 'secret']), 'meos_get_profile', {});
    assert.equal(payload(full).data.identity.email, 'berjil@example.com');
    assert.equal(payload(full).data.about, 'PRIVATE_ABOUT_TEXT');
    assert.equal(JSON.stringify(payload(full)).includes('SECRET_PROFILE_PHOTO_BASE64'), false);
  } finally {
    await h.close();
  }
});


test('app-created tokens authenticate through the encrypted meos.mcp registry', async () => {
  const h = await createHarness();
  try {
    const account = {
      id: 'a',
      baseUrl: h.baseUrl,
      username: h.accounts.a.username,
      password: h.accounts.a.password,
      vaultPassphrase: h.accounts.a.passphrase,
      requestTimeoutMs: 5000
    };
    const config = testConfig({ accounts: new Map([['a', account]]), clients: new Map() });
    const registry = new ServiceRegistry(config.accounts, silentLogger);
    const dynamic = new DynamicClientRegistry(config, registry, silentLogger, { ttlMs: 0 });

    const active = await authenticateBearer(config, 'Bearer app-secret', dynamic);
    assert.equal(active.id, 'app:app-claude');
    assert.deepEqual(active.scopes, ['read', 'health']);
    assert.equal(active.accountId, 'a');

    await assert.rejects(authenticateBearer(config, 'Bearer revoked-secret', dynamic), /not valid/i);
    await assert.rejects(authenticateBearer(config, 'Bearer expired-secret', dynamic), /not valid/i);
    // An empty scope list must never fall through to legacy read-all.
    await assert.rejects(authenticateBearer(config, 'Bearer empty-secret', dynamic), /not valid/i);

    // App tokens use the same granular vocabulary as OAuth: notes-only must
    // not unlock finance.
    const notes = await authenticateBearer(config, 'Bearer notes-secret', dynamic);
    assert.deepEqual(notes.scopes, ['meos.notes.read']);
    const notesCtx = { ...h.ctxFor('a'), client: notes };
    const ownModule = payload(await h.call(notesCtx, 'meos_notes_list'));
    assert.ok(Array.isArray(ownModule.data.items));
    const otherModule = await h.call(notesCtx, 'meos_finance_ledger_get_summary');
    assert.equal(errorCode(otherModule), 'forbidden');
  } finally {
    await h.close();
  }
});
