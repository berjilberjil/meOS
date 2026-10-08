#!/usr/bin/env bash
# Build and open the new MyOS Mac app (apps/mac2).
# One command: ./scripts/install-mac.sh
set -euo pipefail

command -v xcodebuild >/dev/null || { echo "Xcode is required: install from the App Store, then run: xcode-select --install"; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh"; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen

cd "$(dirname "$0")/../apps/mac2"
xcodegen generate

xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug build 2>&1 | tail -20

APP_DIR=$(xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
open "$APP_DIR/MyOS.app"
