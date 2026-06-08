# PRD — Update AGENTS.md branch policy

## Goal
Make AGENTS.md's branch references durable/generic, and record the project's branch-archival convention.

## Context
`feat/relay-mvp` was already merged into `main` (PR #1, merge commit `ae2a0c0`), so AGENTS.md's "Project Phase" note ("Lives on branch `feat/relay-mvp`, not yet merged to `main`") is now stale. Naming a specific active branch in a long-lived doc rots quickly.

## Changes (docs only)
1. **Project Phase** — drop the branch sentence; keep only the durable status (v1 feature-complete, manually tested, menu-bar agent + management Window). Do not name any current active branch.
2. **Verify & Commit** — add a branching convention: per-feature work uses a `feat/*` branch that merges to the mainline; merged `feat/*` branches are kept as historical archives and are never deleted (local or remote).

## Out of scope
- No code changes; no edits inside the `<!-- TRELLIS:START/END -->` block.

## Verification
- Re-read the two edited regions; confirm no remaining hardcoded active-branch reference and the archival rule reads generically.
