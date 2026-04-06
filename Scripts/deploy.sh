#!/bin/bash
# Build, install, and launch MTGCardScanner on a connected iOS device.
#
# Usage:
#   ./scripts/deploy.sh                    # auto-detects first connected device
#   ./scripts/deploy.sh <DEVICE_ID>        # use a specific device

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_ROOT/MTGCardScanner.xcodeproj"
SCHEME="MTGCardScanner"
BUNDLE_ID="com.nikoe.mtgcardscanner"

cd "$PROJECT_ROOT"

# 1. Resolve device ID
if [ -n "$1" ]; then
    DEVICE_ID="$1"
else
    echo "→ Detecting connected iOS device..."
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
        | awk '/connected/ && /iPhone|iPad/ {print $NF}' \
        | head -1)
fi

if [ -z "$DEVICE_ID" ]; then
    echo "✗ No connected iOS device found."
    echo "  Run 'xcrun devicectl list devices' to see what's available,"
    echo "  then pass the device ID as the first argument."
    exit 1
fi

echo "→ Using device: $DEVICE_ID"

# 2. Build for the device (Release configuration via 'install' action)
echo "→ Building MTGCardScanner..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    -quiet \
    clean build install

# 3. Find the built .app
APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -name "MTGCardScanner.app" \
    -path "*InstallationBuildProductsLocation*" \
    -print 2>/dev/null \
    | head -1)

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "✗ Could not find built MTGCardScanner.app"
    exit 1
fi

echo "→ Built: $APP_PATH"

# 4. Install
echo "→ Installing to device..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

# 5. Launch
echo "→ Launching..."
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "✓ Done."
