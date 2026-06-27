# Research: Unsigned macOS App Auto-Release Conventions (GitHub Actions)

- **Query**: Established conventions for a GitHub Actions workflow that auto-builds and publishes a GitHub Release for an UNSIGNED, un-notarized macOS SwiftUI/AppKit app (no paid Apple Developer account), triggered on merges to `main`.
- **Scope**: external (web/docs) + internal (project facts that change the recommendation)
- **Date**: 2026-06-27

## TL;DR (decision-oriented)

For a single-dev unsigned app, the simplest reliable pipeline is:
**`xcodebuild build` (not archive) with `CODE_SIGNING_ALLOWED=NO` → `ditto -c -k --keepParent` the `.app` into a `.zip` → publish with `softprops/action-gh-release@v3` to a unique, idempotent tag (`v<MARKETING_VERSION>-<run_number>` or commit SHA)**, on `push: branches: [main]`, running on the `macos-26` hosted runner. No DMG, no signing, no notarization. Document `xattr -dr com.apple.quarantine` for users.

---

## 0. Cross-cutting finding that de-risks the whole task

**The PRD's headline risk (does a hosted runner have Xcode for the 26.5 SDK?) is resolved: YES.**

- GitHub-hosted `macos-26` runner exists (both arm64 default and `macos-26-intel`/`-large` x64). Source: actions/runner-images README — https://github.com/actions/runner-images/blob/main/README.md
- The `macos-26-arm64` image ships **Xcode 26.5 as default (build 17F42)** plus 26.0–26.6, and **installed SDK `macosx26.5`**. Source (verified 2026-06-27): https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
  - Xcode table: `26.5 (default) | 17F42 | /Applications/Xcode_26.5.app … /Applications/Xcode.app`
  - SDK table: `macOS 26.5 | macosx26.5 | 26.5, 26.6`
- Local toolchain matches exactly (Xcode 26.5, build 17F42), so no Xcode-select gymnastics are strictly required on `macos-26`. Optionally pin with `sudo xcode-select -s /Applications/Xcode_26.5.app` for reproducibility.
- => **Self-hosted runner is NOT required.** (Details belong to the sibling file `research/github-macos-runner-xcode-26.md`; recorded here because it directly determines the recommended design.)

---

## 1. Build + package step (unsigned)

### Recommendation: `xcodebuild build`, NOT `archive`/`-exportArchive`

For an unsigned app, plain `build` is simplest and most reliable. `archive` + `-exportArchive` exists to produce a signed, distributable `.app`/`.pkg` via an `ExportOptions.plist` (`method: mac-application`/`developer-id`/`development`); with no signing identity it adds friction (export step still tries to resolve a signing method) for zero benefit. The `.app` that lands in DerivedData from a plain `build` is a complete, runnable bundle.

### Key flags

```bash
xcodebuild build \
  -project Relay/Relay.xcodeproj \
  -scheme Relay \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
```

