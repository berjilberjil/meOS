#!/bin/zsh
# Install (or reinstall) the local meOS API LaunchAgent. This starts `bun run
# dev` on login for development only — production is Cloudflare Workers.
# Re-run any time the plist changes.
set -euo pipefail

command -v bun >/dev/null || { echo "Bun is required: https://bun.sh"; exit 1; }

LABEL="com.berjil.meos.backend"
OLD_LABEL="com.berjil.myos.backend"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$HERE/${LABEL}.plist"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/MeOS"
python3 - "$SRC" "$DEST" "$ROOT" "$HOME" <<'PY'
import pathlib, plistlib, sys
src, dest, root, home = sys.argv[1:]
data = plistlib.loads(pathlib.Path(src).read_bytes())
data["WorkingDirectory"] = str(pathlib.Path(root, "apps/api"))
env = data.setdefault("EnvironmentVariables", {})
env["PATH"] = f"{home}/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
log = str(pathlib.Path(home, "Library/Logs/MeOS/backend.log"))
data["StandardOutPath"] = log
data["StandardErrorPath"] = log
pathlib.Path(dest).write_bytes(plistlib.dumps(data))
PY

# Older installs used the MyOS label and a hardcoded path.
launchctl bootout "$DOMAIN/$OLD_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/${OLD_LABEL}.plist"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$DEST"
launchctl kickstart "$DOMAIN/$LABEL"

echo "Installed ${LABEL}. Backend will be on http://localhost:5173"
echo "Logs: ~/Library/Logs/MeOS/backend.log"
echo "First run? Apply the local schema:"
echo "  cd apps/api && bunx wrangler d1 execute meos --local --file=db/schema.sqlite.sql"
