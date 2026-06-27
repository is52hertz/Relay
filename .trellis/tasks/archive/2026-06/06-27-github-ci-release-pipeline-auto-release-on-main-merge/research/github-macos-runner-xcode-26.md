# Research: GitHub-hosted macOS runners + Xcode 26.5 / macOS 26.5 SDK

- **Query**: As of mid-2026, can GitHub-hosted macOS runners build an Xcode project whose `MACOSX_DEPLOYMENT_TARGET = 26.5` (macOS 26 "Tahoe")? Hosted image inventory, SDK-vs-deployment-target rule, the runner's actual OS version, whether `xcodebuild test` can run, self-hosted option, and a recommendation for this repo.
- **Scope**: external (verified against live `actions/runner-images` repo + `github/docs` repo)
- **Date**: 2026-06-27

## TL;DR

**Build: yes. App-hosted test: no (right now).** The GA `macos-26` image ships **Xcode 26.5 default** (17F42) + Xcode 26.6 with the **macOS 26.5 SDK** installed, so `xcodebuild build` for a 26.5-deployment-target project works on a hosted runner. BUT the runner VM's **own OS is macOS 26.4 (25E246)** — below 26.5 — so a binary/test-host built for min-OS 26.5 cannot launch there, and `xcodebuild test` for app-hosted XCTest would fail at launch. Pin `macos-26`; gate PRs build-only until the hosted image OS rolls to 26.5.

## Findings

### 1. Hosted macOS runner inventory (as of 2026-06-27)

From the runner-images "Available Images" table:

| OS image | YAML labels | Arch |
|---|---|---|
| macOS 26 (arm64) | `macos-26`, `macos-26-xlarge` | arm64 (Apple Silicon) |
| macOS 26 (x64) | `macos-26-intel`, `macos-26-large` | x64 |
| macOS 15 (arm64) | `macos-latest`, `macos-15`, `macos-15-xlarge` | arm64 |
| macOS 15 (x64) | `macos-latest-large`, `macos-15-large`, `macos-15-intel` | x64 |
| macOS 14 (arm64) | `macos-14`, `macos-14-xlarge` | arm64 |
| macOS 14 (x64) | `macos-14-large` | x64 |

Key label nuance: **`macos-latest` currently still points to macOS 15 (arm64)**, NOT macOS 26. The migration `macos-latest` -> `macos-26` is announced for "June 2026" but tracking issue #14167 was still **open** as of 2026-06-23. => Do not rely on `macos-latest`; pin `macos-26`.

- Source: https://github.com/actions/runner-images/blob/main/README.md
- `macos-latest` migration issue (open): https://github.com/actions/runner-images/issues/14167

### 2. What `macos-26` ships — toolchain vs VM OS (the deciding distinction)

From the `macos-26` (arm64 + x64) image READMEs, latest releases `macos-26-arm64/20260623.0192` and `macos-26/20260623.0283`:

- **Runner VM OS Version: macOS 26.4 (25E246)** — Kernel Darwin 25.4.0. (Same value on both arm64 and x64 images; this is the OS the build/test processes actually run on.)
- **Xcode installed**: 26.6 (RC2, 17F113), **26.5 (default, 17F42)**, 26.4.1, 26.3, 26.2, 26.1.1, 26.0.1. `Xcode.app` == 26.5.
- **macOS SDKs installed** include **`macOS 26.5` (`macosx26.5`)** (from Xcode 26.5/26.6), plus 26.0–26.4.

So: the **SDK is 26.5 (>= deployment target) -> compile/link OK**, but the **VM OS is 26.4 (< deployment target) -> running min-OS-26.5 binaries fails**.

- Source (arm64): https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- Source (x64): https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md
- Release tags: https://github.com/actions/runner-images/releases (filter `macos-26`)

### 3. SDK vs deployment target rule

- The SDK must be >= the deployment target. A lower-SDK image (e.g. `macos-15`) **cannot** build a 26.5 target — no workaround. `macos-26` carries the 26.5 SDK, so building needs no workaround.
- Building needs only the SDK (works on `macos-26`). **Running** a built artifact needs OS >= deployment target (see next section).

### 4. Tests on hosted runner (the deciding factor)

**Q1 — Exact runner OS of current `macos-26`:** **macOS 26.4 (25E246)** — i.e. **< 26.5**. (Latest image releases 20260623; confirmed identical on arm64 and x64 READMEs.)
- Cite: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md ("OS Version: macOS 26.4 (25E246)").

**Q2 — Can `xcodebuild test` run app-hosted UNIT tests (RelayTests, `TEST_HOST = Relay.app`, deployment target 26.5)?** **No.** An app-hosted XCTest bundle is injected into the host app, so `xcodebuild test` must **launch `Relay.app` as the main executable**. That executable's Mach-O minimum-OS is 26.5; macOS dyld refuses to launch a binary whose min-OS is newer than the running OS (26.4), failing with a "built for macOS 26.5 which is newer than running OS" style error. The test host never starts, so the test action errors out before any test runs. (Pure compilation — `build-for-testing` — still succeeds; only the run/launch fails.)

**Q3 — If No, options to still gate PRs with unit tests:**

