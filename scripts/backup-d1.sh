#!/usr/bin/env bash
# Encrypted D1 export. Read-only against production; writes a local backup.
#
# Usage:
#   AGE_RECIPIENT=age1... ./scripts/backup-d1.sh [output-dir]
#
# Requires: wrangler (logged in), age, and sufficient local disk. The plaintext
# SQL is deleted immediately after encryption. D1 Time Travel is the first-line
# recovery (30 days), but it is not an offsite backup — keep these encrypted
# exports somewhere else.
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-./backups}"
mkdir -p "$out"
chmod 700 "$out"

if ! command -v wrangler >/dev/null 2>&1 && ! command -v bunx >/dev/null 2>&1; then
  echo "wrangler (or bunx) is required" >&2
  exit 1
fi
if ! command -v age >/dev/null 2>&1; then
  echo "age is required: brew install age" >&2
  exit 1
fi
if [ -z "${AGE_RECIPIENT:-}" ]; then
  echo "Set AGE_RECIPIENT to the age public key that should decrypt this backup." >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
plain="$out/meos-d1-$stamp.sql"
enc="$out/meos-d1-$stamp.sql.age"

echo "Exporting D1 (remote)…"
if command -v wrangler >/dev/null 2>&1; then
  wrangler d1 export meos --remote --output "$plain"
else
  (cd apps/api && bunx wrangler d1 export meos --remote --output "$OLDPWD/$plain")
fi
chmod 600 "$plain"

echo "Encrypting…"
age -r "$AGE_RECIPIENT" -o "$enc" "$plain"
shred -u "$plain" 2>/dev/null || rm -f "$plain"
chmod 600 "$enc"

echo "Backup written: $enc"
echo "Verify with: age -d -i <identity> $enc | head"
echo "Reminder: app_state is ciphertext, but metadata, devices and password hashes are still sensitive."
