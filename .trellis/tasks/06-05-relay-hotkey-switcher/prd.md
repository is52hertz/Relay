# brainstorm: Relay — macOS 全局应用快捷切换器（类 Thor + Profile）

## Goal

构建一个 macOS 原生（Swift + SwiftUI + AppKit）的全局应用快捷切换器 Relay：用户为目标应用配置全局快捷键，按下后根据应用当前状态（未装/未运行/后台/前台/隐藏/无窗口）执行 启动/聚焦/隐藏/切回上一个 等行为；并支持按场景切换整组快捷键（Profile）。类 Thor，额外支持 Profile/快捷键组。本轮仅做需求审计与提问，不落代码。

## What I already know

### 来自用户 brief
- 自用 / 本机测试为主，无付费 Apple Developer Program，暂不要求上架或正式分发。
- 全局快捷键优先 Carbon `RegisterEventHotKey` 或成熟库（`KeyboardShortcuts` / `MASShortcut`）；明确禁止默认用 `NSEvent` 全局监听 / `CGEventTap`（避免 Accessibility / Input Monitoring）。
- 焦点行为（FocusBehavior/ActivationRule）是自定义产品概念，勿与 `NSApplication.ActivationPolicy` 混淆。倾向默认 `Return to Previous App`。
- 运行状态用 `NSRunningApplication`，启动未运行用 `NSWorkspace`。
- UI 必须贴合 HIG 与 macOS 26 Liquid Glass，原生体验、深浅色、键盘导航、VoiceOver、空/错/禁用态。
- 不引入重型依赖（需先说明收益/风险并确认）。

### 来自仓库（实测）
- Xcode 项目已初始化：`Relay/Relay.xcodeproj`，target `Relay`（+ RelayTests / RelayUITests）。
- 当前仅默认模板：`RelayApp.swift`（`WindowGroup { ContentView() }`）、`ContentView.swift`（Hello world）。
- 关键 build settings：
  - `MACOSX_DEPLOYMENT_TARGET = 26.5` → 仅运行于 macOS 26.5+（无旧系统兼容负担，Liquid Glass 全可用）。
  - `ENABLE_APP_SANDBOX = YES`、`ENABLE_HARDENED_RUNTIME = YES`。
  - `DEVELOPMENT_TEAM = 29QGYWRLCD`、`CODE_SIGN_STYLE = Automatic`、`PRODUCT_BUNDLE_IDENTIFIER = cn.Teethe.Relay`、`SWIFT_VERSION = 5.0`。
  - `GENERATE_INFOPLIST_FILE = YES`（无独立 Info.plist），无 `*.entitlements` 文件，未设 `LSUIElement`。

## Decision (ADR-lite) — locked 2026-06-05

**P0（全部确认）**
- P0-1 关闭 App Sandbox（`ENABLE_APP_SANDBOX = NO`）。不上 MAS；保留 Hardened Runtime。
- P0-2 部署目标保持 `26.5`（仅 macOS 26.5+，Liquid Glass 全可用，无 fallback）。
- P0-3 全局快捷键用 `KeyboardShortcuts`(Sindre Sorhus, MIT, SPM)。
- P0-4 v1 单一 Active Profile（同一时刻只注册一组）。
- P0-5 默认 FocusBehavior = Return to Previous App，per-binding 可覆盖。

**P1（全部确认）**
- P1-6 FocusBehavior 收敛为 4 种：Return to Previous（默认）/ Launch or Focus / Toggle Hide / Focus Only（矩阵见下）。
- P1-7 Return to Previous 语义见下；**Previous = 模型 A（全局动态 (current,previous)）已锁定**。
- P1-8 “运行但无可见窗口”：activate + 再发 `openApplication`(reopen) 尝试建窗；不保证所有 App 建窗。
- P1-9 菜单栏为主（默认隐藏 Dock 图标，提供「显示 Dock 图标」开关）；设置用 `Settings`/独立 Window。
- P1-10 v1 含：菜单栏切 Profile、登录启动(`SMAppService`，默认关)；**延后**：热键切 Profile、前台自动切 Profile。
- P1-11 冲突检测：① 组内重复组合；② `RegisterEventHotKey` 注册失败。注册失败保留 binding 但标记「未生效/可能被占用」+ 克制提示。无法枚举具体占用者/他应用快捷键表。
- P1-12 持久化 Codable JSON（Application Support）；存 bundleId + path(+顺序/FocusBehavior)，图标不入库、运行时由 `NSWorkspace` 取；启动按 bundleId 重解析路径，失效则标记。

### FocusBehavior 行为矩阵（4 种）

