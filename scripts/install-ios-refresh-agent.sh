#!/bin/zsh
# Install (or reinstall) the nightly iOS refresh LaunchAgent: 22:00 daily,
# re-signs MyOS with a new 7-day profile and reinstalls it on the iPhone.
# Re-run any time the plist changes.
#
#   ./scripts/install-ios-refresh-agent.sh            install / reinstall
#   ./scripts/install-ios-refresh-agent.sh --remove   uninstall
set -euo pipefail

LABEL="com.berjil.myos.iosrefresh"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/${LABEL}.plist"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"
# launchd's /bin/zsh cannot open ~/Documents (TCC "can't open input file",
# exit 127). Keep the runnable copy where LaunchAgents are allowed to read.
SUPPORT="$HOME/Library/Application Support/MyOS"

if [[ "${1:-}" == "--remove" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$DEST"
  echo "Removed $LABEL. The app will expire 7 days after the last refresh."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/MyOS" "$SUPPORT/lib"
cp "$HERE/refresh-ios.sh" "$SUPPORT/refresh-ios.sh"
cp "$HERE/lib/ios-device.sh" "$SUPPORT/lib/ios-device.sh"
chmod 755 "$SUPPORT/refresh-ios.sh"

# Rewrite the template so ProgramArguments and MYOS_ROOT match this Mac.
# The checked-in plist still documents the job; the installed one is what
# launchd actually runs.
python3 - "$SRC" "$DEST" "$SUPPORT/refresh-ios.sh" "$HERE/.." <<'PY'
import pathlib, plistlib, sys
src, dest, script, root = sys.argv[1:]
data = plistlib.loads(pathlib.Path(src).read_bytes())
data["ProgramArguments"] = ["/bin/zsh", script]
data["WorkingDirectory"] = str(pathlib.Path(root).resolve())
env = data.setdefault("EnvironmentVariables", {})
env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
env["MYOS_ROOT"] = str(pathlib.Path(root).resolve())
pathlib.Path(dest).write_bytes(plistlib.dumps(data))
PY

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
