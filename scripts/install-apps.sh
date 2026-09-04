#!/bin/zsh
# Build + install MyOS. No arguments installs both.
#
#   ./scripts/install-apps.sh              mac + iphone
#   ./scripts/install-apps.sh mac
#   ./scripts/install-apps.sh ios
#   ./scripts/install-apps.sh ios 0        build, install if the phone is there, don't wait
#   ./scripts/install-apps.sh ios 60       wait up to an hour for the phone
#
# This is the hands-on installer. The nightly one that keeps the free-team
# 7-day signature from lapsing is scripts/refresh-ios.sh; both share the device
# plumbing in scripts/lib/ios-device.sh so they cannot drift apart.
#
# The iPhone install works over Wi-Fi once the device is set to "Connect via
# network" (Xcode > Window > Devices and Simulators > select iPhone > tick the
# box). That is a one-time Xcode step — devicectl has no CLI equivalent, it
# only exposes pair/unpair. After that, leave the cable in the drawer.
#
# The cable is NOT needed per install. What the wireless path does need is both
# machines on the same LAN: the phone on cellular, or on a different Wi-Fi, or
# asleep long enough for the tunnel to drop, all look identical from here —
# `devicectl` just says "unavailable". So the build never depends on the device
# being present, and the install waits for it instead of failing. Leave the
# script running, pick the phone up whenever, and it lands on its own.
set -euo pipefail

ROOT="${0:A:h:h}"
source "$ROOT/scripts/lib/ios-device.sh"
TARGET="${1:-both}"
WAIT_MINS="${2:-20}"

banner() { print -P "\n%F{cyan}==> $1%f"; }

install_mac() {
  banner "Mac: build"
  cd "$ROOT/apps/mac"
  xcodegen generate >/dev/null
  xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Release \
             -derivedDataPath build build >/dev/null

  banner "Mac: install"
  osascript -e 'quit app "MyOS"' 2>/dev/null || true
  for _ in {1..25}; do pgrep -f "/Applications/MyOS.app/Contents/MacOS/MyOS" >/dev/null || break; sleep 0.2; done
  ditto build/Build/Products/Release/MyOS.app /Applications/MyOS.app

  # ditto preserves the bundle's directory mtime, so the folder date looks stale
  # even on a fresh install. Compare the executable instead.
  local a b
  a=$(shasum -a 256 build/Build/Products/Release/MyOS.app/Contents/MacOS/MyOS | cut -c1-16)
  b=$(shasum -a 256 /Applications/MyOS.app/Contents/MacOS/MyOS | cut -c1-16)
  [[ "$a" == "$b" ]] && print "    verified $a" || { print "    HASH MISMATCH"; return 1; }
  open -a /Applications/MyOS.app
}

install_ios() {
  banner "iPhone: where is it"
  ios_reachability

  banner "iPhone: build"
  cd "$ROOT/apps/ios"
  xcodegen generate >/dev/null
  # Build AT the device whenever it is reachable. Targeting the real device is
  # what lets automatic signing register it and settle the trust handshake;
  # `generic/platform=iOS` skips all of that, and the app lands on the phone as
  # "Not Verified" in Settings > VPN & Device Management. Generic is only a
  # fallback so that a phone which is away costs you the install, not the build.
  # Wait for the phone BEFORE building, not after. A generic build installs
  # fine and then sits on the phone as "Not Verified", so waiting to build the
  # right thing beats building the wrong thing quickly.
  local dest="id=$IOS_DEVICE_ID"
  if ! ios_device_present; then
    ios_wait_for_device "$WAIT_MINS" || {
      dest="generic/platform=iOS"
      print "    building generic — the app WILL need a manual Verify on the phone"
    }
  fi
  xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Release \
             -destination "$dest" -derivedDataPath build \
             -allowProvisioningUpdates build >/dev/null

  banner "iPhone: install"
  local app="build/Build/Products/Release-iphoneos/MyOS.app"
  ios_install_waiting "$app" "$WAIT_MINS" \
    || print "    rerun: ./scripts/install-apps.sh ios"

  # This is a free personal team, so the profile lasts 7 days and the app simply
  # stops launching when it lapses. Better to see the date than to be surprised.
  local exp
  exp=$(ios_profile_expiry_human "$app" 2>/dev/null || true)
  [[ -n "$exp" ]] && print "    signing profile good until: $exp  ($(ios_profile_days_left "$app") days)"
}

case "$TARGET" in
  mac)  install_mac ;;
  ios)  install_ios ;;
  both) install_mac; install_ios ;;
  *)    print "usage: install-apps.sh [mac|ios|both] [wait-minutes]"; exit 2 ;;
esac

banner "done"
