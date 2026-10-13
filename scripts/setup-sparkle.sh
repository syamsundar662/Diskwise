#!/bin/bash
# One-time setup for Sparkle's command line tools (generate_keys, sign_update,
# generate_appcast). Downloads the latest Sparkle 2.x release tarball into
# .tools/sparkle (gitignored, not the Xcode dependency used by the app, which
# XcodeGen/SwiftPM fetch separately), then runs generate_keys once. The
# private EdDSA key is stored in the login keychain by generate_keys itself;
# this script never prints or copies it out. Only the public key is printed,
# for pasting into Resources/Info.plist (SUPublicEDKey).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="$repo_root/.tools/sparkle"

echo "Looking up the latest Sparkle 2.x release..."
release_json=$(curl -fsSL https://api.github.com/repos/sparkle-project/Sparkle/releases/latest)
tag=$(echo "$release_json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
asset_url=$(echo "$release_json" | grep -o '"browser_download_url": *"[^"]*Sparkle-[0-9][^"]*\.tar\.xz"' | sed 's/.*"\(https[^"]*\)"/\1/' | head -1)

if [[ -z "$tag" || -z "$asset_url" ]]; then
    echo "Could not find a Sparkle release tarball asset. Check https://github.com/sparkle-project/Sparkle/releases manually." >&2
    exit 1
fi
if [[ "$tag" != 2.* ]]; then
    echo "Latest release tag '$tag' is not a 2.x release; refusing to continue." >&2
    exit 1
fi

echo "Latest Sparkle release: $tag"
echo "Asset: $asset_url"

mkdir -p "$tools_dir"
archive="$tools_dir/Sparkle-$tag.tar.xz"
if [[ ! -f "$archive" ]]; then
    echo "Downloading $archive ..."
    curl -fL --progress-bar -o "$archive" "$asset_url"
else
    echo "Already downloaded: $archive"
fi

extract_dir="$tools_dir/Sparkle-$tag"
if [[ ! -d "$extract_dir" ]]; then
    mkdir -p "$extract_dir"
    echo "Extracting ..."
    tar -xf "$archive" -C "$extract_dir"
fi

bin_dir="$extract_dir/bin"
if [[ ! -x "$bin_dir/generate_keys" ]]; then
    echo "generate_keys not found at $bin_dir/generate_keys after extraction." >&2
    exit 1
fi

# Keep a stable "current" symlink so other scripts don't need to know the
# exact downloaded version.
ln -sfn "$extract_dir" "$tools_dir/current"

echo
echo "Running generate_keys (stores the private EdDSA key in the login keychain)..."
echo "If a key already exists, generate_keys will print the existing public key instead of making a new one."
echo

"$bin_dir/generate_keys"

echo
echo "Public key printed above. Paste it into Resources/Info.plist (SUPublicEDKey),"
echo "replacing any existing placeholder. The private key stays in the login keychain;"
echo "this script does not print or copy it anywhere else."
