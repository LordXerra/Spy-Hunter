#!/bin/bash
#
# Builds Spy Hunter as a self-contained macOS .app and installs it to
# /Applications so it appears in Launchpad.
#
#   ./build_app.sh            build and install
#   ./build_app.sh --no-install   build into ./build only
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Spy Hunter"
BUNDLE_ID="com.tonybrice.spyhunter"
VERSION="0.99"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Refreshing assets"
python3 Tools/build_assets.py

echo "==> Building release binary"
if [ "${SPYHUNTER_UNIVERSAL:-0}" = "1" ]; then
    # Fat arm64 + x86_64 binary, so the app also runs on Intel Macs.
    swift build -c release --arch arm64 --arch x86_64
    PRODUCTS=".build/apple/Products/Release"
else
    swift build -c release
    PRODUCTS=".build/release"
fi

BIN="$PRODUCTS/SpyHunter"
RES_BUNDLE="$PRODUCTS/SpyHunter_SpyHunter.bundle"
[ -x "$BIN" ] || { echo "error: $BIN not found"; exit 1; }
[ -d "$RES_BUNDLE" ] || { echo "error: $RES_BUNDLE not found"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/SpyHunter"
# Bundle.module looks in Contents/Resources, so the SPM resource bundle goes here.
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"

echo "==> Generating icon from project sprites"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
python3 Tools/make_icon.py "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>SpyHunter</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.arcade-games</string>
    <key>NSHumanReadableCopyright</key>
    <string>Developed by Tony Brice. Free including the source code. All images belong to their respective creators.</string>
</dict>
</plist>
PLIST

# Sign with the Developer ID so macOS identifies the app by team rather than by
# a hash of the binary — otherwise every rebuild looks like a brand-new app.
# Anyone building from source without this certificate gets an ad-hoc signature.
SIGN_ID="${SIGN_ID:-Developer ID Application: Tony Brice (MS88W9DG9C)}"
if security find-identity -v -p codesigning | grep -qF "\"$SIGN_ID\""; then
    echo "==> Signing with $SIGN_ID"
    # Hardened runtime matches what release_dmg.sh ships. No timestamp here so
    # local builds work offline; release_dmg.sh re-signs with one.
    codesign --force --options runtime --timestamp=none \
             --sign "$SIGN_ID" "$APP/Contents/MacOS/SpyHunter"
    codesign --force --options runtime --timestamp=none \
             --sign "$SIGN_ID" "$APP"
    codesign --verify --strict "$APP"
else
    echo "==> \"$SIGN_ID\" not in keychain; ad-hoc signing instead"
    codesign --force --deep --sign - "$APP" 2>/dev/null || \
        echo "    (codesign unavailable; app will still run)"
fi

echo "==> Built $APP"

if [ "${1:-}" != "--no-install" ]; then
    DEST="/Applications/$APP_NAME.app"
    echo "==> Installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    # Nudge Launchpad/Spotlight to notice the new app.
    touch "$DEST"
    echo "==> Installed. Look for \"$APP_NAME\" in Launchpad."
fi
