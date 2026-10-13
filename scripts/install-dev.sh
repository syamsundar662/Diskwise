#!/bin/bash
# Build a Release copy of Diskwise with a local Apple Development identity,
# sign it (Sparkle's nested parts first, per Sparkle's sandboxing docs, then
# the app), and install it to ~/Applications for day to day use. Not for
# distribution: see scripts/release.sh for that.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

derived_data="$repo_root/build"
app_name="Diskwise.app"
built_app="$derived_data/Build/Products/Release/$app_name"
dest_dir="$HOME/Applications"
dest_app="$dest_dir/$app_name"

identity_name="Apple Development: syamsundar662@gmail.com (L7G4AMNW89)"

# `codesign` can hang waiting on the Security Server; macOS has no `timeout`,
# so bound every call with perl's alarm instead.
run_with_timeout() {
    perl -e 'alarm 60; exec @ARGV' -- "$@"
}

sign() {
    # sign <path> [extra codesign args...]
    local path="$1"
    shift
    echo "Signing: $path"
    run_with_timeout codesign --force --options runtime --timestamp=none --sign "$signing_identity" "$@" "$path"
}

echo "== 1. Generating Diskwise.xcodeproj =="
/opt/homebrew/bin/xcodegen generate

echo
echo "== 2. Building Release (unsigned) =="
xcodebuild -project Diskwise.xcodeproj -scheme Diskwise -configuration Release \
    -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build

if [[ ! -d "$built_app" ]]; then
    echo "Build did not produce $built_app" >&2
    exit 1
fi

echo
echo "== 3. Signing =="
if security find-identity -v -p codesigning | grep -qF "$identity_name"; then
    signing_identity="$identity_name"
else
    echo "Identity '$identity_name' not found in the keychain; falling back to ad hoc signing (-)."
    echo "Features that need a real identity (e.g. keychain access across relaunches) may behave differently."
    signing_identity="-"
fi
echo "Using signing identity: $signing_identity"

sparkle_framework="$built_app/Contents/Frameworks/Sparkle.framework"
sparkle_current="$sparkle_framework/Versions/Current"

if [[ -d "$sparkle_framework" ]]; then
    # Order matters: sign nested components before the things that embed
    # them, and the app itself last. See
    # https://sparkle-project.org/documentation/sandboxing/
    sign "$sparkle_current/XPCServices/Installer.xpc"
    sign "$sparkle_current/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
    sign "$sparkle_current/Autoupdate"
    sign "$sparkle_current/Updater.app"
    sign "$sparkle_framework"
else
    echo "Note: Sparkle.framework not found in the built app; skipping its signing steps."
fi

sign "$built_app" --entitlements "$repo_root/Resources/Diskwise.entitlements"

echo
echo "Verifying signature..."
run_with_timeout codesign --verify --deep --strict --verbose=2 "$built_app"

echo
echo "== 4. Installing to $dest_app =="
mkdir -p "$dest_dir"

echo "Quitting any running Diskwise..."
osascript -e 'tell application id "com.syam.Diskwise" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x Diskwise >/dev/null 2>&1 || true
sleep 0.5

# Only ever touch our own app bundle here; StorageBar (if installed) is a
# separate app and this script must not go near it.
if [[ -d "$dest_app" ]]; then
    rm -rf "$dest_app"
fi
ditto "$built_app" "$dest_app"

echo
echo "== 5. Launching =="
open "$dest_app"

echo
echo "Installed and launched: $dest_app"
