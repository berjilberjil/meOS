import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { activeSecretsKeyId } from '$lib/server/secrets';
import { passwordKdf, listSessions, SESSION_DAYS, SESSION_IDLE_DAYS } from '$lib/server/auth';
import { mfaStatus } from '$lib/server/mfa';
import { listDevices } from '$lib/server/devices';
import { ensureAiTable } from '$lib/server/ai';
import { listSecurityEvents } from '$lib/server/audit';
import { countObjects, bytesUnder } from '$lib/server/storage';
import { enforceRateLimit } from '$lib/server/security';

/**
 * Security dashboard metadata for the signed-in owner. Counts and key ids only:
 * no note/finance text, no tokens, no IPs, no media contents.
 */
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not signed in');
  enforceRateLimit(`security-overview:${locals.user.id}`, 60, 60_000);

  await sql`
    create table if not exists backup_status (
      user_id        integer primary key references users(id) on delete cascade,
      last_backup_at text,
      last_restore_at text,
      last_kind      text
    )`;
  await ensureAiTable();

  const [sessions, devices, aiKeys, mfa, events, backup] = await Promise.all([
    listSessions(locals.user.id, locals.sessionToken),
    listDevices(locals.user.id),
    sql`select count(*) as n from ai_credentials where user_id = ${locals.user.id}`,
    mfaStatus(locals.user.id),
    listSecurityEvents(locals.user.id, 10),
    sql`select last_backup_at, last_restore_at, last_kind from backup_status where user_id = ${locals.user.id}`
  ]);

  let secretsKey: string | null = null;
  try {
    secretsKey = activeSecretsKeyId();
  } catch {
    // A broken/missing key ring is a real deployment problem, but this endpoint
    // must still render the rest of the dashboard and not leak the key itself.
    secretsKey = null;
  }

  const bodyPrefix = `body-photos/${locals.user.id}/`;
  const eventPrefix = `event-media/${locals.user.id}/`;
  const [bodyCount, bodyBytes, eventCount, eventBytes] = await Promise.all([
    countObjects(bodyPrefix),
    bytesUnder(bodyPrefix),
    countObjects(eventPrefix),
    bytesUnder(eventPrefix)
  ]);

  return json({
    passwordKdf: passwordKdf(),
    secretsKeyVersion: secretsKey,
    sessionDays: SESSION_DAYS,
    sessionIdleDays: SESSION_IDLE_DAYS,
    sessions,
    sessionsCount: sessions.length,
    devices,
    devicesCount: devices.length,
    aiKeys: Number(aiKeys[0]?.n ?? 0),
    mfa,
    media: { bodyPhotos: { count: bodyCount, bytes: bodyBytes }, eventMedia: { count: eventCount, bytes: eventBytes } },
    backup: {
      lastBackupAt: backup[0]?.last_backup_at ? String(backup[0].last_backup_at) : null,
      lastRestoreAt: backup[0]?.last_restore_at ? String(backup[0].last_restore_at) : null,
      lastKind: backup[0]?.last_kind ? String(backup[0].last_kind) : null,
      note: 'Offsite backups are recorded by scripts/record-backup.sh. D1 Time Travel is managed in Cloudflare.'
    },
    recentEvents: events
  });
};
