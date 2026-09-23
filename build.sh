#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Onyx"
APP_DIR="$DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Step 1: Generating high-resolution Onyx AppIcon.icns..."
swift "$DIR/generate_icon.swift"
iconutil -c icns "$DIR/Onyx.iconset" -o "$DIR/AppIcon.icns"

echo "==> Step 2: Compiling Onyx native binary with WebKit..."
find "$DIR/Sources" -name '*.swift' -print0 | xargs -0 swiftc -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path)" -O -wmo -module-name Onyx -o "$DIR/onyx"

echo "==> Step 3: Packaging standalone $APP_NAME.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$DIR/onyx" "$MACOS/$APP_NAME"
cp "$DIR/startpage.html" "$RESOURCES/startpage.html"
cp "$DIR/settings.html" "$RESOURCES/settings.html"
cp "$DIR/anime.min.js" "$RESOURCES/anime.min.js"
cp "$DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$DIR/logo.svg" "$RESOURCES/logo.svg"

cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.company.onyx</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>Web site URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>http</string>
                <string>https</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# A stable signing identity keeps the app's designated requirement constant across rebuilds,
# so the Keychain (password vault) does not re-prompt after every build. Override with
# ONYX_SIGN_IDENTITY; falls back to ad-hoc signing when no Apple Development identity exists.
SIGN_IDENTITY="${ONYX_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> Step 4: Ad-hoc code signing $APP_NAME.app (Keychain will re-prompt after each rebuild)..."
else
    echo "==> Step 4: Code signing $APP_NAME.app with identity $SIGN_IDENTITY..."
fi
codesign --force --deep -s "$SIGN_IDENTITY" "$APP_DIR"

echo "==> Step 5: Syncing to ~/Applications (Spotlight & Dock accessible)..."
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/$APP_NAME.app"
cp -R "$APP_DIR" "$HOME/Applications/$APP_NAME.app"

echo "==> Step 6: Refreshing macOS Dock and LaunchServices icon cache..."
touch "$HOME/Applications/$APP_NAME.app"
touch "$APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/$APP_NAME.app" 2>/dev/null || true
killall Dock 2>/dev/null || true

echo "=========================================================="
echo "  ONYX BUILD COMPLETE"
echo "  Local bundle: $APP_DIR"
echo "  Installed in: $HOME/Applications/$APP_NAME.app"
echo "  Launch with: open \"$APP_DIR\" or Spotlight 'Onyx'"
echo "=========================================================="
