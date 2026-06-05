# Code Quality, Layout & Verification

## File organization

- One primary type per file. Group by layer folder under `Relay/Relay/`:
  `Models/ Persistence/ State/ Services/ UI/`.
- The target uses a file-system-synchronized group: **drop a new `.swift` file into the right
  folder and it compiles** — never hand-edit `project.pbxproj` to register source files. (The
  one exception was adding the SPM package; see app/system-integration.md.)
- Each file starts with the standard header comment block, then a one-line purpose in Chinese.

## Naming

- Use domain names: `Profile`, `HotkeyBinding`, `FocusBehavior`, `TargetApp`.
- Avoid colliding with framework types — the binding model is `HotkeyBinding`, **not** `Binding`
  (that's `SwiftUI.Binding`).
- Services end in their role: `…Service`, `…Resolver`, `…Tracker`, `…Controller`.

## Comments & language

- Inline comments are written in Chinese in this codebase; match the surrounding density.
  Comment the *why* (especially non-obvious AppKit/concurrency decisions), not the obvious.
- User-facing UI strings are English.

## Testing (Swift Testing)

- Use `import Testing` + `@Test` / `#expect` (not XCTest). Tests live in `Relay/RelayTests/`
  (also a synchronized group).
- **Make logic testable by extracting pure, `nonisolated` functions** from side-effecting code,
  then test those without AppKit:
  - `AppActivationDecision.action(for:behavior:)` — the full state×behavior matrix
    (`AppActivationDecisionTests`, 16 cases).
  - `HotkeyConflicts.duplicateBindingIDs(in:)` (`HotkeyConflictsTests`).
- For `@MainActor` types, mark the test `@MainActor` (see `PersistenceStore` round-trip test).
- UI and AppKit-integration code is verified by build + manual run, not unit tests.

## Verify before commit (required — see AGENTS.md)

```bash
cd Relay
xcodebuild -scheme Relay -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild test  -scheme Relay -only-testing:RelayTests -destination 'platform=macOS'
```

SourceKit may show transient "Cannot find type X in scope" across files until indexed —
`xcodebuild` is the source of truth, not the live diagnostics.

## Dependencies & git hygiene

- Do not add dependencies without stating benefit/risk and getting confirmation (AGENTS.md).
  The only runtime dependency is `KeyboardShortcuts` (SPM).
- Xcode per-user state (`*.xcuserstate`, `xcuserdata/`) and `*.profraw` are gitignored; keep
  `Package.resolved` committed.
