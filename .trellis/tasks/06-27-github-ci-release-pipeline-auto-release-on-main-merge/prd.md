# GitHub CI release pipeline (auto-release on main merge)

## Goal

每次有改动合并进 `main` 后，GitHub Actions 自动构建 Relay 并发布一个 GitHub Release（产物 = 可下载的 macOS app 包）。目标是把"合并即发版"自动化，省去手动 archive/打包/建 Release 的步骤。

## What I already know

- 项目：原生 macOS app（Swift/SwiftUI/AppKit），Xcode 工程 `Relay/Relay.xcodeproj`，scheme `Relay`。
- **部署目标 `MACOSX_DEPLOYMENT_TARGET = 26.5`**（很高 → 托管 runner 是否有对应 Xcode/SDK 是头号风险）。
- 版本来源：`MARKETING_VERSION = 1.0`、`CURRENT_PROJECT_VERSION = 1`（build），运行时经 Info.plist `CFBundleShortVersionString` / `CFBundleVersion` 读取（AboutSettingsView / BackupService）。
- Bundle ID：`cn.Teethe.Relay`。
- **无签名 / 无 Apple Developer 付费账号**：app un-sandboxed、自用、非 App Store。Release 产物注定**未签名、未公证** → 用户需手动去隔离（`xattr -dr com.apple.quarantine` 或右键打开）。
- 仓库目前**没有任何 `.github/workflows/`**。
- 仓库 `delete_branch_on_merge=false`；main 合并方式 merge commit。
- 本地用 `xcodebuild build -scheme Relay -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` 可成功构建。

## Assumptions (temporary)

- Release 产物用 `.zip`(内含 `.app`) 即可，无需 `.dmg`（待确认）。
- 不需要任何代码签名/公证（无账号）——CI 用 `CODE_SIGNING_ALLOWED=NO` 构建。
- 也希望 PR/push 时跑一遍 build（+ 单测）作为 CI 门禁（待确认是否纳入本任务）。

## Open Questions (Preference/Blocking only)

- [ ] Runner：GitHub 托管 `macos-*` 是否有能编译 26.5 SDK 的 Xcode？若无 → 是否接受 self-hosted（你自己的 Mac）？（research-first）
- [ ] 发布触发粒度：每次 main 合并都发？还是仅当版本号变化/打 tag 时发？
- [ ] 版本/Tag 来源：用 `MARKETING_VERSION`？还是 git tag 驱动？重复版本如何处理（同版本第二次合并怎么办）。
- [ ] 产物形态：`.zip(.app)` / `.dmg` / 两者。
- [ ] 是否在本任务一并加 PR/push 的 build+test 门禁，还是只做 release 管道。

## Requirements (locked)

**Release workflow（`.github/workflows/release.yml`）**
- 触发：`on: push: branches: [main]`，`runs-on: macos-26`。
- 构建：`xcodebuild build -scheme Relay -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -derivedDataPath build`。
- 版本：从 `xcodebuild -showBuildSettings` 读 `MARKETING_VERSION`（记 `VERSION`）。
- 打包：定位 `build/Build/Products/Release/Relay.app` →
  - `.zip`：`ditto -c -k --keepParent Relay.app Relay-<VERSION>.zip`
  - `.dmg`：`hdiutil create`（staging 内含 `Relay.app` + `/Applications` 软链，UDZO 压缩）
- 发布策略（**日常 prerelease / 版本 bump 正式版**）：
  - 若不存在 tag 为 `v<VERSION>` 的正式 release → 视为新版本 → 发**正式版** `v<VERSION>`（prerelease=false，标 latest）。
  - 否则 → 发 **prerelease** `v<VERSION>-<run_number>`（prerelease=true，天然唯一/幂等/可重入）。
  - 工具：`softprops/action-gh-release`，附 `.zip` + `.dmg`，body 含"未签名，需去隔离运行"说明。

**PR build 门禁（`.github/workflows/ci.yml`）**
- 触发：`on: pull_request` + `push`（非 main 分支）。`runs-on: macos-26`。
- 仅 `xcodebuild build ... CODE_SIGNING_ALLOWED=NO`（**build-only**：托管 OS 26.4 < 26.5，宿主单测无法启动；待托管镜像升 26.5 再加单测）。

**前置改动**
- 把 Relay scheme 设为 Shared 并提交 `Relay.xcodeproj/xcshareddata/xcschemes/Relay.xcscheme`（否则 CI 干净检出 `-scheme Relay` 解析不到）。

**文档**
- README/notice 记录：发版机制、版本号 bump 规则、用户如何对未签名 app 去隔离运行。

## Acceptance Criteria (locked)

