#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$DIR/android"
APK_OUTPUT="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
DEST_APK="$DIR/Onyx-debug.apk"

export JAVA_HOME="/Users/nata/Library/Java/JavaVirtualMachines/jdk-17.0.19+10/Contents/Home"
export ANDROID_HOME="/Users/nata/Library/Android/sdk"

echo "==> Step 1: Syncing web assets to Android assets..."
mkdir -p "$ANDROID_DIR/app/src/main/assets"
cp "$DIR/startpage.html" "$ANDROID_DIR/app/src/main/assets/startpage.html"
cp "$DIR/settings.html" "$ANDROID_DIR/app/src/main/assets/settings.html"
cp "$DIR/anime.min.js" "$ANDROID_DIR/app/src/main/assets/anime.min.js"
cp "$DIR/logo.svg" "$ANDROID_DIR/app/src/main/assets/logo.svg"

echo "==> Step 2: Compiling Android APK with Gradle..."
cd "$ANDROID_DIR"
./gradlew assembleDebug

if [ -f "$APK_OUTPUT" ]; then
    cp "$APK_OUTPUT" "$DEST_APK"
    echo "=========================================================="
    echo "  ONYX ANDROID BUILD SUCCESSFUL"
    echo "  APK Location: $DEST_APK"
    echo "  Install on device via: adb install -r \"$DEST_APK\""
    echo "=========================================================="
else
    echo "Build failed: APK not found at $APK_OUTPUT"
    exit 1
fi
