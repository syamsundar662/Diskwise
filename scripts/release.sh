#!/bin/bash
# Build, sign, notarize, staple and package a release build of Diskwise, and
# produce a Sparkle appcast for it. This script never uploads or publishes
# anything: it only writes local files under dist/ and prints the manual
# steps left to do (create a GitHub release, upload assets).
#
# One time setup needed before this script can run to completion:
#   1. A "Developer ID Application" certificate in your keychain (from your
#      Apple Developer account, Certificates, Identifiers & Profiles).
#   2. A notarytool keychain profile named "diskwise-notary":
#        xcrun notarytool store-credentials diskwise-notary \
#          --apple-id you@example.com --team-id TEAMID --password app-specific-password
#   3. Sparkle's signing keys, via scripts/setup-sparkle.sh (once).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
if [[ -z "$version" ]]; then
    echo "Could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

app_name="Diskwise.app"
archive_path="$repo_root/build/Diskwise.xcarchive"
dist_dir="$repo_root/dist"
staging_dir="$dist_dir/staging"
sparkle_bin="$repo_root/.tools/sparkle/current/bin"
notary_profile="diskwise-notary"
dmg_volname="Diskwise"
dmg_path="$dist_dir/Diskwise-$version.dmg"
zip_path="$dist_dir/Diskwise-$version.zip"
appcast_path="$dist_dir/appcast.xml"

run_with_timeout() {
    # codesign/notarytool can hang on network/Security Server issues; macOS
    # has no `timeout`, so bound every call with perl's alarm instead.
    # Usage: run_with_timeout <seconds> <command> [args...]
    local seconds="$1"
    shift
    perl -e 'alarm($ARGV[0]); shift @ARGV; exec @ARGV' "$seconds" "$@"
}

echo "== Preflight checks =="
preflight_failed=0

developer_id=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)
if [[ -z "$developer_id" ]]; then
    echo
    echo "No 'Developer ID Application' signing identity is installed on this Mac."
    echo "Create one at https://developer.apple.com/account/resources/certificates/list"
    echo "(Certificates > + > Developer ID Application), download it, and double click"
    echo "to add it to your login keychain. Then re-run this script."
    preflight_failed=1
else
    echo "Found signing identity: $developer_id"
fi

if ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    echo
    echo "No notarytool keychain profile named '$notary_profile' was found."
    echo "Create one once with an app specific password (https://appleid.apple.com,"
    echo "Sign-In and Security > App-Specific Passwords):"
    echo "  xcrun notarytool store-credentials $notary_profile \\"
    echo "    --apple-id you@example.com --team-id YOURTEAMID --password xxxx-xxxx-xxxx-xxxx"
    preflight_failed=1
else
    echo "Found notarytool keychain profile: $notary_profile"
fi

if [[ ! -x "$sparkle_bin/sign_update" || ! -x "$sparkle_bin/generate_appcast" ]]; then
    echo
    echo "Sparkle's command line tools are not set up yet. Run this once:"
    echo "  scripts/setup-sparkle.sh"
    preflight_failed=1
else
    echo "Found Sparkle tools at $sparkle_bin"
fi

if [[ "$preflight_failed" -ne 0 ]]; then
    echo
    echo "Fix the above and re-run scripts/release.sh. Nothing was built or signed."
    exit 1
fi

echo
echo "== 1. Generating Diskwise.xcodeproj =="
/opt/homebrew/bin/xcodegen generate

echo
echo "== 2. Archiving (unsigned) =="
rm -rf "$archive_path"
# Xcode 27 needs the destination spelled out (see install-dev.sh).
xcodebuild -project Diskwise.xcodeproj -scheme Diskwise -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" CODE_SIGNING_ALLOWED=NO archive

archived_app="$archive_path/Products/Applications/$app_name"
if [[ ! -d "$archived_app" ]]; then
    echo "Archive did not produce $archived_app" >&2
    exit 1
fi

echo
echo "== 3. Signing with Developer ID =="
sign() {
    local path="$1"
    shift
    echo "Signing: $path"
    run_with_timeout 90 codesign --force --options runtime --timestamp --sign "$developer_id" "$@" "$path"
}

