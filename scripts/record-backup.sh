#!/usr/bin/env bash
# Record a successful offsite backup or restore in D1 so the Security dashboard
# can show it. This writes one metadata row; it does not touch vault data.
#
#   ./scripts/record-backup.sh backup  age-d1
#   ./scripts/record-backup.sh restore local-sqlite-drill
#
# Requires wrangler login. Run only after the backup/restore actually succeeded.
set -euo pipefail
cd "$(dirname "$0")/.."

kind="${1:-backup}"
label="${2:-offsite}"
if [ "$kind" != "backup" ] && [ "$kind" != "restore" ]; then
  echo "Usage: $0 backup|restore [label]" >&2
  exit 1
fi
if ! [[ "$label" =~ ^[a-zA-Z0-9._-]{1,60}$ ]]; then
  echo "label must be 1-60 letters, digits, dot, dash or underscore" >&2
  exit 1
fi
if ! command -v wrangler >/dev/null 2>&1 && ! command -v bunx >/dev/null 2>&1; then
  echo "wrangler (or bunx) is required" >&2
  exit 1
fi

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$kind" = "backup" ]; then
  sql="insert into backup_status (user_id, last_backup_at, last_kind) select id, '$stamp', '$label' from users order by id limit 1 on conflict(user_id) do update set last_backup_at=excluded.last_backup_at, last_kind=excluded.last_kind"
else
  sql="insert into backup_status (user_id, last_restore_at, last_kind) select id, '$stamp', '$label' from users order by id limit 1 on conflict(user_id) do update set last_restore_at=excluded.last_restore_at, last_kind=excluded.last_kind"
fi

if command -v wrangler >/dev/null 2>&1; then
  wrangler d1 execute meos --remote --command "$sql"
else
  (cd apps/api && bunx wrangler d1 execute meos --remote --command "$sql")
fi
echo "Recorded $kind at $stamp ($label)."
