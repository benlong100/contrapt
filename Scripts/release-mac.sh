#!/bin/bash
#
# Build, notarize, and package the Mac app for direct download — the
# no-TestFlight path. Produces build/mac-release/Contrapt-<version>.zip,
# ready to upload to the web site.
#
# One-time setup (the only part the script can't do):
#   1. Make an app-specific password at appleid.apple.com (Sign-In & Security).
#   2. xcrun notarytool store-credentials "contrapt-notary" \
#        --apple-id <your Apple ID email> --team-id 58KR4XUF9K \
#        --password <that app-specific password>
#
# Each release: bump MARKETING_VERSION in Xcode, then run this script.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-contrapt-notary}"
OUT="build/mac-release"
VERSION=$(xcodebuild -project Contrapt.xcodeproj -scheme Contrapt \
    -showBuildSettings -destination 'generic/platform=macOS' 2>/dev/null \
    | awk '/MARKETING_VERSION/ {print $3; exit}')
rm -rf "$OUT" && mkdir -p "$OUT"

echo "→ Archiving Contrapt ${VERSION} (Release)…"
xcodebuild -project Contrapt.xcodeproj -scheme Contrapt -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$OUT/Contrapt.xcarchive" archive

echo "→ Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$OUT/Contrapt.xcarchive" \
    -exportOptionsPlist Scripts/ExportOptions-mac.plist -exportPath "$OUT"

echo "→ Submitting to Apple for notarization (usually a few minutes)…"
ditto -c -k --keepParent "$OUT/Contrapt.app" "$OUT/Contrapt-notarize.zip"
xcrun notarytool submit "$OUT/Contrapt-notarize.zip" \
    --keychain-profile "$PROFILE" --wait

echo "→ Stapling the ticket (so Gatekeeper trusts it offline)…"
xcrun stapler staple "$OUT/Contrapt.app"
rm "$OUT/Contrapt-notarize.zip"

FINAL="$OUT/Contrapt-${VERSION}.zip"
ditto -c -k --keepParent "$OUT/Contrapt.app" "$FINAL"

echo "→ Gatekeeper's own verdict:"
spctl -a -vv "$OUT/Contrapt.app"
echo "✓ Ready to upload: $FINAL"
