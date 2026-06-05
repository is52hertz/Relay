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
- `Relay/State/AppModel.swift` — `@MainActor @Observable` **内存唯一真相(SoT)**；Profile CRUD + active 切换 + 去抖保存。
- `Relay/UI/` — `MenuBarContent`(inline Picker 切 Profile + SettingsLink + Quit)、`SettingsRootView`(NavigationSplitView 骨架 + 空状态)。
- `RelayApp.swift` — `MenuBarExtra` + `Settings` 场景。

## 关键约定 / gotchas
- **SoT = AppModel 持有的 AppConfiguration**；持久化的 `Hotkey` 只存 carbon 码，**不依赖** KeyboardShortcuts 内部格式。
- **全局快捷键将用 KeyboardShortcuts(SPM, 待 PR3 接入)**：Binding 模式 Recorder（不自动注册/不写 UserDefaults）+ 动态 `Name(binding.id)` + `setShortcut`/`onKeyDown` 仅注册 active profile；切 Profile 时 set(nil)/disable 旧组。
- **冲突检测**：组内重复自算（可靠）；系统/他应用占用只能 best-effort（库不暴露注册失败），见 `research/keyboardshortcuts.md`。
- **焦点引擎(待 PR2)** 用公开 AppKit API：`NSRunningApplication.activate(from:)/hide/unhide`、`NSWorkspace.openApplication`(启动/reopen)、`didActivateApplicationNotification`(FrontmostTracker 模型A)。**无 Accessibility/私有 API**。「无窗」无法精确判定 → unhide+activate+reopen 兜底。
- 默认参数不能调用 @MainActor 初始化器（默认实参是 nonisolated 上下文）；构造放进 init body。

## 验证命令
```bash
cd Relay
xcodebuild -scheme Relay -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -scheme Relay -only-testing:RelayTests -destination 'platform=macOS'
```

## 进度
- ✅ PR1 骨架（config + models + persistence + AppModel + 菜单栏/设置壳 + 测试），build & test 绿。
- ⏭️ PR2 焦点引擎 + FrontmostTracker；PR3 KeyboardShortcuts 注册 + Profile 切换 + 冲突；PR4 设置 UI；PR5 登录启动/Dock 开关/丢失处理/Liquid Glass 核对/可访问性。
- ⚠️ 项目级 Swift/macOS 编码 spec 尚未撰写（`.trellis/spec/*` 仍是 web 模板占位；`00-bootstrap-guidelines` 任务待办）。
