# README 组（en/zh-Hans/zh-Hant）+ GPL LICENSE + 首个预览版 release v0.1.0-preview.1

## Goal

为 Relay 仓库（`is52hertz/Relay`）创建一套面向 GitHub 的 README 组（英文主文件 + 简/繁独立文件）、GPL-3.0 LICENSE，并发布第一个预览版 GitHub release `v0.1.0-preview.1`（附 `.dmg`，release notes 精简：功能摘要 + 启动方式）。

参考两个同作者仓库的门面风格：
- `../VideoPlayer/README.md`：多语言 README 组（`README.md` + `README-<lang>.md`）、徽章、"Built with AI, directed by a human" 叙事、AI-native 开发展示（AGENTS.md/.claude 等）、架构图、GPL-3.0、从源码构建。
- `../BlackoutSignal/README.md`：macOS 菜单栏 App 的实用段落（顶部下载按钮、截图、功能、运行要求、安装首启 Gatekeeper 右键打开 + `xattr`、菜单栏+快捷键用法、工作原理表、从源码构建、隐私、致谢、许可）。

## Confirmed decisions（this turn，用户经 AskUserQuestion 选择）

- **语言：3 种** —— `README.md`(English 主) + `README-zh_cn.md`(简体) + `README-zh_tw.md`(繁體)，与 App 本地化 en/zh-Hans/zh-Hant 一一对应。[user]
- **release tag：`v0.1.0-preview.1`**，标记为 GitHub pre-release，标题 `Relay v0.1.0 · Preview 1`。[user]
- **附 `.dmg`**：出 Release 构建、打包 `Relay.app` 为 `.dmg` 挂到 release；启动方式 = 打开 dmg → 拖入「应用程序」→ 首次右键打开（未公证，附 `xattr -dr com.apple.quarantine` 一行）。[user]
- **协议 GPL-3.0**：加 `LICENSE` 全文 + README 注明（理由同 VideoPlayer：学习项目，保证衍生开放）。[user]
- **图标**：用户自行提供 512×512 PNG，放 `docs/icon.png`；README 头图按 width≈180 引用该路径（文件未到位时仅头图占位，不阻塞）。[user]
- **分支**：本工作在 `docs/readme-and-first-release`（off main），完成后 PR 合入 main；release 在合入后从 main 切 tag。[self]

## 现状（已核实）

- 仓库根目前**无 README、无 LICENSE**。`Icon.icon`（Icon Composer 源，无 PNG）在根与 `Relay/Relay/`。无历史 git tag、无 GitHub release（这是第一个）。
- 平台/构建：Xcode 工程 `Relay/Relay.xcodeproj`，scheme `Relay`；`LSUIElement = YES`（菜单栏 agent）、`ENABLE_APP_SANDBOX = NO`、`ENABLE_HARDENED_RUNTIME = YES`、部署目标 **macOS 26.5+**、Apple Silicon、个人 Apple Development 证书签名、**未公证**。Swift / SwiftUI / AppKit。

## 功能清单（已核实，README「功能摘要」据此写，勿夸大）

- **场景化 Profiles（热键组）**：按工作流（Coding/Design/Writing…）整组切换热键绑定；任一时刻只注册 **active Profile** 的热键。
- **全局热键**：经 `KeyboardShortcuts`（Carbon `RegisterEventHotKey`）注册；**热键本身不需 Accessibility/Input Monitoring**。录制器 `ShortcutRecorder` 录入时临时禁用全局热键。Profile 内同组合冲突会检测并标记。
- **按运行状态的激活行为（ActivationConfig，可复用命名配置）**——针对每个目标 App，按其运行态决定动作：
  - **未运行**：Launch & Focus / Launch in Background / Do Nothing
  - **后台运行**：Focus / Show Without Focus / Minimize
  - **当前最前**：Return to Previous / Hide / Quit / Minimize / Do Nothing
- **控制其它 App** 只用公开 AppKit API：`NSWorkspace.openApplication`（启动/聚焦/切回上一个）、`NSRunningApplication.hide/unhide`（隐藏/显示）。Return-to-Previous 由 `FrontmostTracker` 跟踪上一个最前台 App（深度 2 的 MRU，类 ⌘-Tab）。
- **管理窗口**：Profiles 侧边栏（键盘快捷键导航、内联重命名、active 高亮）、绑定详情、快捷键录制。
- **菜单栏 agent**：`MenuBarContent`；可选 Dock 图标开关（General 设置）。
- **设置**：General（开机自启动 via `SMAppService`、显示 Dock 图标）+ Personalization（界面语言：跟随系统/简体/繁體/English，切换后重启生效）。
- **最小化目标窗口经 Accessibility**：可选能力，**按需/懒授权**（绝不在启动时申请），未授权时安全降级 + 一次性提示。
- **数据与隐私**：单用户本地小数据集，Codable JSON 存 Application Support（原子写、去抖保存）；**无网络、无账号、无遥测**。
- **形态**：un-sandboxed（需控制其它 App）、macOS 26.5+、Apple Silicon。

## Requirements

