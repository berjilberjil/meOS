#!/bin/zsh
# Nightly re-sign + reinstall of MyOS on the iPhone, so the free-team 7-day
# profile never gets a chance to lapse.
#
#   ./scripts/refresh-ios.sh            what the LaunchAgent runs at 22:00
#   ./scripts/refresh-ios.sh --force    refresh even if the profile is fresh
#   ./scripts/refresh-ios.sh --status   print the expiry and exit
#
# WHY THIS IS NOT JUST "reinstall every night":
# reinstalling the SAME build changes nothing — the 7-day clock lives in the
# provisioning profile embedded in the app, not in the install. Xcode happily
# reuses a cached profile, so a plain rebuild can hand you the same expiry it
# had yesterday. So this script does three things in order:
#   1. deletes the cached MyOS profile, so automatic signing has to mint a new
#      one with a new 7-day window (work/skcript profiles are never touched),
#   2. deletes the built .app, so the link+codesign step actually re-runs and
#      the new profile gets embedded,
#   3. proves it worked by reading the expiry back out of the signed bundle.
# Step 3 is the real test. A run that builds and installs but comes back with
# yesterday's date is a FAILURE and says so.
#
# Runs unattended out of launchd, so it assumes nothing about $PATH, keeps the
# Mac awake while it works, and never blocks on a prompt.

set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ROOT="${0:A:h:h}"
source "$ROOT/scripts/lib/ios-device.sh"

# Refresh whenever the profile has this many days or fewer left. 6.0 with a
# 7-day profile means "every night", while still skipping a second run on a
# night we already refreshed. Lower it if you want fewer trips to Apple.
REFRESH_BELOW="${MYOS_REFRESH_BELOW:-6.0}"
# The phone is usually in the room at 22:00, but not always. Wait, don't fail.
WAIT_MINS="${MYOS_WAIT_MINS:-120}"

LOG_DIR="$HOME/Library/Logs/MyOS"
LOG="$LOG_DIR/ios-refresh.log"
BUILD_LOG="$LOG_DIR/ios-refresh-build.log"
# The build deletes the signed .app before rebuilding, so a failed run leaves
# nothing on disk to read the deadline off. Remember it here instead: this file
# is what --status falls back to, and what proves the clock moved on the next
# successful run.
STATE="$LOG_DIR/last-signed.epoch"
LOCK="/tmp/myos-ios-refresh.lock"
APP="$ROOT/apps/ios/build/Build/Products/Release-iphoneos/MyOS.app"

FORCE=0; STATUS_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --force)  FORCE=1 ;;
    --status) STATUS_ONLY=1 ;;
    *) print "usage: refresh-ios.sh [--force|--status]"; exit 2 ;;
  esac
done

mkdir -p "$LOG_DIR"
log()  { print "$(date '+%Y-%m-%d %H:%M:%S')  $*" }
note() { osascript -e "display notification \"$1\" with title \"MyOS\"" >/dev/null 2>&1 || true }
fail() {
  log "FAILED: $1"
  # Loud on purpose: a silent failure here means a dead app in seven days.
  osascript -e "display notification \"$1\" with title \"MyOS refresh FAILED\" sound name \"Basso\"" >/dev/null 2>&1 || true
  exit 1
}

# --status short-circuits everything, including the log and the lock.
if (( STATUS_ONLY )); then
  if left=$(ios_profile_days_left "$APP"); then
    print "MyOS iOS build signed until $(ios_profile_expiry_human "$APP")  (${left} days left)"
  elif [[ -s "$STATE" ]]; then
    e=$(<"$STATE")
    print "last signed build expires $(date -r $e '+%a %d %b %Y, %H:%M')  ($(printf '%.1f' $(( (e - $(date +%s)) / 86400.0 ))) days left)"
    print "no .app on disk — the last rebuild did not finish. Run: ./scripts/refresh-ios.sh --force"
  else
    print "no built app at $APP — nothing signed yet"
  fi
  exit 0
fi

# One run at a time. A 22:00 job that overlaps a manual run corrupts the build
# directory both are writing to.
if ! mkdir "$LOCK" 2>/dev/null; then
  print "$(date '+%Y-%m-%d %H:%M:%S')  another refresh is already running — skipping" >>"$LOG"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

# Everything from here is logged. Keep the log from growing forever.
if [[ -f "$LOG" && $(stat -f%z "$LOG") -gt 1048576 ]]; then
  tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
exec >>"$LOG" 2>&1

log "=== nightly iOS refresh ==="

# A build plus a wait for the phone can outlast the idle-sleep timer, and a
# sleeping Mac silently abandons the job half-done.
caffeinate -i -m -w $$ &

