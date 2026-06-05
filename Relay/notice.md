# Relay — App Package Notice

Durable handoff for the Relay macOS app. Scope: `Relay/` (Xcode project).

## What Relay is
基于场景的 macOS 全局应用快捷切换器（类 Thor + Profile/快捷键组）。详见任务 PRD：
`.trellis/tasks/06-05-relay-hotkey-switcher/prd.md`（含 FocusBehavior 矩阵、Previous 模型 A、全部 P0/P1 决策）。

## Build / signing 立场（已定）
- 部署目标 **macOS 26.5+**（仅新系统，Liquid Glass 全可用，无 fallback）。
- **App Sandbox = OFF**（控制他应用与沙箱冲突；不上 MAS）。**Hardened Runtime = ON**。
- **LSUIElement = YES**：菜单栏 agent（默认无 Dock 图标）；"显示 Dock 图标" 开关留待 PR5。
- 无付费 Developer Program：本机自用/开发可行；分发他机需 Developer ID + notarization（未来）。
- 工程用 **PBXFileSystemSynchronizedRootGroup**：新增 `.swift` 文件直接放进 `Relay/Relay/` 即自动编译，无需改 pbxproj。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`：未标注类型默认 MainActor 隔离。**纯数据模型标 `nonisolated`** 以满足 Codable/Hashable/Sendable。

## 模块地图（PR1 已落）
- `Relay/Models/` — `FocusBehavior` / `Hotkey`(carbon码,库无关) / `TargetApp` / `HotkeyBinding` / `Profile` / `AppConfiguration`(+`AppSettings`)。皆 `nonisolated` Codable 值类型。
- `Relay/Persistence/PersistenceStore.swift` — `@MainActor`，原子写 JSON 到 `~/Library/Application Support/cn.Teethe.Relay/config.json`。
- `Relay/State/` — `AppModel`(`@MainActor @Observable` **SoT**；Profile CRUD + active 切换 + 去抖保存 + `hotkeysDidChange` 钩子) / `AppController`(组合根：接 model↔服务，启动/切换即重注册热键)。
- `Relay/UI/` — `MenuBarContent`(inline Picker 切 Profile + SettingsLink + Quit)、`SettingsRootView`(NavigationSplitView：Profile 侧栏增/改名/删/设 active + 详情)、`BindingsDetailView`(增删 App/排序/空状态/active 标识)、`BindingRow`(图标+名+失效/冲突标记+录入器+行为 Picker)、`ShortcutRecorder`(自绘录入：本地 keyDown 监听，无 AX)。
- `Relay/Services/` — `AppActivationDecision`(纯决策, nonisolated) / `TargetAppResolver`(解析 URL/实例/图标) / `FrontmostTracker`(模型 A) / `AppActivationService`(执行层) / `Hotkey+KeyboardShortcuts`(桥接) / `HotkeyConflicts`(组内冲突, 纯) / `HotkeyRegistrationService`(active profile 注册)。
- `RelayApp.swift` — `MenuBarExtra` + `Settings` 场景。

## 关键约定 / gotchas
- **SoT = AppModel 持有的 AppConfiguration**；持久化的 `Hotkey` 只存 carbon 码，**不依赖** KeyboardShortcuts 内部格式。
- **全局快捷键用 KeyboardShortcuts(SPM 2.4.0, 已接入；pbxproj 手工加包，ID 前缀 `DEADBEEF…`)**：`HotkeyRegistrationService` 用动态 `Name(binding.id)` + `setShortcut`/`onKeyDown` 仅注册 active profile；切 Profile 时 set(nil)/disable 旧组；handler 每 Name 只装一次、读 `bindingsByName` 取最新动作（不依赖 removeAllHandlers）。录入器（Binding 模式 Recorder）在 PR4。
- **冲突检测**：组内重复自算（可靠）；系统/他应用占用只能 best-effort（库不暴露注册失败），见 `research/keyboardshortcuts.md`。
- **焦点引擎(PR2 已落)** 用公开 AppKit API：`NSRunningApplication.activate(from:)/hide/unhide`、`NSWorkspace.openApplication`(启动/置前/reopen)、`didActivateApplicationNotification`(FrontmostTracker 模型A)。**无 Accessibility/私有 API**。运行态合并为 notInstalled/notRunning/running/frontmost（「后台/隐藏/无窗」无 AX 不可细分 → running，执行层 unhide+openApplication 兜底）。启动/聚焦统一走 `bringToFront`(unhide+openApplication)；Return to Previous 无 previous 时退化为 hide。
- 默认参数不能调用 @MainActor 初始化器（默认实参是 nonisolated 上下文）；构造放进 init body。

## 验证命令
```bash
cd Relay
xcodebuild -scheme Relay -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -scheme Relay -only-testing:RelayTests -destination 'platform=macOS'
```

## 进度
- ✅ PR1 骨架（config + models + persistence + AppModel + 菜单栏/设置壳 + 测试），build & test 绿。
- ✅ PR2 焦点引擎：`AppActivationDecision` 纯决策（16 组合单测）+ `TargetAppResolver` + `FrontmostTracker`(模型A) + `AppActivationService` 执行层。
- ✅ PR3 热键：KeyboardShortcuts 2.4.0 接入 + `HotkeyRegistrationService`（active profile 注册/切换）+ `HotkeyConflicts`（组内重复，2 单测）+ `AppController` 接线。
- ✅ PR4 设置 UI：Profile 侧栏(增/改名/删/设 active) + 绑定行(图标/失效/冲突徽章/自绘录入器/行为 Picker) + 增删 App(NSOpenPanel)/排序/空状态。AppModel 加 binding CRUD（视图解析 onDelete/onMove，model 仍无 SwiftUI）。**坑：KeyboardShortcuts 2.4.0 的 SwiftUI Recorder 仅 Name 模式（会自动注册）→ 自绘 `ShortcutRecorder`(本地 keyDown + `Shortcut(event:)`) 保持「仅 active profile 注册」不变式**。build+test 绿(9 用例) + 真机 smoke 启动通过。
- ⏭️ PR5 登录启动(SMAppService)/Dock 图标开关/通用设置/丢失处理打磨/Liquid Glass 核对/可访问性收尾。
- ⚠️ 项目级 Swift/macOS 编码 spec 尚未撰写（`.trellis/spec/*` 仍是 web 模板占位；`00-bootstrap-guidelines` 任务待办）。