### R1 — README 组（3 文件，英文为权威源，简/繁为对应翻译）
- 文件：`README.md`（English，主）、`README-zh_cn.md`（简体）、`README-zh_tw.md`（繁體）。
- 每个文件顶部加语言切换行（互链），样式参考 VideoPlayer（`English · 简体中文 · 繁體中文`，当前语言加粗、其余链接）。
- 头部：居中图标 `docs/icon.png`(width≈180) + 项目名 `Relay` + 一句话定位（native macOS 全局 App 切换器 / Thor 类、场景化 Profiles 热键组、菜单栏 agent）。
- 徽章（BlackoutSignal 风格的 release/downloads + 平台/语言/协议）：
  - `github/v/release`、`github/downloads`（指向 `is52hertz/Relay`，release 发布后自动填充）、`macOS 26+`、`Apple Silicon arm64`、`Swift 6`/`SwiftUI`、`license GPL-3.0`。
- 顶部下载按钮（指向 `releases/latest`，文案随语言）。
- 必含段落（融合两参考，**简洁**）：
  1. 一段定位说明（Relay 是什么、解决什么；强调本地/自用、非 MAS）。
  2. **功能 / Features**：按上面「功能清单」写，分组清晰、不夸大；可用一张「按状态 → 可选动作」小表呈现 ActivationConfig。
  3. **运行要求 / Requirements**：Apple Silicon、macOS 26.5+。
  4. **安装 / Install**：从 Releases 下载 `.dmg` → 拖入应用程序 → 首次右键打开（未公证说明 + `xattr -dr com.apple.quarantine /Applications/Relay.app`）。
  5. **使用 / Usage**：菜单栏图标、打开管理窗口、新建 Profile/绑定、录制全局热键、切 Profile；语言在「个性化」里切。
  6. **从源码构建 / Build from source**：`git clone` → `open Relay/Relay.xcodeproj`（Xcode 26，⌘R）/ `xcodebuild -project Relay/Relay.xcodeproj -scheme Relay -configuration Release -destination 'generic/platform=macOS' build`；注明 sandbox 关闭原因（控制其它 App）。
  7. **权限说明**：全局热键不需特殊权限；仅「最小化」可选能力按需申请 Accessibility，且可不授权照常用。
  8. **隐私 / Privacy**：无网络、无遥测、本地 JSON。
  9. **AI-native 开发**（VideoPlayer 调性）：本仓库 `AGENTS.md`/`CLAUDE.md`/`.trellis/` 是有意提交的学习材料；"Built with AI, directed by a human"。
  10. **许可 / License**：GPL-3.0 + 一句「为何 GPL（学习项目）」+ 指向 `LICENSE`。
- 简/繁文件为英文版的**自然中文**（非机翻腔），技术名词与 App 内本地化用词保持一致（如 Profiles、激活行为术语沿用 `ActivationConfig` 的中文显示名）。

### R2 — LICENSE
- 仓库根新增 `LICENSE`：**GPL-3.0 全文**（标准 FSF 文本），版权行 `Copyright (C) 2026 Teethe`（或与 BlackoutSignal 一致的署名）。

### R3 — docs/ 目录
- 创建 `docs/`，README 引用 `docs/icon.png`（用户提供）。本任务**不**生成图标；若用户尚未放入，保持引用路径即可。

### R4 —（独立步骤，main-session 执行，文档合入 + 用户点头后）首个预览版 release
- 出 Release 构建：`xcodebuild -project Relay/Relay.xcodeproj -scheme Relay -configuration Release -derivedDataPath <tmp> -destination 'generic/platform=macOS' build`，取 `Relay.app`。
- 打包 `.dmg`（含 `Relay.app` + `/Applications` 软链便于拖装）：`hdiutil create -volname Relay -srcfolder <stage> -ov -format UDZO Relay-v0.1.0-preview.1.dmg`。
- `gh release create v0.1.0-preview.1 --prerelease --title "Relay v0.1.0 · Preview 1" --notes "<精简notes>" Relay-v0.1.0-preview.1.dmg`。
- release notes **精简**，仅含：① 本版功能摘要（要点列表）② 启动方式（下载 dmg → 拖入 → 右键打开 / xattr；或从源码构建）。

## Acceptance Criteria

- AC1：`README.md`/`README-zh_cn.md`/`README-zh_tw.md` 三文件齐全，顶部语言互链正确，内容一致（同结构、同信息）。
- AC2：功能摘要与代码实际一致（不出现未实现能力 / 不夸大）。
- AC3：`LICENSE` 为 GPL-3.0 全文；README 协议段与之一致。
- AC4：README 引用 `docs/icon.png`；`docs/` 目录存在。
- AC5：所有命令/路径正确（scheme `Relay`、工程路径、`xattr`/`hdiutil`/`gh` 命令可用）。
- AC6（release，R4）：`v0.1.0-preview.1` 为 pre-release，挂 `.dmg`，notes 含功能摘要 + 启动方式。

## Out of Scope

- 不改 App 代码 / 本地化字符串 / 工程配置。
- 不生成图标 PNG（用户提供）。
- 不公证 / 不引入付费签名流程。
- R4 release 的实际发布在文档 PR 合入 main 后、经用户最终确认再由 main-session 执行（对外动作）。