- [ ] 干净检出下 `xcodebuild build -scheme Relay`（shared scheme）成功。
- [ ] 一次 main 合并后，release.yml 跑通并产出带 `.zip` + `.dmg` 的 Release。
- [ ] 首次（无 `v1.0` 正式 release）→ 发正式版 `v1.0`；同版本后续合并 → prerelease `v1.0-<run>`。
- [ ] PR 触发 ci.yml 跑 build-only 并通过。
- [ ] 重复触发不产生 tag 冲突。
- [ ] 产物去隔离后能在 macOS 26.5+ 运行。

## Decision (ADR-lite)

**Context**: 单人、无签名、自用 macOS 26.5 app，要"合并即发版"。头号未知是托管 runner 能否编译 26.5 SDK。
**Decision**:
- Runner 用托管 `macos-26`（自带 Xcode 26.5 + 26.5 SDK，public 仓库免费）→ 不上 self-hosted。
- 发布粒度：日常 prerelease、`MARKETING_VERSION` bump 时发正式版。
- 产物 `.zip` + `.dmg`，均未签名。
- PR 门禁 build-only（托管 OS 26.4 < 26.5，宿主单测起不来）。
**Consequences**:
- 优点：零成本、全自动、Release 列表干净（正式版稀疏、prerelease 留痕）。
- 取舍：CI 不跑单测（仅编译保障）；产物未签名，用户首次运行需手动去隔离；发正式版依赖手动 bump 版本号。
- 未来：托管镜像升到 26.5 后，把 ci.yml 升级为 build+test；或引入 self-hosted 跑测试。

## Definition of Done

- workflow YAML 通过实际 push/合并验证跑通（或在可控分支上演练）。
- README/notice 记录"如何发版 + 用户如何去隔离运行"。
- 失败路径明确（构建失败不发 Release）。

## Out of Scope (explicit)

- 代码签名 / 公证 / Gatekeeper 合规（无付费账号，明确不做）。
- Mac App Store 发布。
- 自动版本号递增策略的复杂方案（除非选定）。

## Research References

- [`research/github-macos-runner-xcode-26.md`](research/github-macos-runner-xcode-26.md) — GA `macos-26` 托管 runner 自带 Xcode 26.5 + macOS 26.5 SDK，公共仓库免费 → 用托管 runner，无需 self-hosted（caveat：runner OS 是 26.4，启动型 UI 测试别指望在托管上跑，build-only 门禁 OK）。
- [`research/unsigned-macos-app-auto-release-conventions.md`](research/unsigned-macos-app-auto-release-conventions.md) — `xcodebuild build CODE_SIGNING_ALLOWED=NO -derivedDataPath build` → `ditto -c -k --keepParent` 打 `.app` 成 `.zip` → `softprops/action-gh-release` 发到幂等 tag `v<MARKETING_VERSION>-<run_number>`。

## Repo caveats (confirmed, must handle)

1. **Relay scheme 未 shared**（无 `xcshareddata/xcschemes/`，`xcuserdata/` 被 gitignore）→ CI 干净检出 `-scheme Relay` 解析不到。**前置修复**：把 Relay scheme 勾选 "Shared" 并提交 `Relay.xcodeproj/xcshareddata/xcschemes/Relay.xcscheme`（或退而用 `-target Relay`）。
2. **`GENERATE_INFOPLIST_FILE=YES`**，无静态 Info.plist → 版本从 `MARKETING_VERSION`（`xcodebuild -showBuildSettings | grep MARKETING_VERSION`）取，不要找 plist。
3. 仓库 **public** → `macos-26` 托管 runner 免费。

## Recommended approach (from research)

- **Runner**: `runs-on: macos-26`，`xcode-select` 到 Xcode 26.5（或默认即是）。
- **Build**: `xcodebuild build -project ... -scheme Relay -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -derivedDataPath build`。
- **Package**: 定位 `build/Build/Products/Release/Relay.app` → `ditto -c -k --keepParent Relay.app Relay-<version>.zip`。
- **Version/Tag**: 读 `MARKETING_VERSION` → tag `v<MARKETING_VERSION>-<github.run_number>`（天然唯一、幂等、可重入，避免 "tag exists"）。
- **Release**: `softprops/action-gh-release`，附 `.zip`，body 自动列入"未签名，需去隔离运行"的说明 + commit 范围。
- **Trigger**: `on: push: branches: [main]`。

## Technical Notes

- 构建命令基线：`xcodebuild -project Relay/Relay.xcodeproj -scheme Relay -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`（archive/export 方式待研究确认对无签名 app 的最简路径）。
- 版本读取已在 app 内依赖 Info.plist，故 CI 产物版本应与 project 设置一致。
