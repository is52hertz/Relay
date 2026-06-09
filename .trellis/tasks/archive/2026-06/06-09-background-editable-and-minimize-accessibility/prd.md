# Background-editable + Minimize (Accessibility, lazy permission)

## Goal
Turn the placeholder actions shipped in the previous task into real behavior: make the **后台 (Background)** column functional, implement **最小化 (Minimize)** via Accessibility with **lazy permission**, and implement **显示不聚焦 (Show Without Focus)**. Relax the AGENTS.md "no Accessibility" boundary narrowly for window minimize.

## Starting point (from the prior task, already shipped on `main`)
- `ActivationConfig { notRunning, background, frontmost }` (one action per state). Enums:
  - `NotRunningAction`: launch / launchWithoutFocus / none — **done**.
  - `BackgroundAction`: focus / showWithoutFocus / minimize — **placeholder**: column disabled, engine always does `.focus` (`isImplemented == (self == .focus)`).
  - `FrontmostAction`: returnToPrevious / hide / quit / none / minimize — done except **minimize is placeholder** (`isImplemented == (self != .minimize)`).
- `AppActivationDecision.action(for:config:)` pure; `Action` already reserves `minimize` / `showWithoutFocus`. `AppActivationService` already does launch/launchWithoutFocus/focus/hide/quit/returnToPrevious via public AppKit; `running` always → `.focus`.
- `NSRunningApplication.isHidden` (public) distinguishes a hidden bg app from a visible-but-behind one.

## Scope (this task)
1. **Background column editable** — remove the `.disabled` placeholder; engine honors all 3 actions; `BackgroundAction.isImplemented` → all true.
2. **showWithoutFocus** — execution: unhide hidden instances, do NOT activate (public API: `NSRunningApplication.unhide()`); for a visible-bg app it's a no-op.
3. **minimize** — new execution via Accessibility (`AXUIElementCreateApplication(pid)` → set `kAXMinimizedAttribute = true` on the target window). Available on Background **and** Frontmost; `FrontmostAction`/`BackgroundAction` minimize → implemented.
4. **Lazy Accessibility permission** — never prompt at launch. Check `AXIsProcessTrusted()`; prompt via `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` only when the user selects Minimize in the editor (or first triggers it). App stays fully functional without it; only minimize is gated. Caveat (document): granted permission is App-level full AX, not scoped to minimize.
5. **Graceful degradation** — if a config says minimize but AX is not trusted at trigger time: do nothing destructive; surface a one-time notice (never silently wrong behavior).
6. **AGENTS.md** — relax the security boundary to a GENERAL principle (not minimize-only): **functionality takes priority over avoiding permissions; permission-gated capabilities (e.g. Accessibility) are allowed when they're the way to implement a feature, provided the permission is requested lazily / on demand — never at launch.** Keep intact the real boundary: no private APIs, no arbitrary/downloaded code execution, no control surface beyond the local machine. Hotkeys still go through `KeyboardShortcuts` (no CGEventTap/global monitors needed).

## Decisions (confirmed)
- **D1 [user] — AGENTS.md relaxation is general.** Prioritize feature implementation over permission-avoidance; the only hard requirement is lazy/deferred permission request (not at startup). Not scoped to minimize. Real security boundaries (no private APIs, no remote control surface, no arbitrary code) stay.
7. Decision layer stays pure; extend Swift Testing for the newly-live actions. Update `Relay/notice.md`.

