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
    # Default to Niko's iPhone (00008101-000519A91468001E)
    DEVICE_FILTER="00008101-000519A91468001E"
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

# 4. Install & Launch using xcodebuild device ID
echo "→ Installing to device..."
xcrun devicectl device install app --device "$XCODE_DEVICE_ID" "$APP_PATH"

echo "→ Launching..."
xcrun devicectl device process launch --device "$XCODE_DEVICE_ID" "$BUNDLE_ID"

echo "✓ Done."
