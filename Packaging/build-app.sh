#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${TOUBAR_VERSION:-1.0.0}"
APP_DIR="$ROOT_DIR/dist/ToubarReplace.app"
DMG_PATH="$ROOT_DIR/dist/ToubarReplace-${VERSION}.dmg"
PKG_PATH="$ROOT_DIR/dist/ToubarReplace-${VERSION}.pkg"

if [[ -n "${TOUBAR_BINARY:-}" ]]; then
  BINARY_PATH="$TOUBAR_BINARY"
else
  swift build -c release
  BINARY_PATH="$ROOT_DIR/.build/release/ToubarReplace"
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/ToubarReplace"
cp "Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon-source.png" "$APP_DIR/Contents/Resources/AppIcon.png"
chmod +x "$APP_DIR/Contents/MacOS/ToubarReplace"

/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null

rm -f "$DMG_PATH"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/toubarreplace-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
if ! /usr/bin/hdiutil create -volname "ToubarReplace" -srcfolder "$STAGING_DIR" \
  -ov -format UDZO "$DMG_PATH" >/dev/null; then
  echo "Warning: hdiutil could not create a DMG in this environment; continuing with PKG." >&2
  rm -f "$DMG_PATH"
fi

rm -f "$PKG_PATH"
/usr/bin/pkgbuild --component "$APP_DIR" --install-location /Applications \
  --identifier com.toubarreplace.app --version "$VERSION" "$PKG_PATH" >/dev/null

echo "Built:"
echo "  $APP_DIR"
[[ -e "$DMG_PATH" ]] && echo "  $DMG_PATH"
echo "  $PKG_PATH"
