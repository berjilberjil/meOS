#!/bin/zsh
# Build + install MyOS. No arguments installs both.
#
#   ./scripts/install-apps.sh          mac + iphone
#   ./scripts/install-apps.sh mac
#   ./scripts/install-apps.sh ios
#
# The iPhone install works over Wi-Fi once the device is set to "Connect via
# network" (Xcode > Window > Devices and Simulators > select iPhone > tick the
# box). That is a one-time Xcode step — devicectl has no CLI equivalent, it
# only exposes pair/unpair. After that, leave the cable in the drawer.
set -euo pipefail

ROOT="${0:A:h:h}"
DEVICE="2224632C-57C6-555C-8280-459061A2883F"   # iPhone 15
TARGET="${1:-both}"

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
  banner "iPhone: transport check"
  local transport
  # `|| true` matters: under `set -euo pipefail`, `head -1` closing the pipe
  # early makes the whole pipeline fail and aborts the install for nothing.
  transport=$(xcrun devicectl list devices -v 2>/dev/null | grep -A1 "transportType" | grep -oE "wired|network" | head -1 || true)
  print "    transport: ${transport:-unknown}"
  [[ "$transport" == "wired" ]] && print "    (tick 'Connect via network' in Xcode to drop the cable)"

  banner "iPhone: build"
  cd "$ROOT/apps/ios"
  xcodegen generate >/dev/null
  xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Release \
             -destination "id=$DEVICE" -derivedDataPath build \
             -allowProvisioningUpdates build >/dev/null

  banner "iPhone: install"
  xcrun devicectl device install app --device "$DEVICE" \
    build/Build/Products/Release-iphoneos/MyOS.app | grep -E "App installed|bundleID"
}

case "$TARGET" in
  mac)  install_mac ;;
  ios)  install_ios ;;
  both) install_mac; install_ios ;;
  *)    print "usage: install-apps.sh [mac|ios|both]"; exit 2 ;;
esac

banner "done"
