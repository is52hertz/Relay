# Frontmost: Cycle Windows, then Hide (opt-in FrontmostAction)

## Goal

When the target app is already frontmost, let repeated hotkey presses cycle
through that app's windows one at a time; only after every window has been
shown does the next press hide the app. This extends the existing "two-step"
(front → hide) interaction into a "front → cycle windows → hide" flow, similar
to Thor/Witch window cycling. It is delivered as a **new opt-in
`FrontmostAction`**, so existing configs are unaffected.

## What I already know (from repo inspection)

- Frontmost behavior is chosen by `ActivationConfig.frontmost: FrontmostAction`
  (`Relay/Relay/Models/ActivationConfig.swift`). Current cases: `returnToPrevious`,
  `hide`, `quit`, `none`, `minimize`.
- Runtime state is computed in `AppActivationService.runtimeState(for:)`
  (`AppActivationService.swift:32-43`); `.frontmost` is detected by comparing
  `workspace.frontmostApplication?.bundleIdentifier` to the target.
- Pure decision mapping lives in `AppActivationDecision.action(for:config:)`
  (`AppActivationDecision.swift:39-64`) → emits an `Action` enum consumed by
  `AppActivationService.perform(...)`.
- **Accessibility is already wired** and is the *sole* AX entry point:
  `WindowMinimizer.swift` — `AXIsProcessTrusted()`, `AXUIElementCreateApplication`,
  `kAXWindowsAttribute` (already enumerates windows in `hasVisibleWindow`),
  `kAXMinimizedAttribute`, `kAXFocusedWindowAttribute`/`kAXMainWindowAttribute`.
  Permission is requested **lazily** (only when the user picks "Minimize" in the
  editor), never at launch (`AppController.swift:58-59`).
- `FrontmostTracker.swift` listens to `NSWorkspace.didActivateApplicationNotification`
  — a natural hook for resetting per-app cycle state when the app loses front.
- No window/tab *cycling* exists today; AX actions only ever touch the
  focused/main window.

## Confirmed decisions (from brainstorm)

- **"Tab" = app windows.** Cycle the target app's windows via public
  Accessibility APIs (`kAXWindowsAttribute` + `kAXRaiseAction`). True in-app
  tabs (browser/terminal tabs) are explicitly **out of scope** — no reliable
  public API. [user]
- **Opt-in.** Add a new `FrontmostAction` case (working name
  `cycleWindowsThenHide`); do not change existing `hide`. [user]
- **Minimized windows: unminimize, then raise.** A minimized window is part of
  the cycle; when its turn comes, unminimize it and raise it. [user]
- **Q1 — all AX windows.** Cycle every window returned by `kAXWindowsAttribute`;
  do **not** filter by subrole. Panels/inspectors/sheets are included. [user]
  (Tradeoff noted: may raise non-main windows; narrowing to `AXStandardWindow`
  later is a one-line change.)
- **Q2 — cursor reset.** Reset per-app cycle state when the target loses
  frontmost (`didActivateApplicationNotification` to another app), and
  re-snapshot when the window set changes mid-cycle. [self, default accepted]
- **Q3 — first frontmost press.** While already frontmost, the first press
  advances to the window *after* the currently focused one (not a re-focus of
  the current), so the first press visibly does something. [self, default accepted]
- **Q4 — degradation copy.** Reuse the existing minimize permission notice; no
  dedicated message. [self, default accepted]

## Requirements (evolving)

- R1. New `FrontmostAction.cycleWindowsThenHide` case (Codable, CaseIterable),
  selectable in the Config editor with localized labels (en / zh-Hans / zh-Hant).
- R2. When state is `.frontmost` and this action is selected:
  - if there is another window not yet shown this cycle → raise the next window
    (unminimizing it first if needed);
  - if all windows have been shown this cycle → perform `hide`.
- R3. Per-app cycle state (ordered window snapshot + cursor) held in memory only
  (not persisted), reset when the app loses frontmost status.
- R4. Stable cycle order: snapshot window order at cycle start; do not re-derive
  from live z-order each press (raising mutates z-order and would cause two
  windows to ping-pong).
- R5. Safe degradation when Accessibility is not granted: fall back to plain
  `hide`, surface the existing one-time permission notice. Never silently do
  nothing destructive-wrong.
- R6. Single-window apps behave like plain `hide` immediately (nothing to cycle).

## Open Questions

- (none — Q1–Q4 resolved above.)

## Acceptance Criteria (evolving)

- [ ] New action appears in the Config editor with correct 3-language labels.
- [ ] With ≥2 windows, repeated presses raise each window once in a stable order,
      then hide on the press after the last.
- [ ] A minimized window in the cycle is unminimized + raised on its turn.
- [ ] Single-window app hides immediately on frontmost press (no extra press).
- [ ] Cycle restarts from the beginning after switching away and back.
- [ ] Without Accessibility permission, action degrades to plain hide + one-time
      notice; app stays functional.
- [ ] No private APIs; no CGEventTap / global NSEvent monitors; data models stay
      AppKit/SwiftUI-free.

## Definition of Done

- Build + type-check green for the Relay target.
- New strings localized in `Localizable.xcstrings` (en, zh-Hans, zh-Hant).
- Manual test across multi-window / minimized / single-window / no-permission.
- `notice.md` updated if a durable contract emerges (e.g. cycle-state ownership).

## Out of Scope

- Switching true in-app tabs (browser/terminal/document tabs).
- Cross-app window cycling, window arrangement, or Spaces/Mission Control control.
- Persisting cycle state across launches.
- Changing any existing FrontmostAction behavior.

## Technical Notes

- Reuse `WindowMinimizer` as the AX home; add window-enumeration (ordered) +
  raise-next capability there, keep AppActivationService as orchestrator.
- `AppActivationDecision` stays pure: it can emit a new `Action`
  (e.g. `.cycleWindowsOrHide`) and let `AppActivationService` resolve the cursor,
  OR the cursor logic lives entirely in the service while the decision just
  routes `.frontmost + cycleWindowsThenHide` there. To settle during design.
- Window order stability: snapshot `kAXWindowsAttribute` order (z-order at cycle
  start) keyed by a stable per-window identity for the cursor.
- Permission model mirrors existing minimize: lazy request, safe fallback.
