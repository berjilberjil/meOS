import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { hasFreshReauth } from '$lib/server/auth';
import { bumpStateVersion } from '$lib/server/stateVersion';
import {
  isAllowedStateKey,
  isDeletableStateKey,
  isRoutingDocument,
  isSealedEnvelope,
  MAX_STATE_VALUE_BYTES,
  PLAINTEXT_STATE_KEYS,
  validateCryptoMeta
} from '$lib/server/stateKeys';
import { utf8Bytes } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { audit } from '$lib/server/audit';

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

// Upsert one key of the logged-in user's app state.
export const PUT: RequestHandler = async ({ params, request, locals, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  if (!isAllowedStateKey(params.key)) throw error(400, 'Unknown state key');
  enforceRateLimit(`state-put:${locals.user.id}`, 180, 60_000);

  // Read and parse behind the same byte cap. `request.json()` would allocate an
  // oversized body before the check, and D1 rejects values above 2 MB anyway.
  const declared = Number(request.headers.get('content-length') ?? '');
  if (Number.isFinite(declared) && declared > MAX_STATE_VALUE_BYTES) {
    throw error(413, 'That is too large to sync');
  }
  const raw = await request.text().catch(() => {
    throw error(400, 'Body must be JSON');
  });
  if (utf8Bytes(raw) > MAX_STATE_VALUE_BYTES) throw error(413, 'That is too large to sync');
  let value: unknown;
  try {
    value = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    throw error(400, 'Body must be JSON');
  }

  const key = params.key;
  if (key === 'meos.crypto' || key === 'myos.crypto') {
    // Vault metadata is the one value whose replacement can lock the owner out
    // of every module. Require a recent password proof (or a session created in
    // the last 15 minutes for first-run setup). The client also verifies the
    // current passphrase before a re-wrap; this is defence in depth.
    const existingVault = await sql`
      select 1 as ok from app_state
      where user_id = ${locals.user.id} and key in ('meos.crypto', 'myos.crypto')
      limit 1`;
    const createdAt = locals.sessionCreatedAt ? Date.parse(locals.sessionCreatedAt) : NaN;
    const freshSession = Number.isFinite(createdAt) && Date.now() - createdAt < 15 * 60_000;
    const reauth = locals.sessionToken ? await hasFreshReauth(locals.sessionToken) : false;
    // First-run setup has no existing vault to protect; a stale login can still
    // create one. Once a vault exists, replacing it needs a fresh proof.
    if (existingVault.length && !freshSession && !reauth) {
      void audit({
        event: 'state_write',
        outcome: 'denied',
        userId: locals.user.id,
        ip: ipOf(getClientAddress),
        userAgent: request.headers.get('user-agent'),
        meta: { key, reason: 'reauth_required' }
      });
      return json(
        { reauthRequired: true, message: 'Confirm your login password before changing vault credentials.' },
        { status: 403 }
      );
    }
    const invalid = validateCryptoMeta(value);
    if (invalid) throw error(400, invalid);
  } else if (key === 'meos.ai.routes' || key === 'myos.ai.routes') {
    if (!isRoutingDocument(value)) throw error(400, 'Routing must be a JSON object');
  } else {
    // Anti-downgrade. Once an account has a vault, a non-plaintext module must
    // arrive as a sealed envelope. This closes the "replace ciphertext with
    // attacker-chosen JSON" path even if a session cookie is stolen; the client
    // also refuses such values on read, but the server should not store them.
    const vault = await sql`
      select 1 as ok from app_state
      where user_id = ${locals.user.id} and key in ('meos.crypto', 'myos.crypto')
      limit 1`;
    if (vault.length && !PLAINTEXT_STATE_KEYS.has(key) && !isSealedEnvelope(value)) {
      throw error(400, 'This account is encrypted; plaintext state is refused');
    }
  }

  await sql`
    insert into app_state (user_id, key, value, updated_at)
    values (${locals.user.id}, ${key}, ${sql.json(value)}, ${nowISO()})
    on conflict (user_id, key) do update set value = excluded.value, updated_at = ${nowISO()}`;
  await bumpStateVersion(locals.user.id);
  void audit({
    event: 'state_write',
    outcome: 'success',
    userId: locals.user.id,
    ip: ipOf(getClientAddress),
    userAgent: request.headers.get('user-agent'),
    meta: { key, bytes: utf8Bytes(raw) }
  });
  return json({ ok: true });
};

// Delete one key of the logged-in user's app state (used to purge removed modules).
export const DELETE: RequestHandler = async ({ params, locals, request, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  if (!params.key || params.key.length > 120 || !/^[a-z0-9._-]+$/i.test(params.key) || params.key.includes('..')) {
    throw error(400, 'Bad key');
  }
  enforceRateLimit(`state-delete:${locals.user.id}`, 60, 60_000);

  // The vault metadata is what makes the account encrypted. Deleting it would
  // make the next client read look like an unencrypted account (downgrade) and
  // can lead to a new vault being created over old ciphertext. There is no
  // legitimate module-purge reason to delete the current meta.
  if (params.key === 'meos.crypto') {
    void audit({
      event: 'state_delete',
      outcome: 'denied',
      userId: locals.user.id,
      ip: ipOf(getClientAddress),
      userAgent: request.headers.get('user-agent'),
      meta: { key: params.key, reason: 'vault_metadata' }
    });
    throw error(409, 'Vault metadata cannot be deleted through the state API');
  }
  if (params.key === 'myos.crypto') {
    const current = await sql`
      select 1 as ok from app_state
      where user_id = ${locals.user.id} and key = 'meos.crypto' limit 1`;
    if (!current.length) {
      throw error(409, 'Cannot delete legacy vault metadata before the current vault exists');
    }
  }

  // Current modules are not deletable through the API. A stolen session must
  // not be able to wipe notes/finance/health with one request. Legacy `myos.*`
  // cleanup and the explicit Fold disconnect are the only exceptions.
  if (!isDeletableStateKey(params.key)) {
    void audit({
      event: 'state_delete',
      outcome: 'denied',
      userId: locals.user.id,
      ip: ipOf(getClientAddress),
      userAgent: request.headers.get('user-agent'),
      meta: { key: params.key, reason: 'current_module' }
    });
    throw error(403, 'Whole current modules cannot be deleted through the state API');
  }

  await sql`delete from app_state where user_id = ${locals.user.id} and key = ${params.key}`;
  await bumpStateVersion(locals.user.id);
  void audit({
    event: 'state_delete',
    outcome: 'success',
    userId: locals.user.id,
    ip: ipOf(getClientAddress),
    userAgent: request.headers.get('user-agent'),
    meta: { key: params.key }
  });
  return json({ ok: true });
};
