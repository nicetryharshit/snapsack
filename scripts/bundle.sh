#!/bin/bash
# Builds SnapSack and wraps it into build/SnapSack.app (menu bar app, custom icon, stable code signature).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SnapSack.app"
BUNDLE_ID="app.snapsack.mac"

echo "→ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/SnapSack"

echo "→ Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnapSack"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ Building the icon…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size"     Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
  sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signing normally changes identity on every build, which makes macOS forget the
# Accessibility / Screen Recording grants. Pinning the designated requirement to the bundle
# identifier keeps them across rebuilds.
echo "→ Signing…"
if ! codesign --force --sign - --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP" 2>/dev/null; then
  echo "  (pinned requirement not accepted; falling back to plain ad-hoc signing)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

echo "✓ Built ${APP}"
