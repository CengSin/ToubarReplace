#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${TOUBAR_VERSION:-1.0.0}"
APP_DIR="$ROOT_DIR/dist/ToubarReplace.app"
DMG_PATH="$ROOT_DIR/dist/ToubarReplace-${VERSION}.dmg"
PKG_PATH="$ROOT_DIR/dist/ToubarReplace-${VERSION}.pkg"
UNIVERSAL_DIR="$ROOT_DIR/.build/universal-release"
UNIVERSAL_BINARY="$UNIVERSAL_DIR/ToubarReplace"

build_arch() {
  local arch="$1"
  echo "Building release for ${arch}…" >&2
  swift build -c release --arch "$arch" >&2
  local candidate
  candidate="$ROOT_DIR/.build/${arch}-apple-macosx/release/ToubarReplace"
  if [[ ! -x "$candidate" ]]; then
    candidate="$ROOT_DIR/.build/release/ToubarReplace"
  fi
  if [[ ! -x "$candidate" ]]; then
    echo "error: missing release binary for arch ${arch}" >&2
    return 1
  fi
  # Confirm the product actually contains the requested slice when multi-arch layout is used.
  if ! /usr/bin/lipo -info "$candidate" 2>/dev/null | /usr/bin/grep -q "$arch"; then
    # Single-arch path may still be correct when host == arch.
    if ! /usr/bin/file "$candidate" | /usr/bin/grep -q "$arch"; then
      echo "error: binary at ${candidate} is not ${arch}" >&2
      return 1
    fi
  fi
  print -r -- "$candidate"
}

if [[ -n "${TOUBAR_BINARY:-}" ]]; then
  BINARY_PATH="$TOUBAR_BINARY"
else
  mkdir -p "$UNIVERSAL_DIR"
  typeset -a built_paths
  built_paths=()
  typeset -a built_archs
  built_archs=()

  for arch in arm64 x86_64; do
    # Do not name this `path` — in zsh that aliases $PATH and breaks subsequent commands.
    if arch_binary="$(build_arch "$arch")"; then
      built_paths+=("$arch_binary")
      built_archs+=("$arch")
    else
      echo "Warning: failed to build ${arch}; continuing with remaining arches." >&2
    fi
  done

  if (( ${#built_paths[@]} == 0 )); then
    echo "error: could not build ToubarReplace for any architecture" >&2
    exit 1
  fi

  if (( ${#built_paths[@]} == 1 )); then
    BINARY_PATH="${built_paths[1]}"
    echo "Packaging single-arch binary (${built_archs[1]})."
  else
    /usr/bin/lipo -create "${built_paths[@]}" -output "$UNIVERSAL_BINARY"
    chmod +x "$UNIVERSAL_BINARY"
    BINARY_PATH="$UNIVERSAL_BINARY"
    echo "Packaging universal binary: ${built_archs[*]}"
  fi
  /usr/bin/file "$BINARY_PATH" || true
  /usr/bin/lipo -info "$BINARY_PATH" 2>/dev/null || true
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/ToubarReplace"
cp "Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
  "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" \
  "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon-source.png" "$APP_DIR/Contents/Resources/AppIcon.png"
# Bundled Agent brand marks (fallback when no local .app icon).
# Loaded at runtime via Bundle.main …/AgentIcons/ (see agentDefaultIcon).
# Do NOT copy SPM's ToubarReplace_ToubarReplace.bundle into the .app:
# swift build emits a flat directory of loose files (no Info.plist), so
# codesign --deep fails with "bundle format unrecognized, invalid, or unsuitable".
# Putting that folder at the .app root also breaks modern app layout
# ("unsealed contents present in the bundle root").
if [[ -d "Sources/ToubarReplace/Resources/AgentIcons" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/AgentIcons"
  cp Sources/ToubarReplace/Resources/AgentIcons/*.png \
    "$APP_DIR/Contents/Resources/AgentIcons/"
fi
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
/usr/bin/lipo -info "$APP_DIR/Contents/MacOS/ToubarReplace" 2>/dev/null || \
  /usr/bin/file "$APP_DIR/Contents/MacOS/ToubarReplace"
