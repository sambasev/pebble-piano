#!/bin/bash
# Builds a TestFlight archive of PerfectPiano, and uploads it when run with --upload.
#
#   App/ship.sh            merge in the packaging branch, gather backing tracks, generate the
#                          Xcode project, build and archive (nothing leaves this Mac)
#   App/ship.sh --upload   upload the last archive to App Store Connect (needs the app record)
#
# Uses the Apple account signed into Xcode (Settings → Accounts) for signing and upload.
# Everything is logged to App/build/ship.log.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$APP_DIR/.." && pwd)"
BUILD="$APP_DIR/build"
ARCHIVE="$BUILD/PerfectPiano.xcarchive"
mkdir -p "$BUILD"
exec > >(tee -a "$BUILD/ship.log") 2>&1
echo "=== $(date) ship.sh $*"

team_id() {
    # The team is the OU of the Apple Development (or Distribution) signing certificate.
    local cert
    for name in "Apple Development" "Apple Distribution"; do
        cert=$(security find-certificate -c "$name" -p 2>/dev/null || true)
        if [ -n "$cert" ]; then
            echo "$cert" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
                | awk -F' = ' '/organizationalUnitName/ {print $2; exit}'
            return
        fi
    done
}

if [ "${1:-}" = "--upload" ]; then
    [ -d "$ARCHIVE" ] || { echo "No archive at $ARCHIVE: run App/ship.sh first."; exit 1; }
    cat > "$BUILD/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$BUILD/ExportOptions.plist" \
        -exportPath "$BUILD/export" -allowProvisioningUpdates
    echo "=== UPLOADED. App Store Connect is processing the build (15–60 min)."
    exit 0
fi

cd "$REPO"

# 1. Packaging branch on top of the current work.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "Uncommitted changes in $REPO: commit or stash them first."; exit 1
fi
current=$(git branch --show-current)
if [ "$current" != "testflight-build" ]; then
    git checkout -B testflight-build
fi
# Latest main and the packaging branch, on top of the current work.
for branch in main testflight; do
    git fetch origin "$branch"
    git merge --no-edit FETCH_HEAD
done
echo "Building from: $(git log --oneline -1)"

# 2. Backing tracks: saved settings from the library plus the audio files.
LIB="$HOME/Library/Application Support/PianoPad/Backing Tracks"
mkdir -p BackingTracks
if [ -d "$LIB" ]; then cp -R "$LIB/." BackingTracks/; fi
if [ -d "$REPO/../backing_tracks" ]; then cp "$REPO/../backing_tracks/"* BackingTracks/ 2>/dev/null || true; fi
echo "Backing tracks to ship:"; ls -R BackingTracks

# 3. Xcode project.
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
TEAM=$(team_id)
[ -n "$TEAM" ] || { echo "No signing certificate found: open Xcode → Settings → Accounts → Manage Certificates → + Apple Development."; exit 1; }
echo "Team: $TEAM"
cd "$APP_DIR"
PIANOPAD_TEAM="$TEAM" xcodegen

# 4. Archive (signs with the Xcode account, registering the bundle ID if needed).
# Every archive gets a new build number (the date and time), since App Store Connect rejects
# one it has already seen. Set BUILD_NUMBER to override.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
rm -rf "$ARCHIVE"
xcodebuild -project PerfectPiano.xcodeproj -scheme PianoPadApp -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive
echo "=== ARCHIVED build $BUILD_NUMBER: $ARCHIVE"
echo "Try it: open \"$ARCHIVE/Products/Applications/PerfectPiano.app\""
