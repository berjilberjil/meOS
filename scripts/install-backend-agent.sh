#!/bin/zsh
# Install (or reinstall) the meOS backend LaunchAgent so the SvelteKit backend
# starts on login and stays alive. Re-run any time the plist changes.
set -euo pipefail

LABEL="com.berjil.myos.backend"
SRC="$(cd "$(dirname "$0")" && pwd)/${LABEL}.plist"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"

mkdir -p "$HOME/Library/LaunchAgents"
cp "$SRC" "$DEST"

# Unload any previous version, then load and start the new one.
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DEST"
launchctl kickstart "gui/$(id -u)/${LABEL}"

echo "Installed ${LABEL}. Backend will be on http://localhost:5173"
echo "Logs: ~/Library/Logs/meos-backend.log"
