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
- `Relay/Models/` — `ActivationConfig`(按状态焦点配置；含 `NotRunningAction`/`BackgroundAction`/`FrontmostAction` 三枚举，非法组合不可表达) / `Hotkey`(carbon码,库无关) / `TargetApp` / `HotkeyBinding`(`configID` 引用配置) / `Profile` / `AppConfiguration`(`activationConfigs[]` 全局表 + `AppSettings.defaultConfigID`)。皆 `nonisolated` Codable 值类型。
- `Relay/Persistence/PersistenceStore.swift` — `@MainActor`，原子写 JSON 到 `~/Library/Application Support/cn.Teethe.Relay/config.json`。
- `Relay/State/` — `AppModel`(`@MainActor @Observable` **SoT**；Profile CRUD + active 切换 + 去抖保存 + `hotkeysDidChange` 钩子) / `AppController`(组合根：接 model↔服务，启动/切换即重注册热键)。
- `Relay/UI/` — `MenuBarContent`(inline Picker 切 Profile + SettingsLink + Quit)、`SettingsRootView`(NavigationSplitView：Profile 侧栏增/改名/删/设 active + 详情)、`BindingsDetailView`(增删 App/排序/空状态/active 标识)、`BindingRow`(图标+名+失效/冲突标记+录入器+`ActivationConfigPicker` 按名选配置)、`ShortcutRecorder`(自绘录入：本地 keyDown 监听，无 AX)、`GeneralSettingsView`(登录启动/Dock/默认配置 + 焦点配置表 `Table`+＋/－+二步删除确认)、`ActivationConfigPicker`(BindingRow 与 General 共用)、`SettingsContainer`(Settings 分页：Profiles + General)。
- `Relay/Services/` — `AppActivationDecision`(纯决策, nonisolated) / `TargetAppResolver`(解析 URL/实例/图标) / `FrontmostTracker`(模型 A) / `AppActivationService`(执行层) / `Hotkey+KeyboardShortcuts`(桥接) / `HotkeyConflicts`(组内冲突, 纯) / `HotkeyRegistrationService`(active profile 注册) / `LoginItemService`(SMAppService 登录启动) / `DockIconController`(Dock 图标策略)。
- `RelayApp.swift` — `MenuBarExtra` + `Settings` 场景。

