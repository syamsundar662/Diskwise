# Diskwise 1.0 plan

Diskwise is a production macOS app (window + menu bar item) that shows disk usage and frees space safely.
It grew out of ~/StorageBar (menu bar only). Approved by Syam on 2026-10-13. No em or en dashes anywhere (code, comments, UI text, docs).

## Decisions
- Window layout: "Focus" (icon rail on the left, big centered disk ring, one Clean button, summary chips). See Sources/Diskwise/Window/WindowDesigns.swift `FocusDesign` for the approved mockup.
- Style: "Midnight" palette (Theme.swift): dark navy glass, bright blue accent, white text.
- Menu bar panel stays (existing PanelView pages), with an "Open Diskwise" button.
- Distributed outside the App Store: Developer ID signing, hardened runtime, notarization, DMG, Sparkle 2 auto updates. Not sandboxed (cleanup needs access to other apps' caches).
- No licensing or payments in 1.0. English only.
- macOS 14+ (uses numericText content transitions, SMAppService).

## Layout of the repo
- Package.swift: SwiftPM for development and tests (DiskwiseCore library, Diskwise executable, DiskwiseCoreTests). No Sparkle here.
- Sources/DiskwiseCore: scanning, cleanup catalog, SafeDelete (the only removal gate), apps, history. Pure Foundation.
- Sources/Diskwise: the app (AppKit + SwiftUI). Window/ holds window pages, Onboarding/, Settings/.
- project.yml: XcodeGen spec for the shipping app (Diskwise.xcodeproj is generated, not committed). Uses the same Sources/Diskwise files plus the local DiskwiseCore package and Sparkle.
- Resources/: Info.plist, Diskwise.entitlements, Assets.xcassets (AppIcon).
- scripts/: make-icon (draws the app icon in code), install-dev.sh (build, sign with Apple Development, install to ~/Applications, launch), release.sh (archive, Developer ID sign, notarize, staple, DMG, Sparkle signature + appcast).

## Window features (1.0)
Dashboard (Focus), Smart Cleanup, Space Lens (interactive sunburst: hover, click to zoom, breadcrumb), Large & Old Files, Project Junk, Uninstaller, Settings window (General: launch at login via SMAppService, show menu bar item; Cleanup: folders to never touch; Notifications: low space threshold; Updates: automatic checks; About), first-launch onboarding (welcome, Full Disk Access with live detection, notifications), main menu with shortcuts (Cmd+R rescan, Cmd+1..6 pages, Cmd+, settings).

## Animations
Scan sweep on the ring with counting numbers, page transitions, rail selection that glides, sunburst zoom, rows folding away when removed, cleaning progress ring counting freed GB then a success state, card hover lift. Subtle, never flashy.
