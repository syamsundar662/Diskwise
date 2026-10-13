# Diskwise

Diskwise is a macOS app that shows where your disk space went and helps you
free it up safely. It has a window (dashboard, smart cleanup, an interactive
disk space sunburst, large and old files, project junk cleanup, an
uninstaller) and a menu bar item with a quick summary panel. It grew out of
StorageBar, a smaller menu bar only tool.

Diskwise is not sandboxed: cleaning up other apps' caches and leftovers needs
access outside its own container. It asks Finder's permission (via Apple
Events) only to empty the Trash and to move apps that need your password to
the Trash; every other removal goes through its own SafeDelete gate. It does
not collect or send any data, and there is no account, license or payment in
1.0.

## Requirements

- macOS 14 or later to run Diskwise.
- Xcode 26 and Swift 6 to build it.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
  to build and install the signed app; not needed for plain `swift build`.

## Repository layout

- `Package.swift`: the SwiftPM package used for day to day development and
  tests. It builds `DiskwiseCore` (scanning, cleanup catalog, SafeDelete, apps,
  history; pure Foundation, no AppKit/Sparkle) and a `DiskwiseDev` executable
  from `Sources/Diskwise` for `swift build`/`swift run`. It does not depend on
  Sparkle.
- `Sources/DiskwiseCore`: the engine, with its tests in
  `Tests/DiskwiseCoreTests`.
- `Sources/Diskwise`: the app (AppKit + SwiftUI). `main.swift` is the entry
  point (there is no `@main` type).
- `project.yml`: the [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec for
  the shipping app. Generates `Diskwise.xcodeproj` (not committed) from the
  same `Sources/Diskwise` files plus the local `DiskwiseCore` package and
  Sparkle 2, with hardened runtime on.
- `Resources/`: `Info.plist` and `Diskwise.entitlements` (both generated into
  this folder by `xcodegen generate`, with their real content defined in
  `project.yml`), plus `Assets.xcassets/AppIcon.appiconset` and a 1024x1024
  `AppIcon-1024.png` for docs.
- `scripts/make-icon.swift`: draws the app icon (a navy Big Sur style squircle
  with a cyan to green progress ring) and writes the whole icon set.
- `scripts/setup-sparkle.sh`: one time setup for Sparkle's `generate_keys`,
  `sign_update` and `generate_appcast` command line tools.
- `scripts/install-dev.sh`: builds, signs with a local Apple Development
  identity, and installs to `~/Applications` for everyday use.
- `scripts/release.sh`: builds, signs with a Developer ID, notarizes, staples,
  packages a DMG, and produces a Sparkle appcast, for an actual release.

## Developing

```
swift build
swift test
```

`Sources/Diskwise` also supports a snapshot mode for checking the UI without
opening a window: it renders every page off screen to PNG files and exits.

```
DISKWISE_SNAPSHOT=/tmp/dw swift run DiskwiseDev
```

writes a PNG per page/state (`/tmp/dw-<name>.png`) and exits. It's read only:
it never removes anything or saves state.

## Installing a local build

```
scripts/install-dev.sh
```

This runs `xcodegen generate`, builds Release unsigned
(`CODE_SIGNING_ALLOWED=NO`), then signs Sparkle's nested parts and the app
itself with hardened runtime using your local Apple Development identity
(falling back to ad hoc signing if you don't have one), quits any running
Diskwise, installs the result to `~/Applications/Diskwise.app`, and opens it.

## Releasing

```
scripts/release.sh
```

This archives, signs with a Developer ID Application identity, notarizes with
`notarytool`, staples the ticket, builds and signs a DMG (the app plus an
Applications symlink, volume name "Diskwise"), and writes a Sparkle appcast to
`dist/appcast.xml`. It never uploads or publishes anything: it prints the
manual steps (create a GitHub release, upload the DMG and the appcast) at the
end.

One time setup before the first release:

1. A **Developer ID Application** certificate in your keychain. Create one
   under Certificates, Identifiers & Profiles in your Apple Developer account,
   download it, and double click to add it to your login keychain.
2. A **notarytool keychain profile** named `diskwise-notary`, using an
   app-specific password from <https://appleid.apple.com> (Sign-In and
   Security, App-Specific Passwords):
   ```
   xcrun notarytool store-credentials diskwise-notary \
     --apple-id you@example.com --team-id YOURTEAMID --password xxxx-xxxx-xxxx-xxxx
   ```
3. **Sparkle's signing keys**, once:
   ```
   scripts/setup-sparkle.sh
   ```
   This downloads Sparkle's command line tools, generates an EdDSA key pair
   (the private key is stored in your login keychain and is never printed or
   committed), and prints the public key. It should already be in
   `Resources/Info.plist` (`SUPublicEDKey`, by way of `project.yml`); if you
   ever regenerate the key, update it there too.
4. A **GitHub releases feed**. Diskwise checks
   `https://github.com/syamsundar662/Diskwise/releases/latest/download/appcast.xml`
   for updates (`SUFeedURL`), so each release needs a GitHub release tagged
   `vX.Y.Z` with the DMG and `appcast.xml` uploaded as assets.