| Option | Works on hosted `macos-26` now? | Notes |
|---|---|---|
| (a) Build-only gate on hosted | **Yes** | `xcodebuild build` (or `build-for-testing`) proves it compiles+links. Simplest; zero infra; no real test execution. |
| (b) Convert RelayTests to logic tests (no `TEST_HOST`) | **Only if test bundle + code-under-test are built min-OS <= 26.4** | The test bundle still loads the app/Relay code, which is min-OS 26.5; loading min-OS-26.5 mach-o on 26.4 also fails. So (b) does not rescue you unless combined with lowering targets, and that only works for code that doesn't require 26.5 APIs. Generally **not viable** while the app needs 26.5. |
| (c) Self-hosted runner on dev's own 26.5 Mac | **Yes** | Tests run for real. But repo is PUBLIC -> fork-PR code execution risk (see section 6). Use only for `push`/internal triggers, not fork PRs. |
| (d) Lower deployment target for the test target only | **No (for an app that truly needs 26.5)** | Test target transitively links the 26.5 app code; loading still hits the 26.5 min-OS gate. Lowering only the test target's own setting doesn't change the linked app code's min-OS. |
| (wait) Hosted image OS rolls to 26.5 | **Eventually yes** | Image OS is already at 26.4 with the 26.5 SDK present; a future weekly image is likely to reach 26.5, after which app-hosted `xcodebuild test` just works on hosted. Re-check the README. |

**Simplest viable recommendation (single-dev, unsigned app):** **(a) build-only gate on hosted `macos-26` now** (run `xcodebuild build`/`build-for-testing` as the PR gate). If you need real unit-test execution before the hosted image reaches 26.5, run tests locally or via a self-hosted 26.5 Mac (option c) restricted to non-fork triggers. Avoid (b)/(d) — they don't actually run while the app requires 26.5.

### 5. Cost note (favors hosted for this repo)

GitHub Actions is **free for standard GitHub-hosted runners in public repositories** (and free for self-hosted). Relay's repo is **public**, so hosted `macos-26` costs nothing.
- Source: https://raw.githubusercontent.com/github/docs/main/data/reusables/actions/actions-billing.md
- Source: https://docs.github.com/en/billing/concepts/product-billing/github-actions

### 6. Self-hosted runner option (own Mac on 26.5 + Xcode)

- **Security (matters here — public repo)**: GitHub warns —
  > "We recommend that you only use self-hosted runners with private repositories. This is because forks of your public repository can potentially run dangerous code on your self-hosted runner machine by creating a pull request that executes the code in a workflow."
  - Source: https://raw.githubusercontent.com/github/docs/main/data/reusables/actions/self-hosted-runner-security.md
  - Docs: https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners
  - Partial mitigations: require approval for fork-PR workflow runs, ephemeral/just-in-time runners, never auto-run untrusted PR code. None removes running on your daily-driver machine.
- **Setup**: repo Settings -> Actions -> Runners -> New self-hosted runner (macOS/arm64) -> `./config.sh --url <repo> --token <token>` -> `./run.sh` or service (`./svc.sh install && ./svc.sh start`). Workflow: `runs-on: [self-hosted, macOS, ARM64]`.
- **Tradeoffs**: + exact local Xcode/SDK and 26.5 host OS (real tests run), no minutes; - machine must stay online/maintained, public-repo security exposure, toolchain drift, secrets/workspace persist locally.

## Recommendation for THIS project

**Release build: GitHub-hosted `macos-26`. PR gate: build-only on hosted now.**

- **Deciding factor (build)**: `macos-26` already defaults to Xcode 26.5 + macOS 26.5 SDK, so the "can a hosted runner compile 26.5?" risk is resolved; hosted is free for this public repo and avoids self-hosted's security exposure.
- **Deciding factor (test)**: hosted VM OS is 26.4 (< 26.5), so app-hosted `xcodebuild test` can't launch the host app -> keep the PR gate **build-only** until the hosted image OS reaches 26.5; run real unit tests locally (or self-hosted, non-fork triggers) if needed sooner.
- **Concrete guidance**:
  1. `runs-on: macos-26` (pin; do not use `macos-latest` until the label migration completes).
  2. Optionally pin toolchain: `DEVELOPER_DIR=/Applications/Xcode_26.5.app` for deterministic SDK.
  3. Build unsigned (PRD baseline): `xcodebuild -project Relay/Relay.xcodeproj -scheme Relay -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
  4. CI gate: `xcodebuild build` (or `build-for-testing`) — do not invoke the `test` action on hosted while VM OS < 26.5.

## Caveats / Not Found

- Images update weekly; the VM OS (26.4 now), default Xcode, and SDK list can move. Re-check the `macos-26` README before relying on specifics — the OS reaching 26.5 is the event that unblocks app-hosted tests on hosted.
- dyld min-OS enforcement is firm for the **main executable** (the app-hosted test host) — this is the load-bearing fact for Q2. The (b)/(d) caveats assume the test code transitively loads min-OS-26.5 app code, which is the case for an app that genuinely targets 26.5.
- `macos-latest` -> `macos-26` migration (issue #14167) unresolved at research time; treat `macos-latest` as macOS 15 for now.
