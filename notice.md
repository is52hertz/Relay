# Project Notice (root)

Cross-cutting, durable project facts for the next agent. Scope = whole repo.

## CI / Release pipeline (`.github/workflows/`)

两个 GitHub Actions workflow，均跑在托管 `macos-26` runner（自带 Xcode 26.5 + macOS 26.5 SDK，public 仓库免费）。

### `ci.yml` — PR build 门禁
- 触发：`pull_request`（+ 手动 `workflow_dispatch`）。
- 动作：`xcodebuild build`（Debug，未签名，**build-only**）。
- **为什么不跑测试**：托管 `macos-26` 的 runner OS 是 **26.4**，低于 app 部署目标 **26.5**；
  dyld 无法在 26.4 启动 26.5 二进制，宿主型 XCTest（含单测，TEST_HOST=Relay.app）会启动失败。
  待托管镜像 OS 升到 26.5 即可在此加 `xcodebuild test`；或用 self-hosted 26.5 Mac 专跑测试
  （需限定非 fork 触发，避免公开仓库 fork PR 在你机器上跑任意代码）。

### `release.yml` — 合并 main 即发版
- 触发：`push: branches: [main]`。`concurrency: release-main` 串行化，避免并发抢同一 tag。
- 构建：`xcodebuild build`（Release，未签名）→ `ditto` 打 `.zip` + `hdiutil` 打 `.dmg`。
- 版本来源：`MARKETING_VERSION`（经 `xcodebuild -showBuildSettings` 读；工程 `GENERATE_INFOPLIST_FILE=YES`，无静态 Info.plist）。
- **发布粒度**：
  - 不存在 tag 为 `v<VERSION>` 的正式 release → 发**正式版** `v<VERSION>`（标 latest）。
  - 已存在 → 发 **prerelease** `v<VERSION>-<run_number>`（唯一、幂等、可重入）。
- **如何发新正式版**：bump `MARKETING_VERSION`（Xcode target build setting）后合并 main，即自动出正式版 `v<新版本>`；
  同版本的后续合并只产 prerelease。

### 关键约束 / 坑
- **Relay scheme 必须 shared**：`Relay.xcodeproj/xcshareddata/xcschemes/Relay.xcscheme` 已提交。
  否则 CI 干净检出 `-scheme Relay` 解析不到（`xcuserdata/` 被 gitignore）。
- 产物**未签名未公证**（无 Apple Developer 付费账号）：用户首次运行需去隔离
  （`xattr -dr com.apple.quarantine ...` 或右键打开），README `## 📦 Install` 已说明。
- 第三方 action 固定主版本（均为 Node 24 运行时，避免弃用告警）：`actions/checkout@v5`、`softprops/action-gh-release@v3`。

详细调研：`.trellis/tasks/06-27-github-ci-release-pipeline-auto-release-on-main-merge/research/`。