| 目标状态 | Return to Previous（默认） | Launch or Focus | Toggle Hide | Focus Only |
|---|---|---|---|---|
| 未安装 | 标记失效+提示 | 标记失效+提示 | 标记失效+提示 | 标记失效+提示 |
| 未运行 | 启动并聚焦 | 启动并聚焦 | 启动并聚焦 | 不启动(no-op/轻提示) |
| 后台·有窗 | 聚焦 | 聚焦 | 聚焦 | 聚焦 |
| 已隐藏 | unhide+聚焦 | unhide+聚焦 | unhide+聚焦 | unhide+聚焦 |
| 运行·无窗 | 聚焦+reopen建窗 | 聚焦+reopen建窗 | 聚焦+reopen建窗 | 聚焦+reopen建窗 |
| 已在前台 | 切回 Previous | no-op | hide 目标 | no-op |

### Return to Previous —— Previous 模型 A（锁定）
- **模型 A（全局动态）**：监听 `NSWorkspace.didActivateApplicationNotification` 维护全局 `(current, previous)`，排除 Relay 自身；目标在前台时按热键→激活 `previous`。等价于 ⌘Tab MRU 的深度 2；纯事件驱动、零空闲开销、无 AX/私有 API。模型 B（每 binding 快照）已否决。
- 共同边界：previous 已退出/为空→退化为 hide 目标；previous 是 Relay→跳过找上一个；跨 App 激活用现行协作式激活（`activate(from:)`），调用前对照官方文档核对。

## Requirements (evolving)
- 应用管理：增/删目标应用；读取 名称/图标/bundleId/路径；检测安装与路径失效。
- 快捷键绑定：录入/修改/清空/禁用；显示 `⌃1`/`⌥Space`；组内冲突检测。
- 焦点控制：按状态分支执行（未装/未运行/后台/前台/隐藏/无窗口）。
- FocusBehavior 类型：见 brief 5 种（待裁剪 + 定默认）。
- Profile：增/改名/删/设 active；同 App 跨 Profile 不同快捷键；切换时注销旧注册新；菜单栏切换。

## Acceptance Criteria (evolving)
- [ ] 全局快捷键在 Relay 非前台时可触发（无需 Accessibility）。
- [ ] 各应用状态分支行为符合所选 FocusBehavior。
- [ ] Profile 切换后旧组快捷键注销、新组注册，无残留。
- [ ] 组内快捷键冲突可检测并在 UI 标示。
- [ ] UI 符合 HIG + macOS 26 Liquid Glass，支持深浅色/键盘/VoiceOver/空错禁用态。

## Definition of Done
- 类型检查 / build 通过（受影响 target）。
- 关键服务（注册、激活、持久化）有单元测试。
- notice.md / spec 视情况更新。

## Out of Scope (explicit, 待确认)
- MAS 上架；正式分发（无付费账号）。
- 多 Profile 同时激活（v1 默认否）。
- 前台 App 自动切换 Profile（默认否）。
- 跨 Space / 全屏 的窗口级精确控制（系统限制，无 AX/私有 API 不做）。
- 操作他应用具体窗口（move/resize/raise 单窗）——需 Accessibility，默认不做。

## Technical Notes
- 全局快捷键：Carbon `RegisterEventHotKey` 无需 Accessibility、沙箱内可用；`KeyboardShortcuts`(Sindre Sorhus, MIT, SPM) 封装之 + 提供原生录入器与存储。
- 激活/隐藏：`NSRunningApplication.activate(options:)` / `.hide()` / `.unhide()` 不需 Accessibility；`NSWorkspace.openApplication` 启动；`didActivateApplicationNotification` 追踪前台用于 Return-to-Previous。
- 沙箱：控制他应用与 App Sandbox 冲突（Thor 类工具通常不沙箱、非 MAS 分发）。当前工程沙箱=ON，建议关闭。
- 签名：personal team 可本机自用与本机运行（macOS 本机运行不像 iOS 7 天限制）；分发他机需 Developer ID + notarization（付费）。
- Liquid Glass：target 26.5 全可用；标准容器（NavigationSplitView/Form/List/toolbar/sheet/MenuBarExtra）自动玻璃化；自定义浮层用 `.glassEffect` / `GlassEffectContainer`。**精确 API 签名在写 UI 前以 Apple 官方文档 / apple-skills(hig, ios-liquid-glass) 核对，不臆造。**

## Technical Approach（最终设计）

### 数据模型（值类型，Codable，JSON 持久化）
- `FocusBehavior`：enum `.returnToPrevious(默认)/.launchOrFocus/.toggleHide/.focusOnly`。
- `Hotkey`：自有 Codable 结构（`carbonKeyCode`/`carbonModifiers`），与 `KeyboardShortcuts.Shortcut` 互转——**持久化格式不依赖第三方库内部格式**（降依赖风险）。可空（清空/禁用）。
- `TargetApp`：`id/bundleIdentifier/displayName/lastKnownPath`；图标与运行态不入库，运行时取。
- `Binding`：`id + TargetApp + Hotkey? + FocusBehavior`（app 信息内嵌进 binding；同 App 跨 Profile = 各自独立 binding）。
- `Profile`：`id/name + [Binding]`（有序）。
- `AppConfiguration`（根文档，带 `schemaVersion`）：`[Profile] + activeProfileID? + AppSettings`。
- `AppSettings`：`showDockIcon/launchAtLogin/defaultBehavior`。

