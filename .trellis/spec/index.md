# Relay — Coding Spec Index

Engineering conventions for **Relay**, a native macOS (Swift / SwiftUI / AppKit) global
app switcher with Profiles. These specs are auto-loaded into `trellis-implement` /
`trellis-check` via per-task jsonl manifests — keep them concrete and source-backed.

Product / business / security rules live in `AGENTS.md` (the authority). These specs
cover *how the code is written*.

## Layers

| Layer | Read before touching… | Files |
|-------|------------------------|-------|
| [`swift/`](swift/index.md) | Any Swift code — language mode, concurrency, testing, file layout | concurrency, quality |
| [`app/`](app/index.md) | Models, state, persistence, services (the non-UI core) | architecture, system-integration |
| [`ui/`](ui/index.md) | SwiftUI views, scenes, AppKit bridges | swiftui |
| [`guides/`](guides/index.md) | Cross-cutting thinking prompts (generic) | — |

## Project shape (orient quickly)

- One Xcode app target `Relay` (no packages / single-repo). Source under `Relay/Relay/`,
  organized by layer folders: `Models/ Persistence/ State/ Services/ UI/`.
- Uses **PBXFileSystemSynchronizedRootGroup** — new `.swift` files in those folders are
  compiled automatically; no `project.pbxproj` edits needed to add files.
- One SPM dependency: `KeyboardShortcuts` (global hotkeys). Tests in `Relay/RelayTests/`
  use Swift Testing.
- Targets macOS 26.5; un-sandboxed; menu-bar agent (`LSUIElement = YES`). See `Relay/notice.md`
  for the live architecture snapshot.
