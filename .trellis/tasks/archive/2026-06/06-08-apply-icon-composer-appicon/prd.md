# PRD — Apply Icon Composer App Icon

## Goal
Wire the user-authored Icon Composer icon (`Icon.icon`, root of repo) in as Relay's app icon, replacing the empty placeholder `AppIcon.appiconset`.

## Context
- `Relay/Relay.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` for the `Relay/` source folder — files placed under `Relay/Relay/` gain target membership automatically; no manual `project.pbxproj` file-reference edits are needed.
- Build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (Debug + Release of the `Relay` target) currently points at an empty `AppIcon.appiconset`.
- `Icon.icon` is the new macOS 26 Icon Composer format (`icon.json` + `Assets/*.svg`); Xcode 26 compiles it via `actool` when it is a target resource and the appicon name matches its base filename.

## Approach (clearly optimal, low-risk)
1. Move `Icon.icon` → `Relay/Relay/Icon.icon` so the synchronized folder gives it target membership.
2. Set `ASSETCATALOG_COMPILER_APPICON_NAME = Icon` in both Debug and Release configs of the `Relay` target.
3. Delete the now-unused empty `Relay/Relay/Assets.xcassets/AppIcon.appiconset` placeholder.

## Out of scope
- No icon artwork changes; no other build-setting or code changes.

## Verification
- `xcodebuild build` for the `Relay` scheme succeeds and `actool` compiles `Icon.icon` (no missing-appicon warning).
