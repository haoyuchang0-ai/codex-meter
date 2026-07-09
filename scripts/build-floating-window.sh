#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$ROOT/CodexQuotaFloat.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/swift-module-cache"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE_DIR" "$MACOS_DIR" "$APP_DIR/Contents/Resources"
cp "$ROOT/FloatingWindow/Info.plist" "$APP_DIR/Contents/Info.plist"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
SWIFTC_ARGS=(
  -module-cache-path "$MODULE_CACHE_DIR"
  -framework Cocoa
  "$ROOT/FloatingWindow/QuotaModels.swift"
  "$ROOT/FloatingWindow/main.swift"
  -o "$BUILD_DIR/CodexQuotaFloat"
)

if [[ -n "$SDK_PATH" ]]; then
  swiftc -sdk "$SDK_PATH" "${SWIFTC_ARGS[@]}"
else
  swiftc "${SWIFTC_ARGS[@]}"
fi

cp "$BUILD_DIR/CodexQuotaFloat" "$MACOS_DIR/CodexQuotaFloat"
chmod +x "$MACOS_DIR/CodexQuotaFloat"

echo "Built $APP_DIR"
