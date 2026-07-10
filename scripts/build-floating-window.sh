#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$ROOT/CodexQuotaFloat.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/swift-module-cache"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE_DIR" "$MACOS_DIR" "$APP_DIR/Contents/Resources"
cp "$ROOT/FloatingWindow/Info.plist" "$APP_DIR/Contents/Info.plist"

SDK_PATH="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
FALLBACK_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
SWIFTC_ARGS=(
  -module-cache-path "$MODULE_CACHE_DIR"
  -framework Cocoa
  "$ROOT/FloatingWindow/QuotaModels.swift"
  "$ROOT/FloatingWindow/main.swift"
  -o "$BUILD_DIR/CodexQuotaFloat"
)

if [[ -n "$SDK_PATH" ]]; then
  if ! swiftc -sdk "$SDK_PATH" "${SWIFTC_ARGS[@]}"; then
    if [[ ! -d "$FALLBACK_SDK" || "$SDK_PATH" == "$FALLBACK_SDK" ]]; then
      exit 1
    fi
    echo "Default SDK failed; retrying with $FALLBACK_SDK"
    swiftc -sdk "$FALLBACK_SDK" "${SWIFTC_ARGS[@]}"
  fi
else
  swiftc "${SWIFTC_ARGS[@]}"
fi

cp "$BUILD_DIR/CodexQuotaFloat" "$MACOS_DIR/CodexQuotaFloat"
chmod +x "$MACOS_DIR/CodexQuotaFloat"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