- `CODE_SIGNING_ALLOWED=NO` — the load-bearing flag; skips codesign entirely (no identity needed). (Often paired/equivalent context: `CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`, but `CODE_SIGNING_ALLOWED=NO` alone is sufficient and cleanest.)
- `-derivedDataPath build` — pins output to a known relative dir so you can locate the product deterministically (otherwise it's under `~/Library/Developer/Xcode/DerivedData/<hash>`).
- `-destination 'generic/platform=macOS'` — device-agnostic macOS build (the local `platform=macOS` baseline in the PRD also works; `generic/platform=macOS` is the conventional CI form).
- `-configuration Release` — matches the intended distributable.

### Locating and zipping the product

With `-derivedDataPath build`, the bundle is at:

```
build/Build/Products/Release/Relay.app
```

Zip it preserving the bundle (use `ditto`, never `zip`):

```bash
ditto -c -k --keepParent \
  "build/Build/Products/Release/Relay.app" \
  "Relay.zip"
```

- `ditto -c -k --keepParent` is the Apple-blessed way to archive a `.app`: it preserves bundle structure, symlinks, resource forks, and extended attributes that plain `zip` mangles (mangling can corrupt the bundle). `--keepParent` ensures the archive contains `Relay.app/...` rather than its loose contents. This is the same mechanism Apple's notarization docs use for submitting `.app`s.
- To find the product dynamically instead of hardcoding the path:
  `APP=$(find build/Build/Products/Release -maxdepth 1 -name '*.app' | head -1)`
  or query build settings: `xcodebuild -showBuildSettings ... | grep -m1 ' BUILT_PRODUCTS_DIR'`.

### Project-specific CI gotcha (verified in this repo)

- The `Relay` scheme is **NOT shared**: there is no `Relay/Relay.xcodeproj/xcshareddata/xcschemes/`, and `xcuserdata/` is **gitignored** (`.gitignore` lines: `xcuserdata/`, `*.xcuserdatad/`). `git ls-files` shows **no scheme files tracked**.
- `xcodebuild -list` still reports a `Relay` scheme locally because Xcode auto-creates implicit schemes from targets. On a clean CI checkout `xcodebuild -scheme Relay` *usually* still works via the same auto-creation, but the **robust convention** is to mark the scheme "Shared" in Xcode and commit `xcshareddata/xcschemes/Relay.xcscheme`. Alternatives if you don't want to commit a scheme: build with `-target Relay` instead of `-scheme Relay`.
- `build/` and `DerivedData/` are already gitignored — safe to use as the `-derivedDataPath`.

---

## 2. Artifact format conventions

### `.zip(.app)` vs `.dmg`

- For unsigned, self-distributed, single-dev apps, **`.zip` containing the `.app` is the dominant convention** — zero extra tooling (`ditto` is built in), small, and trivial to attach to a Release. Recommended here.
- `.dmg` is nicer UX (drag-to-Applications background image) but adds tooling (`hdiutil`, or actions like `create-dmg`) and, crucially, **adds nothing for an unsigned app** — an unsigned `.dmg` is itself quarantined and Gatekeeper-blocked just like the zip. Treat DMG as optional polish, out of MVP scope (PRD already assumes `.zip`).

### Gatekeeper: what users must do (document this)

Any file downloaded via a browser/`curl` from GitHub Releases gets the `com.apple.quarantine` extended attribute. For an **unsigned, un-notarized** app, Gatekeeper will block first launch with "Relay is damaged / cannot be opened / from an unidentified developer". Document BOTH escape hatches:

1. **Terminal (most reliable on modern macOS):**
   ```bash
   xattr -dr com.apple.quarantine /Applications/Relay.app
   ```
   (`-d` delete attr, `-r` recurse the bundle.) Run after moving the app to `/Applications`.
2. **GUI:** Try to open → it's blocked → **System Settings → Privacy & Security → scroll down → "Open Anyway"**, then confirm.
   - Caveat: the classic **Control-click → Open** bypass has been progressively **tightened in recent macOS** (Sequoia 15 / Tahoe 26): for fully unsigned apps the right-click trick may no longer suffice and the user is routed to the Privacy & Security "Open Anyway" button or must use `xattr`. So lead with the `xattr` command in user docs.

Apple references:
- "Open a Mac app from an unknown developer" — https://support.apple.com/en-us/102445
- `xattr(1)` / quarantine background — widely documented; Gatekeeper overview: https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web

---

## 3. Release-on-merge patterns & versioning

### Trigger: `push: branches: [main]` vs tag-push

- **`on: push: branches: [main]`** — fires on every merge to main → matches the PRD's "merge = release" goal directly. Recommended.
- **`on: push: tags: ['v*.*.*']`** — the more "traditional" release gate (build only when a human pushes a version tag). Cleaner version semantics, but requires a manual tag step, which contradicts "auto-release on merge". The action README shows both forms (`step.if: github.ref_type == 'tag'`, or `on.push.tags` filter). Source: https://github.com/softprops/action-gh-release#-limit-releases-to-pushes-to-tags
- Hybrid (common): run build/test CI on every push+PR, but only **publish** when `startsWith(github.ref, 'refs/tags/')` — keeps releases deliberate. Tradeoff vs PRD intent noted below.

### Deriving the version / tag

Options, with the repo's reality (version lives in `MARKETING_VERSION = 1.0`; `GENERATE_INFOPLIST_FILE = YES`, so there is **no static Info.plist** to read pre-build):

| Source | How | Notes for this repo |
|---|---|---|
| Build setting `MARKETING_VERSION` | `xcodebuild -showBuildSettings -scheme Relay \| awk '/ MARKETING_VERSION/{print $3}'` | Single source of truth; works even though Info.plist is generated. Most accurate. |
| `agvtool` | `agvtool what-marketing-version -terse1` (marketing) / `agvtool what-version -terse` (build/`CURRENT_PROJECT_VERSION`) | Convenient but `agvtool` is finicky with generated plists / multi-config; `-showBuildSettings` is more robust. |
| Generated Info.plist (post-build) | `/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Build/Products/Release/Relay.app/Contents/Info.plist` | Only available **after** build; reads exactly what ships. Good for a sanity check / asset naming. |
| `git tag` | `git describe --tags` | Requires you to be tag-driven; not the chosen model here. |
| Run number / SHA | `${{ github.run_number }}`, `${{ github.sha }}` | Guarantees uniqueness; pairs with MARKETING_VERSION for a human-readable+unique tag. |

### Popular publishing actions

- **`softprops/action-gh-release@v3`** (recommended). Creates the release **and the git tag if it doesn't exist**, uploads `files:` globs, supports `tag_name`, `name`, `body`, `generate_release_notes: true`, `prerelease`, `draft`, `make_latest`, `fail_on_unmatched_files`, `target_commitish`. If a release already exists for the tag, **it updates that release** rather than failing. Requires `permissions: contents: write`. `v3` needs a Node 24 runtime (use `v2.6.2` for older). Source: https://github.com/softprops/action-gh-release
  - Minimal: `tag_name` defaults to `github.ref_name`; for non-tag (branch) pushes you must pass an explicit `tag_name`.
- **`gh release create`** (GitHub CLI, pre-installed on runners) — scriptable alternative: `gh release create "<tag>" Relay.zip --title "<title>" --notes "<notes>"`. Auto-creates the tag. Needs `GH_TOKEN: ${{ github.token }}` and `contents: write`. Docs: https://cli.github.com/manual/gh_release_create

### Idempotency — avoiding "tag already exists" on a re-merged version

The failure mode: `MARKETING_VERSION` stays `1.0`, two merges → both try tag `v1.0` → second collides. Strategies:

1. **Unique build tag (recommended, simplest, always green):** `v${MARKETING_VERSION}-${{ github.run_number }}` (e.g. `v1.0-7`) or `…-${GITHUB_SHA::7}`. Every run gets a fresh tag → never collides; each merge yields a downloadable build. Downside: many releases; use `make_latest: true` so "Latest" always points at newest.
2. **Skip-if-exists gate:** before publishing, check `gh release view "v$VER" >/dev/null 2>&1 && echo exists`; set a step output and `if:` the release step off it (only publish when the version is new). Couple with bumping `MARKETING_VERSION` per real release. Cleaner version list, but a re-merge without a bump produces no release (may be desired).
3. **Update-in-place:** `action-gh-release` already overwrites/updates an existing same-tag release's assets, so pointing repeated `1.0` builds at tag `v1.0` won't error — it just replaces assets. Acceptable if you want exactly one release per marketing version. (Note: GitHub "immutable releases", if enabled on the repo, would break re-upload — then prefer strategy 1.)

---

## 4. Recommended minimal, robust design (+ alternatives)

### Recommended (best fit for single-dev, unsigned, "merge = release")

- **Runner:** `runs-on: macos-26` (has Xcode 26.5 / macosx26.5 SDK; arm64 default).
- **Trigger:** `on: push: branches: [main]` (+ optionally `workflow_dispatch` for manual reruns).
- **Permissions:** `permissions: { contents: write }`.
- **Build:** `xcodebuild build … -derivedDataPath build CODE_SIGNING_ALLOWED=NO` (share+commit the `Relay` scheme first, or use `-target`).
- **Version:** read `MARKETING_VERSION` via `xcodebuild -showBuildSettings`.
- **Tag scheme:** `v${MARKETING_VERSION}-${{ github.run_number }}` → inherently idempotent (Strategy 1).
- **Package:** `ditto -c -k --keepParent build/Build/Products/Release/Relay.app Relay.zip`.
- **Publish:** `softprops/action-gh-release@v3` with `tag_name`, `files: Relay.zip`, `generate_release_notes: true`, `make_latest: true`. Build failure → no release (steps are sequential; release step only runs on success).
- **Docs:** README/notice section: "Download `Relay.zip` → unzip → move to `/Applications` → `xattr -dr com.apple.quarantine /Applications/Relay.app` → open."

### Alternative A — Tag-driven releases (cleaner version history)

`on: push: tags: ['v*.*.*']`; you bump `MARKETING_VERSION`, commit, then `git tag vX.Y && git push --tags`. Tag == version, no run-number suffix, naturally idempotent (one tag = one release). **Tradeoff:** loses "auto on merge"; adds a manual tagging step.

### Alternative B — CI gate on PR/push + release only on bump

Every push/PR runs `xcodebuild build` (+ `xcodebuild test`) as a status check; a separate `if` step publishes a release **only when `MARKETING_VERSION` changed** (diff the build setting vs the previous tag, Strategy 2). **Tradeoff:** more workflow logic; re-merges without a version bump produce no new artifact (often desirable). This is the closest to "production hygiene" if release noise from Strategy 1 becomes annoying.

---

## Caveats / Not Found

- **Scheme not shared (blocking-ish):** must share+commit `Relay.xcscheme` or build via `-target Relay`, else CI may fail to resolve `-scheme Relay` on a clean checkout. Verified against this repo's `.gitignore` and `git ls-files`.
- **No static Info.plist:** `GENERATE_INFOPLIST_FILE = YES` → version must come from `MARKETING_VERSION` build setting (or post-build generated plist), not a checked-in Info.plist.
- **Apple Gatekeeper UX is a moving target:** exact GUI wording/steps differ across macOS 15/26; the `xattr -dr com.apple.quarantine` command is the stable, version-independent instruction — lead with it.
- **Architecture:** `macos-26` default runner is **arm64**; a plain `build` yields an arm64 (or whatever `ARCHS` resolves to) binary. If Intel users matter, set `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` for a universal binary, or use `macos-26-intel`. Not in PRD scope but flag for the implementer.
- **Runner-image specifics** (Xcode list, image churn) belong to sibling file `research/github-macos-runner-xcode-26.md`; only the decision-relevant subset is captured here.
- Could not use the project's configured `mcp__exa__*` search tools (not available in this environment); findings were gathered via direct `curl` of primary sources (GitHub raw README/runner-images, Apple support) — all URLs above were reachability-checked (HTTP 200) on 2026-06-27.