# ---------------------------------------------------------------- decide ---
OLD_EPOCH=""
if OLD_EPOCH=$(ios_profile_expiry_epoch "$APP" 2>/dev/null); then
  left=$(ios_profile_days_left "$APP")
  log "current build signed until $(ios_profile_expiry_human "$APP")  (${left} days left)"
  if (( FORCE == 0 )) && (( left > REFRESH_BELOW )); then
    log "still fresh (> ${REFRESH_BELOW} days) — nothing to do"
    exit 0
  fi
elif [[ -s "$STATE" ]]; then
  # A previous run deleted the .app and then failed. The deadline is still real
  # even though the bundle is gone — keep it, so the "did the clock move" check
  # below cannot be fooled into passing on a stale profile.
  OLD_EPOCH=$(<"$STATE")
  log "no .app on disk (previous run failed) — last signature expires $(date -r $OLD_EPOCH '+%a %d %b %Y, %H:%M')"
else
  log "no signed build on disk yet — building from scratch"
  OLD_EPOCH=0
fi

# ------------------------------------------------- force a brand-new profile ---
# Only ours. The skcript work profiles in the same directory are load-bearing
# for the day job and must survive this untouched.
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
pruned=0
if [[ -d "$PROFILE_DIR" ]]; then
  for f in "$PROFILE_DIR"/*.mobileprovision(N); do
    plist=$(mktemp)
    security cms -D -i "$f" >"$plist" 2>/dev/null || { rm -f "$plist"; continue }
    appid=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$plist" 2>/dev/null || true)
    rm -f "$plist"
    if [[ "$appid" == *".$IOS_BUNDLE_ID" || "$appid" == *".$IOS_BUNDLE_ID."* ]]; then
      rm -f "$f"; pruned=$(( pruned + 1 ))
    fi
  done
fi
log "pruned $pruned cached MyOS profile(s) — automatic signing will mint a new one"

# --------------------------------------------------------------- build ---
cd "$ROOT/apps/ios" || fail "cannot enter apps/ios"

ios_reachability
dest="id=$IOS_DEVICE_ID"
if ! ios_device_present; then
  # Build AT the device whenever it is reachable: targeting the real device is
  # what lets automatic signing register it and settle the trust handshake.
  # generic/platform=iOS skips that and the app lands as "Not Verified".
  deadline_txt="soon"
  (( OLD_EPOCH > 0 )) && deadline_txt="$(date -r $OLD_EPOCH '+%d %b')"
  ios_wait_for_device "$WAIT_MINS" || fail "phone never joined the Wi-Fi — no refresh tonight, app expires $deadline_txt"
fi

xcodegen generate >/dev/null || fail "xcodegen failed"

# Force the codesign step to actually run. Without this an unchanged tree
# produces a cache hit and the old profile stays embedded — the exact silent
# failure this whole script exists to prevent.
rm -rf build/Build/Products/Release-iphoneos

log "building..."
if ! xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Release \
                -destination "$dest" -derivedDataPath build \
                -allowProvisioningUpdates build >"$BUILD_LOG" 2>&1; then
  log "build log tail:"
  tail -n 30 "$BUILD_LOG"
  if grep -qiE "no profiles|no signing certificate|requires a development team|Your session has expired|not authorized" "$BUILD_LOG"; then
    # The free 7-day profile is minted by Apple on demand, so this needs a
    # live Apple ID session — the signing certificate sitting in the keychain
    # is not enough. Team ACDQ327MPR ("Berjil Jacob", the free personal team)
    # hangs off the berjil@skcript.com Apple ID, not the gmail one.
    fail "no Apple ID in Xcode — open Xcode > Settings > Accounts, sign in as berjil@skcript.com (team ACDQ327MPR), then run ./scripts/refresh-ios.sh --force"
  fi
  fail "build failed — see $BUILD_LOG"
fi

# ------------------------------------------------------- prove it worked ---
NEW_EPOCH=$(ios_profile_expiry_epoch "$APP") || fail "built app has no embedded profile"
NEW_LEFT=$(ios_profile_days_left "$APP")
log "new build signed until $(ios_profile_expiry_human "$APP")  (${NEW_LEFT} days left)"

if (( NEW_EPOCH <= OLD_EPOCH )); then
  fail "Apple handed back the SAME profile (still expires $(ios_profile_expiry_human "$APP")) — the clock did not reset"
fi
print "$NEW_EPOCH" > "$STATE"

# -------------------------------------------------------------- install ---
if ! ios_install_waiting "$APP" "$WAIT_MINS"; then
  fail "built a fresh profile but could not install — run: ./scripts/install-apps.sh ios"
fi

log "done — good for ${NEW_LEFT} more days"
note "Reinstalled. Good until $(ios_profile_expiry_human "$APP")."
