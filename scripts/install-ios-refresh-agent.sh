#!/bin/zsh
# Install (or reinstall) the nightly iOS refresh LaunchAgent: 22:00 daily,
# re-signs MyOS with a new 7-day profile and reinstalls it on the iPhone.
# Re-run any time the plist changes.
#
#   ./scripts/install-ios-refresh-agent.sh            install / reinstall
#   ./scripts/install-ios-refresh-agent.sh --remove   uninstall
set -euo pipefail

LABEL="com.berjil.myos.iosrefresh"
SRC="$(cd "$(dirname "$0")" && pwd)/${LABEL}.plist"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--remove" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$DEST"
  echo "Removed $LABEL. The app will expire 7 days after the last refresh."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/MyOS"
cp "$SRC" "$DEST"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$DEST"

echo "Installed $LABEL — runs daily at 22:00."
launchctl print "$DOMAIN/$LABEL" | grep -E "state|runs|last exit" || true
cat <<'TXT'

  Check status any time:   ./scripts/refresh-ios.sh --status
  Run it right now:        launchctl kickstart -k gui/$(id -u)/com.berjil.myos.iosrefresh
  Watch it work:           tail -f ~/Library/Logs/MyOS/ios-refresh.log

  The phone needs to be on the same Wi-Fi as this Mac. If it is not, the job
  waits up to two hours for it before giving up and telling you.
TXT