## 关键约定 / gotchas
- **SoT = AppModel 持有的 AppConfiguration**；持久化的 `Hotkey` 只存 carbon 码，**不依赖** KeyboardShortcuts 内部格式。
- **全局快捷键用 KeyboardShortcuts(SPM 2.4.0, 已接入；pbxproj 手工加包，ID 前缀 `DEADBEEF…`)**：`HotkeyRegistrationService` 用动态 `Name(binding.id)` + `setShortcut`/`onKeyDown` 仅注册 active profile；切 Profile 时 set(nil)/disable 旧组；handler 每 Name 只装一次、读 `bindingsByName` 取最新动作（不依赖 removeAllHandlers）。录入器（Binding 模式 Recorder）在 PR4。
- **冲突检测**：组内重复自算（可靠）；系统/他应用占用只能 best-effort（库不暴露注册失败），见 `research/keyboardshortcuts.md`。
- **焦点引擎** 大部分用公开 AppKit API：`NSRunningApplication.activate(from:)/hide/unhide`、`NSWorkspace.openApplication`(启动/置前/reopen)、`didActivateApplicationNotification`(FrontmostTracker 模型A)。运行态合并为 notInstalled/notRunning/running/frontmost（「后台/隐藏/无窗」无 AX 不可细分 → running，执行层 unhide+openApplication 兜底）。**前台/后台的「可见窗口」细分（D8，06-09）**：当目标即当前活跃 App 且 `minimizer.isTrusted` 时，问 `WindowMinimizer.hasVisibleWindow(ofPID:)`——有未最小化窗口 → `.frontmost`，全部最小化 / 0 窗口 → `.running`（后台，命中默认 focus 走 D7 取消最小化）。AX 未信任 / 读取失败 → 回退到原「活跃即 .frontmost」（全最小化未切换的场景为已知局限，**绝不在 runtimeState 弹 AX 权限**）。`hasVisibleWindow` fail-safe：copy `kAXWindowsAttribute` 失败/非数组 → true；空数组（确定 0 窗口）→ false；任一窗口确证未最小化 → true；单窗口读 minimized 失败按「未能证明已最小化」倾向 true；全部确证最小化 → false。启动/聚焦统一走 `bringToFront`(unhide+openApplication)；Return to Previous 无 previous 时退化为 hide。**`focus` 经 `openApplication(activates:true)` 拉起 App「最近活跃的窗口」（macOS 决定，无 AX 不能定向具体窗口）——这是预期行为；按窗口循环/定向聚焦仍 out-of-scope**。
- **后台列已可编辑（06-09）**：三态全部接入引擎——`focus`(unhide+activate) / `showWithoutFocus` / `minimize`。`BackgroundAction.isImplemented`/`FrontmostAction.isImplemented` 现恒为 true。沿用单一 `background` 动作 + 按 `isHidden` 智能执行（**不**拆 已隐藏/未隐藏，表仍 4 列，D2）。
- **`showWithoutFocus` 语义 = 「先抬升再还焦点」(D6，手测后修正——非「仅 unhide-in-place」)**：执行层 (1) 抓 `NSWorkspace.frontmostApplication`（按键时是用户的 App，Relay 是后台 agent 非前台）；(2) 走 `bringToFront`（`openApplication activates:true`，同时 unhide / 机会式取消最小化）把目标抬到最前并聚焦；(3) **在 (2) 的 `openApplication` 完成回调里**（回调在后台并发队列，故 `Task { @MainActor }` 跳回主 actor）用 `bringRunningAppToFront`（同走 openApplication，**不**用 `activate(from:.current)`——后台 agent 协作激活静默失败）把原前台 App 还焦。守卫：无前台 App 或它即目标(bundleID 相同) → 跳过 (3)。纯公开 API。取舍：被还焦 App 窗口回到最上，重叠处盖住目标，可能轻微闪烁。
- **`focus` 机会式取消最小化（D7，NO prompt）**：窗口被最小化到 Dock 时 `openApplication` 只激活 App 不显示窗口。`bringToFront` 在 **`minimizer.isTrusted` 已为真** 时调 `WindowMinimizer.unminimizeFocusedWindow(ofPID:)`（设 `kAXMinimizedAttribute=false`，窗口解析复用 `focusedOrMainWindow`）。**`focus` 绝不弹权限、不走 `onPermissionDenied`**——未信任则静默保持 openApplication 原行为；只有显式选 Minimize 才弹(D5)。
- **最小化（minimize）经 Accessibility，权限延迟申请（06-09）**：唯一 AX 入口是新服务 `WindowMinimizer`(`@MainActor @Observable`，注入)；`AXUIElementCreateApplication(pid)` → 读 `kAXFocusedWindowAttribute`(回退 `kAXMainWindowAttribute`) → 设 `kAXMinimizedAttribute=true`。**只作用于焦点/主窗口**(D3)，pid 取 `resolver.runningInstances(of:).first?.processIdentifier`。**绝不在启动时弹窗**：仅当用户在 General 选「Minimize」时 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt:true])` 弹窗(D5)。触发时若 `AXIsProcessTrusted()` 为假 → **不做任何破坏性操作**，经 `onPermissionDenied` 回调由 `AppController` 弹一次性 `NSAlert`(打开系统设置)，绝不退化为别的动作(D4)。模型/决策层仍 nonisolated、无 AX——决策层只产出 `.minimize`，信任态/降级是执行层职责。AX 权限为 **App 级全量**（非 minimize 专属）。
- 默认参数不能调用 @MainActor 初始化器（默认实参是 nonisolated 上下文）；构造放进 init body。
- **AppController 在 `@State` 初始化期运行（早于 NSApp 建立）**：用 `NSApplication.shared`（非 `NSApp`，后者此时为 nil 会崩）；登录项/Dock/注册等系统副作用在 XCTest 宿主下跳过（`XCTestConfigurationFilePath` 判定），否则测试宿主 App 崩溃。
- 登录启动（SMAppService）在无正式签名/非 /Applications 运行时可能不持久——已知限制，失败仅 NSLog。
- **管理 UI 用 `Window`(id `main`) 而非 `Settings` 场景**：Settings 窗口不支持自定义 `.toolbar` 按钮（Add App/Profile、Set as Active 会失效）、且切激活策略时窗口异常。菜单栏「Open Relay…」→ `openWindow` + `NSApplication.shared.activate()`；`.defaultLaunchBehavior(.suppressed)` 防 agent 启动弹窗。
- **跨 App 激活一律用 `NSWorkspace.openApplication(at: bundleURL)`，不要用 `NSRunningApplication.activate(from: .current)`**：Relay 是后台 agent、非前台，协作式激活会静默失败（Return to Previous 曾因此切不回去）。
- **`ShortcutRecorder` 录制期间设 `KeyboardShortcuts.isEnabled=false`，stop()/dismantle 恢复 true**：否则按下的组合会被已注册的全局热键截走、触发别的 App，录不进来（也使「录入重复组合 → 触发组内冲突 Warn」成为可能）。
- **焦点行为 = `ActivationConfig` 全局表（替代旧 `FocusBehavior` 枚举）**：每条按「未启动/后台/前台」赋原子动作，绑定/默认存 `configID`/`defaultConfigID`。决策层 `AppActivationDecision.action(for:config:)` 仍纯，输出 `Action`（`launchWithoutFocus`=`openApplication activates:false`、`quit`=`terminate()`、`showWithoutFocus`、`minimize`）。配置编辑经 `HotkeyRegistrationService` 的 `configResolver` 闭包在按键时实时解析，**无需重注册**（`AppController` 接线，读 `model`）。删除被引用配置 → 二步确认（`confirmationDialog` 列依赖 `Profile › App`）后把绑定回退全局默认；删全局默认先把指针移到剩余首行；`－` 在最后一行禁用（始终 ≥1 配置，无悬空引用）。后台三态与「最小化」的接入见上文（06-09）。
- **AGENTS.md 权限立场（06-09 起放宽，通用）**：功能优先于「避免权限」；权限门控能力（如 Accessibility）在确为实现手段时允许使用，**唯一硬要求是延迟/按需申请（绝不在启动时）**，无权限时 App 仍全功能、只降级被门控的那一项且安全降级。保留硬边界：无私有 API（仅文档化的公开 AppKit + AX 属性）、不执行下载/任意代码、不暴露超出本机的控制面；热键仍走 `KeyboardShortcuts`。

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
- ✅ PR5 收尾：`LoginItemService`(SMAppService) + `DockIconController` + `GeneralSettingsView`(登录启动/Dock/默认行为) + Settings 分页(`SettingsContainer`)。系统副作用经 `AppController.settingsDidChange` 接线、启动同步、测试宿主跳过。build+test 绿(9) + 真机 smoke 启动通过。
- 🎉 PRD 全部 5 个 PR 完成。UI 全用标准容器（NavigationSplitView/Form/List/toolbar/MenuBarExtra），macOS 26.5 自动 Liquid Glass；未手抹玻璃；图标/徽章补了 accessibilityLabel。
- ✅ 焦点行为重构（06-08）：删 `FocusBehavior` 枚举 → `ActivationConfig` 全局可增删改配置表（General 内 `Table`+＋/－+二步删除确认）；按状态动作（未启动/前台可编辑，后台＋最小化占位禁用）；新增 `launchWithoutFocus`/`quit`；`ActivationConfigPicker` 复用于 BindingRow/General；`configResolver` 实时解析。无迁移（未上线）。build+RelayTests 绿(10)。详见 `.trellis/tasks/archive/2026-06/06-08-redesign-focus-behavior-per-state/prd.md`。
- ✅ 后台可编辑 + 最小化（06-09）：后台列去禁用、三态接入引擎（focus/showWithoutFocus/minimize）；`minimize` 经新 `WindowMinimizer`(唯一 AX 入口) 最小化焦点/主窗口，权限延迟申请（选 Minimize 时弹），AX 未授权时无操作 + 一次性 `NSAlert`(D4)；`AppActivationDecision` 保持纯（产出 `.minimize`/`.showWithoutFocus`，信任态在执行层）；AGENTS.md 权限边界放宽为通用原则。build + RelayTests 绿(13)。**待真机手测**：minimize 实际效果、AX 授权弹窗、未授权降级提示（build 不能验证）。详见 `.trellis/tasks/06-09-background-editable-and-minimize-accessibility/prd.md`。
- ✅ 焦点行为细化（06-09，手测后修正 D6/D7，纯执行层）：`showWithoutFocus` 改为「抓前台→`bringToFront` 抬升目标→在 openApplication 完成回调里 `bringRunningAppToFront` 还焦」（D6）；`focus`/`bringToFront` 在 `minimizer.isTrusted` 已真时 `unminimizeFocusedWindow(ofPID:)` 机会式取消最小化、**绝不弹权限/提示**（D7）。决策层/模型不变。build + RelayTests 绿(13)。**待真机手测**：showWithoutFocus 还焦时序/闪烁、focus 对已最小化窗口的还原。
- ✅ 「前台 = 有可见窗口」运行态细分（06-09，D8，纯执行层）：`AppActivationService.runtimeState` 在目标为活跃 App 且 `minimizer.isTrusted` 时调新方法 `WindowMinimizer.hasVisibleWindow(ofPID:)` 细分 `.frontmost`/`.running`（全最小化/0 窗口 → 后台，命中默认 focus → D7 还原窗口，统一「最小化已切换/未切换」两种情形）。未信任/AX 读取失败 → 回退活跃即 `.frontmost`，**绝不弹 AX**。纯决策 `AppActivationDecision`/模型不变（无新 RuntimeState case）。build + RelayTests 绿(13)。**待真机手测**：活跃 App 全部窗口最小化后触发热键应还原窗口（已授权）；未授权时维持原行为。
- 仍未做（PRD 明确 out-of-scope / 延后）：热键切 Profile、前台自动切 Profile、多 Profile 同时激活、跨 Space/全屏窗口级控制、按窗口循环/定向聚焦具体窗口、Quit on Background。项目级 Swift spec（`.trellis/spec`）已撰写（非占位）。