sparkle_framework="$archived_app/Contents/Frameworks/Sparkle.framework"
sparkle_current="$sparkle_framework/Versions/Current"
if [[ -d "$sparkle_framework" ]]; then
    sign "$sparkle_current/XPCServices/Installer.xpc"
    sign "$sparkle_current/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
    sign "$sparkle_current/Autoupdate"
    sign "$sparkle_current/Updater.app"
    sign "$sparkle_framework"
fi
sign "$archived_app" --entitlements "$repo_root/Resources/Diskwise.entitlements"

echo
echo "Verifying signature..."
run_with_timeout 60 codesign --verify --deep --strict --verbose=2 "$archived_app"
run_with_timeout 60 spctl --assess --type execute --verbose "$archived_app" || \
    echo "spctl assessment will pass once the build below is notarized and stapled."

echo
echo "== 4. Notarizing =="
rm -rf "$dist_dir"
mkdir -p "$dist_dir"
rm -f "$zip_path"
ditto -c -k --keepParent "$archived_app" "$zip_path"

run_with_timeout 1800 xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait

echo
echo "== 5. Stapling =="
run_with_timeout 120 xcrun stapler staple "$archived_app"
run_with_timeout 60 spctl --assess --type execute --verbose "$archived_app"

echo
echo "== 6. Building the DMG =="
rm -rf "$staging_dir"
mkdir -p "$staging_dir"
ditto "$archived_app" "$staging_dir/$app_name"
ln -s /Applications "$staging_dir/Applications"

background_png="$staging_dir/.background.png"
if swift "$repo_root/scripts/make-dmg-background.swift" "$background_png" >/dev/null 2>&1; then
    have_background=1
else
    echo "Could not draw a DMG background; continuing with a plain DMG."
    have_background=0
fi

rm -f "$dmg_path"
hdiutil create -volname "$dmg_volname" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path"

if [[ "$have_background" -eq 1 ]]; then
    echo "Laying out the DMG window in Finder (needs Automation permission for your terminal)..."
    mount_point=$(hdiutil attach "$dmg_path" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | head -1)
    if [[ -n "$mount_point" ]]; then
        osascript <<OSA || echo "Finder layout step failed; the DMG still works, just without custom icon positions."
tell application "Finder"
    tell disk "$dmg_volname"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 120, 1060, 520}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to file ".background.png"
        set position of item "$app_name" of container window to {150, 190}
        set position of item "Applications" of container window to {500, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
        hdiutil detach "$mount_point" -quiet || true
        rm -f "$dmg_path"
        hdiutil create -volname "$dmg_volname" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path"
    fi
fi

echo "Signing the DMG..."
run_with_timeout 90 codesign --force --sign "$developer_id" "$dmg_path"
run_with_timeout 1800 xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
run_with_timeout 120 xcrun stapler staple "$dmg_path"

echo
echo "== 7. Sparkle appcast =="
update_zip="$dist_dir/updates/Diskwise-$version.zip"
mkdir -p "$dist_dir/updates"
ditto -c -k --keepParent "$archived_app" "$update_zip"

echo "Signature for this update (for reference; generate_appcast signs it too):"
"$sparkle_bin/sign_update" "$update_zip"

"$sparkle_bin/generate_appcast" "$dist_dir/updates" \
    --download-url-prefix "https://github.com/syamsundar662/Diskwise/releases/latest/download/" \
    -o "$appcast_path"

echo
echo "== Done. Nothing was uploaded or published. =="
echo
echo "Built:"
echo "  $dmg_path"
echo "  $appcast_path"
echo
echo "Next manual steps:"
echo "  1. Create a GitHub release at https://github.com/syamsundar662/Diskwise/releases/new"
echo "     tagged v$version."
echo "  2. Upload these as release assets:"
echo "       $dmg_path"
echo "       $appcast_path"
echo "  3. Make sure the release is published at a URL ending in /releases/latest,"
echo "     since SUFeedURL points at .../releases/latest/download/appcast.xml."
echo "  4. Sanity check the appcast's enclosure URL matches the asset you uploaded."
