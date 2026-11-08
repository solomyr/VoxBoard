#!/bin/bash
# Build and install on an already-paired iPhone. No App Store upload.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 DEVICE_UDID [DEVELOPMENT_TEAM]" >&2
  echo "List connected devices with: xcrun devicectl list devices" >&2
  exit 2
fi

VOXBOARD_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VOXBOARD_DEVICE="$1"
VOXBOARD_BUILD="${VOXBOARD_DERIVED_DATA:-$VOXBOARD_ROOT/build/device}"
VOXBOARD_SIGNING=("CODE_SIGN_STYLE=Automatic")
if [[ $# -eq 2 ]]; then
  VOXBOARD_SIGNING+=("DEVELOPMENT_TEAM=$2")
elif [[ ! -f "$VOXBOARD_ROOT/signing.local.yml" ]]; then
  echo "Pass a team ID or create signing.local.yml as described in README.md." >&2
  exit 2
fi

cd "$VOXBOARD_ROOT"
./scripts/bootstrap-llama.sh
xcodegen generate
xcodebuild -project VoxBoard.xcodeproj -scheme VoxBoard -configuration Release \
  -destination "id=$VOXBOARD_DEVICE" -derivedDataPath "$VOXBOARD_BUILD" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  "${VOXBOARD_SIGNING[@]}" build

VOXBOARD_APP="$VOXBOARD_BUILD/Build/Products/Release-iphoneos/Sayboard.app"
codesign --verify --deep --strict "$VOXBOARD_APP"
xcrun devicectl device install app --device "$VOXBOARD_DEVICE" "$VOXBOARD_APP"
xcrun devicectl device process launch --device "$VOXBOARD_DEVICE" --terminate-existing app.voxboard
