import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  clearFailedLogins,
  loginAllowed,
  recordFailedLogin,
  verifyPassword
} from '$lib/server/auth';
import { ensureAiTable } from '$lib/server/ai';
import { listDevices } from '$lib/server/devices';
import { isMfaEnabled, verifySecondFactor } from '$lib/server/mfa';
import { bytesUnder, countObjects } from '$lib/server/storage';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { audit } from '$lib/server/audit';

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

/**
 * Encrypted export of everything MeOS holds for this owner.
 *
 * `state` is exactly what D1 stores: ciphertext envelopes plus the public vault
 * metadata. The server cannot decrypt it, so this is a real backup of the
 * zero-knowledge model rather than a plaintext dump. Media bytes are not
 * embedded; counts and sizes are listed so the owner knows what to copy from
 * R2 separately.
 *
 * Requires the login password (and MFA) — not just a live session — because a
 * stolen cookie must not be able to walk away with the whole vault.
 */
export const POST: RequestHandler = async ({ request, locals, getClientAddress }) => {
  const user = locals.user;
  if (!user) throw error(401, 'Not signed in');

  enforceRateLimit(`export:${user.id}`, 3, 60 * 60 * 1000);

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const password = String(body.password ?? '');
  const code = String(body.code ?? '').trim().slice(0, 64);
  const ip = ipOf(getClientAddress);
  const userAgent = request.headers.get('user-agent');

  if (!(await loginAllowed(user.username, ip))) {
    throw error(429, 'Too many attempts. Wait a few minutes and try again.');
  }
  const rows = await sql`select password_hash from users where id = ${user.id}`;
  if (!rows[0] || !(await verifyPassword(password, String(rows[0].password_hash)))) {
    await recordFailedLogin(user.username, ip);
    void audit({ event: 'export', outcome: 'failure', userId: user.id, ip, userAgent });
    throw error(403, 'That password is not correct.');
  }
  if (await isMfaEnabled(user.id)) {
    if (!code) {
      return new Response(JSON.stringify({ mfaRequired: true, message: 'Enter your authenticator code.' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    if (!(await verifySecondFactor(user.id, code))) {
      await recordFailedLogin(user.username, ip);
      void audit({ event: 'export', outcome: 'denied', userId: user.id, ip, userAgent, meta: { reason: 'mfa' } });
      throw error(403, 'That authenticator code is not valid.');
    }
  }
  await clearFailedLogins(user.username, ip);

  const stateRows = await sql`select key, value as raw from app_state where user_id = ${user.id}`;
  const state: Record<string, unknown> = {};
  for (const row of stateRows) {
    const raw = row.raw;
    try {
      state[String(row.key)] = typeof raw === 'string' ? JSON.parse(raw) : raw;
    } catch {
      state[String(row.key)] = raw;
    }
  }

  const devices = await listDevices(user.id);
  await ensureAiTable();
  const aiKeys = await sql`
    select id, provider, label, masked, enabled, models
    from ai_credentials where user_id = ${user.id} order by created_at asc`;

  const bodyPhotoPrefix = `body-photos/${user.id}/`;
  const eventMediaPrefix = `event-media/${user.id}/`;
  const media = {
    bodyPhotos: { count: await countObjects(bodyPhotoPrefix), bytes: await bytesUnder(bodyPhotoPrefix) },
    eventMedia: { count: await countObjects(eventMediaPrefix), bytes: await bytesUnder(eventMediaPrefix) },
    note: 'Media bytes are ciphertext in private R2 and are not embedded in this JSON.'
  };

  void audit({
    event: 'export',
    outcome: 'success',
    userId: user.id,
    ip,
    userAgent,
    meta: { state_keys: stateRows.length, devices: devices.length, ai_keys: aiKeys.length }
  });

  const payload = {
    format: 'meos-encrypted-export',
    version: 1,
    exportedAt: new Date().toISOString(),
    user: { id: user.id, username: user.username },
    encryption: {
      state: 'AES-256-GCM envelopes sealed on the client; this export is ciphertext',
      media: 'ciphertext objects in private R2; copy them separately',
      warning: 'meos.crypto contains the wrapped DEK and salts. Without the vault passphrase or recovery code this export is unreadable.'
    },
    state,
    devices,
    aiKeys,
    media
  };

  return new Response(JSON.stringify(payload, null, 2), {
    status: 200,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': 'attachment; filename="meos-encrypted-export.json"',
      'Cache-Control': 'no-store'
    }
  });
};
