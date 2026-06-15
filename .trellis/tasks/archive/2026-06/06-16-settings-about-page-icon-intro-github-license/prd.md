# Settings: About Page

## Goal

Add a standard **About** pane to Settings showing the app icon, name + version,
a short intro, a GitHub link, the license (GPL-3.0), and third-party
acknowledgements — the usual contents of an About screen.

## What I already know (from repo inspection)

- Settings is `SettingsRootView` (System-Settings-style `NavigationSplitView`)
  with `Pane` enum `.general` / `.personalization` / `.data` (title +
  `systemImage` icon + a detail `switch`). Adding `.about` = enum case +
  title/icon + detail case → new `AboutSettingsView`.
- **GitHub**: `https://github.com/is52hertz/Relay` (git `origin`).
- **Version**: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` →
  read at runtime from the bundle (`CFBundleShortVersionString` /
  `CFBundleVersion`), not hardcoded.
- **License**: `./LICENSE` is **GNU GPL v3**.
- **Third-party**: `KeyboardShortcuts` (sindresorhus, MIT) — acknowledge it.
- **App icon**: there is **no `AppIcon` asset** in `Assets.xcassets` yet (only
  `AccentColor`). `NSApp.applicationIconImage` therefore shows the system
  default icon. Shipping a custom app icon is a **separate task** — out of scope
  here; this pane just displays whatever the current app icon is.

## Requirements

- R1. New `SettingsRootView.Pane.about` (title "About", icon `info.circle`) →
  new `AboutSettingsView`.
- R2. **Header**: app icon (`NSApp.applicationIconImage`), app name "Relay",
  and version read from the bundle, formatted e.g. "Version 1.0 (1)".
- R3. **Intro**: a one/two-line description of Relay (localized). Draft (edit
  welcome): *"A native macOS switcher for launching, focusing, and hiding apps
  with global hotkeys — organized into scene-based Profiles."*
- R4. **GitHub link**: a labeled `Link` ("View on GitHub" / "GitHub") opening
  `https://github.com/is52hertz/Relay` in the browser.
- R5. **License**: show "GPL-3.0" with a link to the license
  (`https://github.com/is52hertz/Relay/blob/main/LICENSE`).
- R6. **Acknowledgements**: list third-party deps — KeyboardShortcuts (MIT) with
  a link to its repo.
- R7. **Copyright**: a "© 2026 Teethe" line. [user]
- R8. All new user-facing strings localized en / zh-Hans / zh-Hant (version
  numbers, "GPL-3.0", and URLs are not translated).

## Decisions (resolved)

- Q1 intro: **use the R3 draft**. [user]
- Q2 license: **"GPL-3.0" label + link to the GitHub LICENSE** (no in-app
  full-text sheet). [user]
- Q3 copyright holder: **Teethe** → "© 2026 Teethe". [user]
- Q4 app icon: **display the current/default app icon** via
  `NSApp.applicationIconImage` for now (custom AppIcon is a separate task). [user]

## Acceptance Criteria

- [ ] New "About" pane appears in Settings sidebar with the `info.circle` icon.
- [ ] Header shows the app icon, "Relay", and the bundle version (not hardcoded).
- [ ] GitHub link opens the repo; license link opens the GPL-3.0 LICENSE.
- [ ] KeyboardShortcuts (MIT) is acknowledged with a working link.
- [ ] Intro + labels localized in en / zh-Hans / zh-Hant.
- [ ] Keyboard + VoiceOver reachable; HIG spacing; light/dark correct.
- [ ] No private APIs; no network calls (links open in the browser only).

## Definition of Done

- Build + type-check green.
- New strings in `Localizable.xcstrings` (3 languages).
- Manual check: pane renders, links open, version correct.

## Out of Scope

- Designing/shipping a custom app icon (`AppIcon` asset) — separate task.
- Wiring the standard app-menu "About Relay" item to this pane (could be a
  follow-up).
- An in-app changelog / update checker / acknowledgements auto-generation.

## Technical Notes

- `AboutSettingsView` is SwiftUI; reading the bundle version + app icon uses
  Foundation/AppKit at the view layer (fine — it's UI). No model changes, no
  persistence — this pane is static/read-only.
- Use `Link` / `SettingsLink`-style rows; open URLs via SwiftUI `Link` or
  `NSWorkspace.open`. License/GitHub are plain https links (no bundled web view).
- Match the existing panes' `Form`/`.formStyle(.grouped)` conventions.
