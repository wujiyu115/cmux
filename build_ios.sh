#!/usr/bin/env bash
# Build TeamPilot for iOS as an UNSIGNED .ipa.
#
# No Apple signing certificates are configured, so the output cannot be
# installed through Xcode or TestFlight. It is useful for sideloading
# (TrollStore / AltStore / Sideloadly) and for proving the iOS target still
# builds. Once a certificate exists, switch to
# `flutter build ipa --export-options-plist=...` instead.
#
# Usage: ./build_ios.sh [--debug] [--skip-gen] [--proxy host:port]

set -euo pipefail

MODE=release
SKIP_GEN=0
PROXY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --debug) MODE=debug; shift ;;
    --skip-gen) SKIP_GEN=1; shift ;;
    --proxy)
      [ $# -ge 2 ] || { echo "--proxy needs host:port" >&2; exit 1; }
      PROXY="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

cd "$(dirname "$0")/client"

[ "$(uname -s)" = "Darwin" ] || { echo "iOS builds need macOS." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild not found. Install Xcode." >&2; exit 1; }

# CocoaPods pulls GoogleMLKit (via mobile_scanner) straight from dl.google.com,
# which is unreachable on some networks — the download then hangs rather than
# failing, because curl is invoked without a timeout.
if [ -n "$PROXY" ]; then
  export HTTP_PROXY="http://$PROXY" HTTPS_PROXY="http://$PROXY"
  export http_proxy="http://$PROXY" https_proxy="http://$PROXY"
  export ALL_PROXY="socks5h://$PROXY"
  echo "=== using proxy $PROXY ==="
fi

# flutter_alacritty keeps its Rust crate in a nested submodule; without it
# `flutter pub get` fails on a missing path dependency.
RUST_PKG=packages/flutter_alacritty/packages/rust_lib_flutter_alacritty
if [ ! -f "$RUST_PKG/pubspec.yaml" ]; then
  echo "Missing $RUST_PKG — run: git submodule update --init --recursive" >&2
  exit 1
fi

# cargokit cross-compiles the Rust engine during pod install.
if command -v rustup >/dev/null; then
  rustup target list --installed | grep -qx aarch64-apple-ios \
    || { echo "=== adding rust target aarch64-apple-ios ==="; rustup target add aarch64-apple-ios; }
else
  echo "rustup not found; assuming the Rust toolchain can target aarch64-apple-ios." >&2
fi

echo "=== flutter pub get ==="
flutter pub get

if [ "$SKIP_GEN" -eq 1 ]; then
  echo "=== skipping generated sources (--skip-gen) ==="
else
  # Downloads from fonts.gstatic.com; pass --skip-gen to reuse what is on disk.
  echo "=== syncing bundled Google Fonts ==="
  dart run tool/sync_bundled_google_fonts.dart
  echo "=== generating native splash sources ==="
  dart run native_splash_screen_cli gen
fi

echo "=== flutter build ios --$MODE --no-codesign ==="
flutter build ios "--$MODE" --no-codesign

APP=build/ios/iphoneos/Runner.app
[ -d "$APP" ] || { echo "Expected $APP to exist after the build." >&2; exit 1; }

# `flutter build ipa --no-codesign` stops at the .xcarchive because exporting
# needs a signing identity, so wrap the .app into Payload/ ourselves — that is
# all an .ipa is.
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)"
DIST="dist/$VERSION"
IPA="$DIST/teampilot-$VERSION-unsigned.ipa"

rm -rf "$DIST/Payload" "$IPA"
mkdir -p "$DIST/Payload"
cp -R "$APP" "$DIST/Payload/"
(cd "$DIST" && zip -qry "$(basename "$IPA")" Payload && rm -rf Payload)

[ -f "$IPA" ] || { echo "Failed to write $IPA" >&2; exit 1; }
echo
echo "=== unsigned ipa ==="
du -h "$IPA" | awk '{printf "%s  %s\n", $1, $2}'
echo "(unsigned — sideload it; Xcode and TestFlight will reject it)"
