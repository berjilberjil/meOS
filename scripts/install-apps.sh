#!/bin/zsh
# Build + install MyOS. No arguments installs both.
#
#   ./scripts/install-apps.sh              mac + iphone
#   ./scripts/install-apps.sh mac
#   ./scripts/install-apps.sh ios
#   ./scripts/install-apps.sh ios 0        build, install if the phone is there, don't wait
#   ./scripts/install-apps.sh ios 60       wait up to an hour for the phone
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
DEVICE="2224632C-57C6-555C-8280-459061A2883F"   # iPhone 15
HOSTNAME_LOCAL="Berjil-Jacob.coredevice.local"
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
  # `generic/platform=iOS` builds a device slice without a device attached, so a
  # phone that is off the network costs you the install, not the build.
  xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Release \
             -destination "generic/platform=iOS" -derivedDataPath build \
             -allowProvisioningUpdates build >/dev/null

  banner "iPhone: install"
  ios_install_waiting
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
  if ping -c 1 -W 1500 "$HOSTNAME_LOCAL" >/dev/null 2>&1; then
    print "    phone is on this network but the tunnel is down — it should come back on wake"
  else
    print "    phone is NOT on this Wi-Fi (cellular, another network, or asleep)"
    print "    wireless debugging needs both on the same LAN; this Mac is on $(ipconfig getifaddr en0 2>/dev/null || print '?')"
  fi
}

# Retries until the phone shows up. The whole point: an install you start and
# walk away from.
ios_install_waiting() {
  local app="build/Build/Products/Release-iphoneos/MyOS.app"
  local deadline=$(( $(date +%s) + WAIT_MINS * 60 ))
  local first=1
  while :; do
    if xcrun devicectl device install app --device "$DEVICE" "$app" 2>/dev/null \
         | grep -E "App installed|bundleID"; then
      print "    installed"
      return 0
    fi
    if (( $(date +%s) >= deadline )); then
      print "    phone never came back within ${WAIT_MINS}m — rerun: ./scripts/install-apps.sh ios"
      return 1
    fi
    if (( first )); then
      print "    waiting for the phone (up to ${WAIT_MINS}m) — unlock it on this Wi-Fi and it installs itself"
      first=0
    fi
    sleep 10
  done
}

case "$TARGET" in
  mac)  install_mac ;;
  ios)  install_ios ;;
  both) install_mac; install_ios ;;
  *)    print "usage: install-apps.sh [mac|ios|both] [wait-minutes]"; exit 2 ;;
esac

banner "done"