### 服务层（引用类型，@MainActor 触 AppKit）
- `PersistenceStore`：`~/Library/Application Support/cn.Teethe.Relay/config.json`，原子写 + 去抖自动保存；内存 SoT。
- `TargetAppResolver`：按 `bundleIdentifier` 经 `NSWorkspace.urlForApplication(...)` 解析，回退 `lastKnownPath`，判定 installed/missing；`NSWorkspace.icon(forFile:)` 取图标，NSCache 缓存。
- `FrontmostTracker`（模型 A）：订阅 `didActivateApplicationNotification`，维护 `(current, previous)`，排除自身；启动用 `frontmostApplication` 初始化。
- `AppActivationService`（焦点引擎）：**纯决策函数（state × behavior → action，可单测）** + 副作用执行（`NSWorkspace.openApplication`(启动/reopen)、`NSRunningApplication.activate(from:)/hide/unhide`）。状态判定：未运行（runningApps 空）、frontmost（bundleId 比对）、isHidden；**「无窗 vs 后台有窗」无 AX 无法精确区分**→统一 unhide+activate(+reopen) 兜底（已在 P1-8 接受）。
- `HotkeyRegistrationService`：profile 激活时为每个有热键的 binding 建动态 `KeyboardShortcuts.Name(binding.id)`，`setShortcut` + `onKeyDown{ activation.handle(binding) }`；切换时全部注销。组内重复冲突**自行计算**（可靠，库无关）；系统级注册失败为 best-effort（依库 API，见研究项）。
- `AppModel`（根 @Observable，环境注入）：持有 `AppConfiguration`，CRUD + setActive；activeProfile 变化→重注册；任何变更→去抖保存。
- `LoginItemService`（`SMAppService.mainApp`）、`DockIconController`（`NSApp.setActivationPolicy(.accessory/.regular)`）。

### UI（SwiftUI，macOS 26 Liquid Glass 自动）
- 场景：`MenuBarExtra`（主，`.menu` 风格 v1）+ `Window`/`Settings`（管理）。默认 `.accessory`（无 Dock 图标），可切 `.regular`。
- 菜单栏：Profile 列表（active 打勾，点选切换）+ 打开设置 + 退出。
- 设置：`NavigationSplitView`——侧栏 Profile（增/改名/删/排序），详情 = 该 Profile 的 binding 列表（图标+名、`KeyboardShortcuts.Recorder`、FocusBehavior `Picker`、状态徽章），含空/错/禁用态。通用设置面板：showDockIcon/launchAtLogin/defaultBehavior。
- Liquid Glass：标准容器（split view/toolbar/list/menu bar）在 26.5 自动玻璃化；v1 不手动加 `.glassEffect`（除非后续做浮层快速切换面板）。VoiceOver/键盘/深浅色靠系统控件 + 显式 `accessibilityLabel`。
- 录入器写入→镜像回我方模型（SoT），细节见研究项。

### 并发
- 热键回调 / 激活在主线程；持久化去抖后台写。`AppModel` 与触 AppKit 的服务标 `@MainActor`。保留 Swift 5 语言模式，必要时再升 Swift 6 严格并发。

## Implementation Plan（小 PR 顺序）
- **PR1 骨架与配置**：关沙箱、设 `.accessory`/LSUIElement 基线、SPM 加 KeyboardShortcuts；落全部模型 + `PersistenceStore` + 根 `AppModel`；空 UI 壳（MenuBarExtra + 空设置窗）。测试：Codable round-trip + 持久化。
- **PR2 激活引擎 + 前台追踪**：`TargetAppResolver`、`FrontmostTracker`(模型 A)、`AppActivationService`（纯决策函数 + 执行），临时调试触发。测试：4×状态决策矩阵。
- **PR3 热键注册 + Profile 切换**：`HotkeyRegistrationService`（动态 Name、切换注销重注册）、组内冲突检测、注册失败 best-effort；Profile CRUD + setActive；菜单栏切换。
- **PR4 设置 UI**：NavigationSplitView profiles/bindings、录入器、行为 Picker、状态徽章、增删 App、空/错/禁用态、HIG/VoiceOver。
- **PR5 设置项与打磨**：登录启动(`SMAppService`)、显示 Dock 图标、App 丢失/路径失效处理、冲突 UI、Liquid Glass 核对、可访问性/深浅色 QA。

## Research References（写码前需核对，落 research/*.md）
- `research/keyboardshortcuts.md` — 动态 `Name`、`setShortcut/getShortcut`、`onKeyDown`、`disable/enable/reset`、SwiftUI `Recorder` 与变更观察、**注册失败可见性**。
- `research/liquid-glass-macos26.md` — 公开 API 与自动采用范围、是否需 opt-in、自定义玻璃前置条件。
- `research/cross-app-activation.md` — macOS 26 `NSRunningApplication.activate(from:)` 协作式激活、`openApplication`/reopen 行为。
