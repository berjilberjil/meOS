# Shared iPhone plumbing. Sourced by install-apps.sh (interactive) and
# refresh-ios.sh (the nightly LaunchAgent). Keep the device knowledge here so
# the two callers can never drift apart.
#
# Everything prints to stdout with a four-space indent; the nightly job just
# redirects stdout into its log file.

IOS_DEVICE_ID="2224632C-57C6-555C-8280-459061A2883F"   # iPhone 15
IOS_DEVICE_HOST="Berjil-Jacob.coredevice.local"
IOS_BUNDLE_ID="com.berjil.myos"

# "unavailable" contains "available", so matching the word is not enough — this
# check claimed the phone was there every time it was not, and the build then
# failed on a destination that could not be resolved.
ios_device_present() {
  local line
  line=$(xcrun devicectl list devices 2>/dev/null | grep "$IOS_DEVICE_ID" || true)
  [[ -n "$line" && "$line" != *unavailable* ]]
}

# The phone only has to be on the same LAN — the install goes over the local
# network, so a Wi-Fi with no internet is still fine for this.
ios_wait_for_device() {
  local mins="${1:-20}"
  (( mins == 0 )) && return 1
  print "    waiting up to ${mins}m for the phone to join this Wi-Fi..."
  local deadline=$(( $(date +%s) + mins * 60 ))
  while (( $(date +%s) < deadline )); do
    if ios_device_present; then print "    phone is here"; return 0; fi
    sleep 10
  done
  return 1
}

# Says which of the three things is wrong, instead of "unavailable".
ios_reachability() {
  local tunnel
  tunnel=$(xcrun devicectl list devices -v 2>/dev/null | grep -oE "TunnelState\.[a-z]+" | head -1 || true)
  case "$tunnel" in
    *connected)
      print "    wireless: connected — cable not required"
      return ;;
  esac
  if ping -c 1 -W 1500 "$IOS_DEVICE_HOST" >/dev/null 2>&1; then
    print "    phone is on this network but the tunnel is down — it should come back on wake"
  else
    print "    phone is NOT on this Wi-Fi (cellular, another network, or asleep)"
    print "    wireless debugging needs both on the same LAN; this Mac is on $(ipconfig getifaddr en0 2>/dev/null || print '?')"
  fi
}

# Retries until the phone shows up. The whole point: an install you start and
# walk away from.
ios_install_waiting() {
  local app="$1" mins="${2:-20}"
  local deadline=$(( $(date +%s) + mins * 60 ))
  local first=1
  while :; do
    if xcrun devicectl device install app --device "$IOS_DEVICE_ID" "$app" 2>/dev/null \
         | grep -E "App installed|bundleID"; then
      print "    installed"
      return 0
    fi
    if (( $(date +%s) >= deadline )); then
      print "    phone never came back within ${mins}m"
      return 1
    fi
    if (( first )); then
      print "    waiting for the phone (up to ${mins}m) — unlock it on this Wi-Fi and it installs itself"
      first=0
    fi
    sleep 10
  done
}

# --- provisioning profile -------------------------------------------------
# This is a free personal team: the profile lasts 7 days and the app simply
# stops launching when it lapses. Every decision the nightly job makes hangs
# off this one date, so read it from the signed app itself, not from a cache.

# Prints the expiry as epoch seconds, or nothing when there is no profile.
ios_profile_expiry_epoch() {
  local prov="$1/embedded.mobileprovision" plist=$(mktemp)
  security cms -D -i "$prov" >"$plist" 2>/dev/null || { rm -f "$plist"; return 1; }
  local exp
  exp=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$plist" 2>/dev/null || true)
  rm -f "$plist"
  [[ -z "$exp" ]] && return 1
  # PlistBuddy prints e.g. "Thu Sep 03 07:26:28 IST 2026" in the local zone.
  date -j -f "%a %b %d %T %Z %Y" "$exp" "+%s" 2>/dev/null
}

ios_profile_expiry_human() {
  local epoch
  epoch=$(ios_profile_expiry_epoch "$1") || return 1
  date -r "$epoch" "+%a %d %b %Y, %H:%M"
}

# Days left as a decimal, e.g. 6.4. Negative once it has lapsed.
ios_profile_days_left() {
  local epoch
  epoch=$(ios_profile_expiry_epoch "$1") || return 1
  printf "%.1f" $(( ( epoch - $(date +%s) ) / 86400.0 ))
}
