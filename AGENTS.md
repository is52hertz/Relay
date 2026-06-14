# AI Agent Instructions

This file is the single source of truth for all AI coding assistants working on this project.
Tool-specific files (`CLAUDE.md`) point here.

## Instruction Priority

- Treat this `AGENTS.md` as the authority for product requirements, business rules, coding standards, security/correctness constraints, verification expectations, commit policy, and handoff rules.
- Treat Trellis as the authority for task workflow mechanics: task lifecycle, phase order, PRD/research/spec-context handling, quality-gate sequence, session journal, and finish/archive steps.
- When these instructions and Trellis overlap, apply the more specific authority: product/business/code/security rules from `AGENTS.md`; task lifecycle and phase-flow rules from Trellis.
- Do not use Trellis text to weaken or bypass the business, security, correctness, or scope rules in this file.
- Do not use this file as a reason to skip required Trellis steps unless the current user message explicitly opts out for that turn.

## Product

Relay is a native macOS (Swift / SwiftUI / AppKit) global application switcher — like Thor — with scene-based hotkey groups (Profiles). The user binds global hotkeys to target apps to launch / focus / hide / return-to-previous, and switches a whole set of bindings per workflow (e.g. Coding, Design, Writing). It is a single-user menu-bar agent with a small local dataset (a few Profiles and bindings stored as Codable JSON), targeting macOS 26.5+. There is no paid Apple Developer account: it runs un-sandboxed (it controls other apps), is for local / self-use, and is not aimed at the Mac App Store.

## Project Phase

- **Relay app (`Relay/`)**: v1 feature-complete (PR1–PR5) and manually tested; menu-bar agent plus a management `Window`.
- **Project specs (`.trellis/spec/`)**: not yet authored — still generic templates; see the `00-bootstrap-guidelines` task.

## Development Rules

### Two-Step Confirmation First
- Never start the moment a requirement is stated or changed. Every new or modified requirement first passes through an understand-and-confirm step before any code is written. The only exception is trivial mechanical actions whose intent is obvious (e.g. `git push`, fixing a typo, a one-line rename).
- **Step one — reflect and surface, always in the open before building:**
  - Judge whether the request is sound: is it safe? is it efficient? does it fit the project's scale?
  - Consider whether a better approach exists than the one asked for.
  - State your full understanding of the request, your analysis of it (risks, tradeoffs, anything ill-advised), and your concrete recommendation.
- **Step two — act on the outcome:**
  - If the request is uncertain (multiple approaches with tradeoffs, may affect other features, or ill-suited to the project's scale), wait for the user's confirmation before modifying code.
  - If there is a clearly optimal and safe path, you may proceed without waiting for confirmation — but conspicuously notify the user that you are doing so up front, and on completion state plainly what you changed and why it was the better path.
  - Push back on any request that compromises security, correctness, or runtime efficiency, even when explicitly asked.

### Scope Discipline
- Each task must stay within its stated scope. Do not add, refactor, or "improve" anything outside the current request.
- If the current task logically depends on another unbuilt feature, ask the user before implementing it. Never silently introduce adjacent functionality.

### Coding Standards
- **Source of truth & persistence**: `AppModel` (`@MainActor @Observable`) is the single in-memory source of truth. Persist as Codable JSON in Application Support (atomic write, debounced save). Data models are `nonisolated` Codable value types and must not import AppKit/SwiftUI. Keep persisted formats independent of third-party libraries (e.g. store Carbon key codes, not a library's internal type).
- **Concurrency**: default actor isolation is `MainActor` (Swift 5 language mode). Types touching AppKit/SwiftUI stay on `MainActor`; `AppModel` and services must stay free of AppKit/SwiftUI so they remain unit-testable. Inject services via the composition root (`AppController`); do not use singletons.
- **Global hotkeys**: register only the active Profile, via the `KeyboardShortcuts` package. Never use `CGEventTap` or global `NSEvent` monitors — they require Accessibility / Input Monitoring and are out of scope.
- **Controlling other apps**: prefer public AppKit APIs — `NSWorkspace.openApplication`, `NSRunningApplication.hide/unhide`. From this background agent, bring an app forward with `openApplication(at: bundleURL)`, not `NSRunningApplication.activate(from: .current)` (cooperative activation silently fails for a non-frontmost agent). No private APIs.
- **UI**: SwiftUI-first; bridge to AppKit only when required. The management UI must live in a `Window`, not the `Settings` scene (Settings drops custom toolbars). Use system controls, HIG spacing, light/dark, and full keyboard + VoiceOver. Rely on automatic Liquid Glass from standard containers on macOS 26.5 — do not hand-roll glass. Prefer modern surfaces (`.popover`) over the legacy `.help` tooltip for essential information.
- **Permissions**: functionality takes priority over avoiding permissions. Permission-gated capabilities (e.g. Accessibility, used to minimize a target window) are allowed when they are the way to implement a feature — provided the permission is requested **lazily / on demand** (when the user opts into that feature, or first triggers it), **never at launch**. The app must stay fully functional without the permission; only the gated capability degrades, and it degrades safely (do nothing destructive + surface a one-time notice — never silently do the wrong thing). Note: Accessibility grants app-level access, not a per-feature scope. Global hotkeys still go through `KeyboardShortcuts` (no `CGEventTap` / global `NSEvent` monitors needed).
- **Security boundary**: the app is un-sandboxed and can launch/activate arbitrary apps. Never add code that executes downloaded or arbitrary code, never use private APIs (only documented public AppKit + Accessibility attributes), and never expose any control surface beyond the local user's own machine.

### Verify & Commit
- After any code change, run the project's verification (e.g. type-check / build / lint) across all affected packages.
- If verification fails, fix the errors first, then verify again.
- After verification passes, automatically commit files that were modified by the agent in the current task and belong to the current task.
- Before committing, inspect dirty files and separate current-task agent edits from unrecognized dirty files. Do not include unrecognized dirty files in commits unless the user explicitly asks to include them.
- If a dirty file's ownership or task relevance cannot be determined safely, stop and ask the user before committing.
- Group commits by coherent change unit. Do not push unless explicitly requested.
- Branching: per-feature work lands on a `feat/*` branch that merges into the mainline. Keep merged `feat/*` branches as historical archives — never delete them (local or remote).
- Commit message format (Conventional Commits):
  ```
  type(scope): short summary

  Detailed description of what changed and why.
  ```
  Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`.

### Session Handoff
- `notice.md` files are scoped by directory and record durable handoff information for the next agent.
- Root `notice.md` records global, cross-package, or cross-task project information.
- App/package notices record durable facts for that app/package: architecture, contracts, workflows, credentials, known limitations, and package-specific gotchas.
- Update the relevant `notice.md` only when the session creates or discovers information that remains useful beyond the current task or conversation. Do not record pure Q&A, routine progress, temporary decisions, or workflow session/journal details there.
- Ensure any `notice.md` you touch remains accurate and up-to-date within its directory scope.

### End-of-Session Summary
- At the end of each conversation, output a brief summary in 中文 (Chinese). This summary is user-facing.
  ```
  ## Summary
  - **Done**: work completed this round
  - **Key decisions**: tag each [user] or [self], explain the decision
  - **Commits**: list this round's commits (hash, message, files); note any dirty files left out and why
  - **Open/known risks**: issues introduced or discovered this round (omit if none)
  - **Suggested next steps**: 1-3 concrete actionable items
  ```

<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
