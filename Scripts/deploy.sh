#!/bin/bash
# Build, install, and launch MTGCardScanner on a connected iOS device.
#
# Usage:
#   ./scripts/deploy.sh                    # auto-detects first connected device
#   ./scripts/deploy.sh <DEVICE_NAME>      # use a specific device by name

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_ROOT/MTGCardScanner.xcodeproj"
SCHEME="MTGCardScanner"
BUNDLE_ID="com.nikoe.mtgcardscanner"

cd "$PROJECT_ROOT"

# 1. Resolve device — get both xcodebuild ID and devicectl UUID
if [ -n "$1" ]; then
    DEVICE_FILTER="$1"
else
    # Default to Niko's iPhone when no device specified
    # Device names use smart apostrophe (Unicode RIGHT SINGLE QUOTATION MARK)
    DEVICE_FILTER="Niko"
fi

echo "→ Detecting connected iOS device..."

# Get xcodebuild-compatible device ID and name from destinations
DEST_LINE=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | grep 'platform:iOS, arch:' \
    | grep -v 'Simulator' \
    | grep -v 'placeholder')

if [ -n "$DEVICE_FILTER" ]; then
    DEST_LINE=$(echo "$DEST_LINE" | grep -i "$DEVICE_FILTER" | head -1)
else
    DEST_LINE=$(echo "$DEST_LINE" | head -1)
fi

if [ -z "$DEST_LINE" ]; then
    echo "✗ No connected iOS device found."
    echo "  Run 'xcodebuild -project $PROJECT -scheme $SCHEME -showdestinations'"
    echo "  to see what's available."
    exit 1
fi

# Extract xcodebuild device ID
XCODE_DEVICE_ID=$(echo "$DEST_LINE" | sed 's/.*id://' | sed 's/[,}].*//' | tr -d '[:space:]')
# Extract device name
DEVICE_NAME=$(echo "$DEST_LINE" | sed 's/.*name://' | sed 's/[,}].*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

echo "→ Using device: $DEVICE_NAME ($XCODE_DEVICE_ID)"

# 2. Build for the device
echo "→ Building MTGCardScanner..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "id=$XCODE_DEVICE_ID" \
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

# 4. Get devicectl UUID for install/launch (different from xcodebuild ID)
DEVICECTL_UUID=$(xcrun devicectl list devices 2>/dev/null \
    | grep -i "$DEVICE_NAME" \
    | awk '{for(i=1;i<=NF;i++){if($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-/){print $i; exit}}}')

if [ -z "$DEVICECTL_UUID" ]; then
    echo "⚠ Could not find devicectl UUID for '$DEVICE_NAME', trying xcodebuild ID..."
    DEVICECTL_UUID="$XCODE_DEVICE_ID"
fi

# 5. Install
echo "→ Installing to device..."
xcrun devicectl device install app --device "$DEVICECTL_UUID" "$APP_PATH"

# 6. Launch
echo "→ Launching..."
xcrun devicectl device process launch --device "$DEVICECTL_UUID" "$BUNDLE_ID"

echo "✓ Done."
