#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="HoldToTranslate"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_NAME="hold-to-translate"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-1}"
FAIL_ON_UNSIGNED="${FAIL_ON_UNSIGNED:-0}"
SIGN_IDENTITY_FILE="$ROOT_DIR/.build-signing-identity"
SVG_ICON_SOURCE="$ROOT_DIR/assets/app-icon.svg"
ICON_FILE_NAME="AppIcon"
ICON_ICNS_PATH="$RESOURCES_DIR/${ICON_FILE_NAME}.icns"
STATUS_BAR_ICON_FILE_NAME="StatusBarIconTemplate"
STATUS_BAR_ICON_PATH="$RESOURCES_DIR/${STATUS_BAR_ICON_FILE_NAME}.png"

generate_app_icon_if_possible() {
  if [[ ! -f "$SVG_ICON_SOURCE" ]]; then
    echo "[WARN] SVG icon source not found: $SVG_ICON_SOURCE"
    return 1
  fi

  if ! command -v qlmanage >/dev/null 2>&1 || ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    echo "[WARN] Missing one of required tools (qlmanage/sips/iconutil); skip Dock icon generation."
    return 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  local iconset_dir="$tmpdir/${ICON_FILE_NAME}.iconset"
  local raster_png

  qlmanage -t -s 1024 -o "$tmpdir" "$SVG_ICON_SOURCE" >/dev/null 2>&1 || true
  raster_png="$(find "$tmpdir" -maxdepth 1 -type f -name '*.png' | head -n 1)"

  if [[ -z "$raster_png" || ! -f "$raster_png" ]]; then
    echo "[WARN] Failed to rasterize SVG icon with qlmanage; skip Dock icon generation."
    rm -rf "$tmpdir"
    return 1
  fi

  mkdir -p "$iconset_dir"

  local size
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$raster_png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    local size2x=$((size * 2))
    sips -z "$size2x" "$size2x" "$raster_png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
  done

  if iconutil -c icns "$iconset_dir" -o "$ICON_ICNS_PATH" >/dev/null 2>&1; then
    sips -z 32 32 "$raster_png" --out "$STATUS_BAR_ICON_PATH" >/dev/null 2>&1 || true
    echo "[OK] Dock icon generated: $ICON_ICNS_PATH"
    rm -rf "$tmpdir"
    return 0
  fi

  echo "[WARN] iconutil failed; skip Dock icon generation."
  rm -rf "$tmpdir"
  return 1
}

resolve_sign_identity() {
  if [[ -n "$SIGN_IDENTITY" ]]; then
    return 0
  fi

  if [[ -f "$SIGN_IDENTITY_FILE" ]]; then
    local pinned
    pinned="$(head -n 1 "$SIGN_IDENTITY_FILE" | tr -d '[:space:]')"
    if [[ -n "$pinned" ]]; then
      SIGN_IDENTITY="$pinned"
      return 0
    fi
  fi

  local -a identities
  identities=("${(@f)$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/^[[:space:]]*[0-9][0-9)] \([0-9A-F]\{40\}\) "\(Apple Development:[^"]*\)".*/\1|\2/p')}")

  if (( ${#identities[@]} == 0 )); then
    return 1
  fi

  if (( ${#identities[@]} > 1 )); then
    echo "[ERROR] Multiple Apple Development identities found; refusing ambiguous auto-selection."
    local item
    for item in "${identities[@]}"; do
      echo "  - $item"
    done
    echo "[TIP] Set SIGN_IDENTITY to a certificate SHA-1 hash and rerun."
    echo "[TIP] Example: SIGN_IDENTITY=<SHA1> ./scripts/build_app.sh"
    return 2
  fi

  SIGN_IDENTITY="${identities[1]%%|*}"
  echo "$SIGN_IDENTITY" > "$SIGN_IDENTITY_FILE"
  return 0
}

resolve_sign_identity || {
  if [[ "$FAIL_ON_UNSIGNED" == "1" ]]; then
    echo "[ERROR] No usable signing identity resolved."
    echo "[TIP] Export SIGN_IDENTITY=<SHA1> and rerun, or set FAIL_ON_UNSIGNED=0 to allow unsigned build."
    exit 1
  else
    echo "[WARN] No signing identity available; continue with unsigned build."
    echo "[WARN] Accessibility permission may still need to be re-granted after some updates on unsigned apps."
  fi
}

swift build -c release --package-path "$ROOT_DIR"

BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
if [[ ! -d "$BUILD_DIR" ]]; then
  BUILD_DIR="$ROOT_DIR/.build/release"
fi

BINARY_PATH="$BUILD_DIR/$BINARY_NAME"
if [[ ! -f "$BINARY_PATH" ]]; then
  echo "[ERROR] Release binary not found: $BINARY_PATH"
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

ICON_PLIST_BLOCK=""
if generate_app_icon_if_possible; then
  ICON_PLIST_BLOCK=$(cat <<EOF
  <key>CFBundleIconFile</key>
  <string>${ICON_FILE_NAME}</string>
EOF
)
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>HoldToTranslate</string>
  <key>CFBundleDisplayName</key>
  <string>HoldToTranslate</string>
  <key>CFBundleIdentifier</key>
  <string>local.holdtotranslate.app</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>hold-to-translate</string>
${ICON_PLIST_BLOCK}
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cp "$BINARY_PATH" "$MACOS_DIR/$BINARY_NAME"
chmod +x "$MACOS_DIR/$BINARY_NAME"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  echo "[OK] Signed with identity: $SIGN_IDENTITY"
  codesign --display --verbose=2 "$APP_BUNDLE" 2>&1 | sed -n 's/^Identifier=/[INFO] Identifier=/p; s/^TeamIdentifier=/[INFO] TeamIdentifier=/p'
else
  echo "[WARN] Unsigned app bundle. Accessibility/Keychain trust may reset after rebuilds."
  echo "[TIP] Use SIGN_IDENTITY=<SHA1> ./scripts/build_app.sh"
fi

if [[ "$INSTALL_TO_APPLICATIONS" == "1" ]]; then
  APP_TARGET="/Applications/${APP_NAME}.app"
  if [[ -d "$APP_TARGET" ]] && command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$APP_BUNDLE/" "$APP_TARGET/"
  else
    rm -rf "$APP_TARGET"
    cp -R "$APP_BUNDLE" "$APP_TARGET"
  fi
  xattr -dr com.apple.quarantine "$APP_TARGET" 2>/dev/null || true
  echo "[OK] Installed: /Applications/${APP_NAME}.app"
fi

echo "[OK] App bundle created: $APP_BUNDLE"
echo "[TIP] Launch: open '$APP_BUNDLE'"
echo "[TIP] Accessibility path: $MACOS_DIR/$BINARY_NAME"