## Design decisions (confirmed — "all recommended")
- **D2 — Background granularity: keep ONE `background` action** + smart execution via `isHidden` (focus = unhide+activate; showWithoutFocus = unhide-no-activate; minimize). No config-level 已隐藏/未隐藏 split; table stays 4 columns. (Supersedes the prior task's notice note about splitting.)
- **D3 — Minimize target: the app's focused/main window only** (`kAXFocusedWindowAttribute`, fallback `kAXMainWindowAttribute`). Not all windows.
- **D4 — Degradation when AX ungranted at trigger: do nothing + a one-time notice.** Never degrade to a different destructive action.
- **D5 — Permission prompt timing: when the user selects "Minimize" in the editor** (with an explainer), not silently at first trigger.

## Behavior refinements (from manual test — confirmed)
- **D6 — `showWithoutFocus` semantics = "raise then return focus" (option b).** Corrected: NOT just unhide-in-place. Execution: (1) capture the current frontmost app (`NSWorkspace.frontmostApplication` — at key-down it's the user's app, since Relay is a background agent); (2) bring the target to front via `openApplication(activates:true)` (also unhides) — this raises its window AND focuses it; (3) re-activate the captured frontmost app so focus returns to it. Public API only, no AX. Accepted caveats (document): the re-activated app's windows return on top, so where they overlap the target is covered; non-overlapping layouts leave the target visible; a brief flicker is expected. If no captured frontmost / it equals the target, just leave the target focused.
- **D7 — `focus` restores minimized windows (opportunistic AX, NO prompt).** Bug: when the target's window(s) are minimized to the Dock, `focus` (openApplication) activates the app but shows no window. Fix: during `focus`, if `WindowMinimizer.isTrusted` AND the target has a minimized focused/main window, un-minimize it via AX (`kAXMinimizedAttribute = false`). **`focus` must NOT prompt** for Accessibility (only explicit Minimize selection prompts, D5) — if untrusted, silently keep the current `openApplication` behavior (no notice). So focus un-minimizes only when permission already happens to be granted.

- **D8 — Runtime-state: "frontmost" requires a VISIBLE window ("后台 = 用户看不到, 无可见窗口").** Reclassify in `AppActivationService.runtimeState`: when the target IS the active app, additionally check (AX, trusted only) whether it has any non-minimized window — enumerate `kAXWindowsAttribute`, look for one with `kAXMinimizedAttribute == false`. If a visible window exists → `.frontmost`; if none (all minimized, or zero windows) → `.running` (background). Non-active apps stay `.running` as before. Effect: an active app whose windows are all minimized runs the **background** action (default `focus` → D7 restores the window), unifying the "minimized + not switched" and "minimized + switched" cases. This REPLACES the earlier A1 "frontmost override" idea — it's a state reclassification (A2), so the pure `AppActivationDecision` is unchanged and there is no Do-Nothing-override question.
  - Untrusted / AX read fails → keep the current activation-based classification (active app stays `.frontmost`); the "all-minimized without switching → no restore" case persists as a documented known limitation. NEVER prompt for AX from `runtimeState` (consistent with D7).
  - Cost: one AX window-list query per key-down when the target is the active app and AX is trusted — acceptable.
  - A config with `background = minimize`: an all-minimized active app re-minimizes (effectively no-op) — the self-consistent result of that config, acceptable.

## Already shipped (NOT in this task)
- **Quit** — `FrontmostAction.quit` is implemented and wired (`AppActivationService` → `terminate()`) on `main` since the previous task. Only on the Frontmost state. (Optional future: add Quit to Background — out of scope unless requested.)

## `focus` and multiple windows (clarification)
- The `focus` action uses `NSWorkspace.openApplication(activates: true)`, which activates the app and brings **the app's most-recently-active window** forward — macOS decides; we cannot target a specific window without AX. This is the intended behavior; no change this task.
- Deterministic specific-window focus / window cycling would need AX window enumeration — see Out of Scope (open: could be pulled in since AX is being added).

## Out of scope
- Per-window cycling / focusing a specific window; Spaces/full-screen window control.
- Any AX use beyond reading window list + setting minimized state.

## Technical notes
- AX needs the target pid: `resolver.runningInstances(of:).first?.processIdentifier` → `AXUIElementCreateApplication(pid)`. Window via `kAXMainWindowAttribute` / `kAXFocusedWindowAttribute`; set `kAXMinimizedAttribute`.
- Keep AX entirely inside a `@MainActor` service (e.g. `WindowMinimizer`) injected via `AppController`; models/decision layer stay free of it.
- Spec: `app/system-integration.md` (activation/focus/permissions), `swift/concurrency.md`, `ui/swiftui.md` (permission explainer UI), `swift/quality.md`.
