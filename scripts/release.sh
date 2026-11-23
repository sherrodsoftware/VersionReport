#!/bin/zsh
# Builds a Developer ID signed, notarized, stapled, and Sparkle-signed installer
# package in dist/, and prints the appcast entry for it.
#
# Usage: scripts/release.sh [--hotfix] [--skip-tests] [--skip-notarize]
#   --hotfix         Name the package VersionReport-<version>-build<build>.pkg, for a
#                    new build that replaces the package on an existing release.
#   --skip-tests     Don't run the unit tests first.
#   --skip-notarize  Stop after building the signed package (no notarization,
#                    stapling, or Sparkle signature).
#
# NOTARY_PROFILE sets the notarytool keychain profile (default VersionReportNotaryAPI).
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="LAR9U97K23"
BUNDLE_ID="com.sherrodsoftware.VersionReport"
PROJECT="Version Report.xcodeproj"
SCHEME="Version Report"
APP_BUNDLE="Version Report.app"
INSTALLER_IDENTITY="Developer ID Installer: JOHN WILLIAM SHERROD (${TEAM_ID})"
NOTARY_PROFILE="${NOTARY_PROFILE:-VersionReportNotaryAPI}"
SPARKLE_ACCOUNT="Sherrod Software"
APPCAST_URL="https://www.sherrodsoftware.com/versionreport/appcast.xml"
RELEASES_URL="https://github.com/sherrodsoftware/VersionReport/releases/download"

HOTFIX=false
SKIP_TESTS=false
SKIP_NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --hotfix) HOTFIX=true ;;
        --skip-tests) SKIP_TESTS=true ;;
        --skip-notarize) SKIP_NOTARIZE=true ;;
        *) echo "Unknown option: $arg"; exit 2 ;;
    esac
done

WORK="build/release"
ARCHIVE="${WORK}/VersionReport.xcarchive"
EXPORT="${WORK}/export"
rm -rf "$WORK"
mkdir -p "$WORK" dist

if [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: the working tree has uncommitted changes, which will be in this build"
fi

if ! $SKIP_TESTS; then
    echo "==> Running tests"
    xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' -quiet
fi

echo "==> Archiving"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -archivePath "$ARCHIVE" -allowProvisioningUpdates archive -quiet

echo "==> Exporting with Developer ID"
cat > "${WORK}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "${WORK}/ExportOptions.plist" -allowProvisioningUpdates -quiet

APP="${EXPORT}/${APP_BUNDLE}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP}/Contents/Info.plist")

# Sparkle only offers a build whose number is higher than the one people have.
LIVE_BUILD=$(curl -fsSL "${APPCAST_URL}?$(date +%s)" | sed -n 's/.*sparkle:version="\([0-9]*\)".*/\1/p' | head -1 || true)
if [[ -n "$LIVE_BUILD" && "$BUILD" -le "$LIVE_BUILD" ]]; then
    echo "Build ${BUILD} isn't higher than the live appcast's ${LIVE_BUILD}, so Sparkle wouldn't offer it."
    echo "Bump CURRENT_PROJECT_VERSION in Xcode, commit it, and run this again."
    exit 1
fi

if $HOTFIX; then
    PKG="dist/VersionReport-${VERSION}-build${BUILD}.pkg"
    ASSET="VersionReport-${VERSION}-build${BUILD}.pkg"
else
    PKG="dist/Version Report ${VERSION}.pkg"
    ASSET="Version.Report.${VERSION}.pkg"   # GitHub replaces spaces with dots
fi

echo "==> Checking the app (version ${VERSION}, build ${BUILD})"
codesign --verify --deep --strict "$APP"
details=$(codesign -dv --verbose=2 "$APP" 2>&1)
grep -q "Identifier=${BUNDLE_ID}" <<< "$details" || { echo "Unexpected bundle identifier"; exit 1; }
grep -q "TeamIdentifier=${TEAM_ID}" <<< "$details" || { echo "Not signed by ${TEAM_ID}"; exit 1; }
grep -q "Authority=Developer ID Application" <<< "$details" || { echo "Not signed with Developer ID"; exit 1; }
grep -q "(runtime)" <<< "$details" || { echo "The hardened runtime isn't enabled"; exit 1; }
echo "Architectures: $(lipo -archs "${APP}/Contents/MacOS/Version Report")"
echo "Entitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | sed 's/^/    /'

echo "==> Building ${PKG}"
ROOT="${WORK}/root"
mkdir -p "$ROOT"
ditto --noextattr --noqtn "$APP" "${ROOT}/${APP_BUNDLE}"
codesign --verify --deep --strict "${ROOT}/${APP_BUNDLE}"
COMPONENTS="${WORK}/components.plist"
pkgbuild --analyze --root "$ROOT" "$COMPONENTS" >/dev/null
# Always install into /Applications, never over a copy that was moved elsewhere.
/usr/libexec/PlistBuddy -c "Delete :0:BundleIsRelocatable" "$COMPONENTS" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$COMPONENTS"
rm -f "$PKG"
pkgbuild --root "$ROOT" --component-plist "$COMPONENTS" --install-location /Applications \
    --identifier "$BUNDLE_ID" --version "$VERSION" --sign "$INSTALLER_IDENTITY" "$PKG"

# Keep the exported app beside the packages, as an Xcode export to dist/ would.
rm -rf "dist/${APP_BUNDLE}"
ditto "$APP" "dist/${APP_BUNDLE}"

if $SKIP_NOTARIZE; then
    echo "==> Skipping notarization: ${PKG} is signed but not notarized"
    exit 0
fi

echo "==> Notarizing (this usually takes a few minutes)"
xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PKG"

echo "==> Checking"
spctl -a -vv -t install "$PKG"

echo "==> Signing for Sparkle"
SIGN_UPDATE=$(ls -t ~/Library/Developer/Xcode/DerivedData/Version_Report-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1)
[[ -x "$SIGN_UPDATE" ]] || { echo "Couldn't find Sparkle's sign_update; build the project in Xcode once."; exit 1; }
SIGNATURE=$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$PKG")

PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y 00:00:00 +0000")
cat <<ITEM

Done: ${PKG}

Upload it to the v${VERSION} GitHub release (GitHub names it ${ASSET}), then
use this item in public/versionreport/appcast.xml:

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${RELEASES_URL}/v${VERSION}/${ASSET}"
        sparkle:version="${BUILD}"
        sparkle:shortVersionString="${VERSION}"
        ${SIGNATURE}
        type="application/octet-stream"
      />
    </item>
ITEM
