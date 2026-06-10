# Split Profiles main window and General Settings scene

## Goal

把当前"Profiles 与 General 同处一个 Window 内 TabView 两个分页"的结构,拆成更符合 macOS 原生心智的两个独立场景:
- **主 `Window`** = Profiles 管理(增删 Profile、编辑绑定),作为程序主窗口。
- 真正的 **`Settings` 场景** = 只放 General,走系统 ⌘, / 应用菜单 "Settings…",并做成标准 macOS 设置样式(标签:控件 + 分组分隔 + 灰色说明)。

## What I already know

- 现状:`RelayApp` 只有一个 `Window(id: "main")` 装 `SettingsContainer`(一个 `TabView`),分页 = `SettingsRootView`(Profiles,NavigationSplitView,带 Add Profile 工具栏)+ `GeneralSettingsView`(General,`Form`,固定宽 560,内含激活配置表)。**当前没有真正的 SwiftUI `Settings` 场景。**
- ⌘, 现由菜单栏 "Open Relay…" 手动绑定,打开的是那个 Window。
- `GeneralSettingsView` 是纯 `Form`,`+/−` 在表格 footer,**无窗口级 `.toolbar`** → 可安全进 `Settings` 场景(不踩"Settings 丢自定义 toolbar"的坑)。
- `SettingsRootView` 的 NavigationSplitView 带 Add Profile 工具栏 → 必须留在 `Window`(符合"主窗口"定位)。
- 两个视图都只读同一 `AppModel`;General 还需 `WindowMinimizer`(最小化权限)。

## Confirmed decisions (this turn)

- 重命名:把 `Settings*` 命名改掉(主窗口不该叫 SettingsRootView)。[user]
- 快捷键:`Settings` 场景用系统默认 ⌘,;"Open Relay…" 不绑快捷键。[user]
- General 要做成标准 macOS 设置样式;实测 General **已是** `.formStyle(.grouped)` 的标准 Form(两个 Toggle + Default behavior LabeledContent + 激活配置表),搬进真 Settings 场景即获原生 chrome。配置表保留(决策 A),不变 label:控件行。[user]
- General 范围:**搬 + 微调样式**(加 footer 说明 / 适配 Settings 宽度;不碰表格交互 #3/#4/#5)。[user]
- **启动来源感知**(纠正了"suppressed=永不弹窗"的误区):开机自启→不弹窗;用户显式启动(双击图标/安装后首启)→显示主窗口(Profiles)。[user]

## Open Questions

- (resolved) 激活配置表放哪 → **A:留在 General**。[user]
- General 在 Settings 场景里如何呈现"标准样式":配置表为主体,外层用 `Form`/`Section`(段标题 + footer 说明)套标准 inset 分组 chrome。表格行本身仍是表格(非 label:控件)。待确认 footer 说明文案与是否还要别的段。

## Requirements (evolving)

- 主 `Window`(重命名后)直接以 Profiles 管理为根,去掉 TabView。
- 新增 `Settings { ... }` 场景,注入 `AppModel` + `WindowMinimizer`,内容为 General。
- 菜单栏:"Open Relay…" 打开主窗口(不绑快捷键);⌘, 归系统 Settings。
- General 搬进 Settings 场景 + 轻量样式微调(footer 说明 / 宽度适配)。
- **启动来源感知**:登录项拉起不弹窗;显式启动 `openWindow(主窗口)`。经 AppDelegate 在 `didFinishLaunching` 检测 login-item AppleEvent;`shouldHandleReopen` 也开窗。

## Acceptance Criteria (evolving)

- [ ] 开机自启(SMAppService 登录项)→ 仅菜单栏,无窗口。
- [ ] 用户显式启动(Finder 双击 / 安装后首启)→ 自动显示 Profiles 主窗口。
- [ ] ⌘, 打开系统 Settings(只含 General);应用菜单出现 "Settings…"。
- [ ] "Open Relay…" 打开 Profiles 主窗口,无快捷键。
- [ ] General 在 Settings 场景内呈现标准 grouped 样式(含配置表)。
- [ ] 旧 `SettingsContainer`/`SettingsRootView` 命名清理完毕,无残留误导。
- [ ] 构建 + RelayTests 通过。

## Definition of Done

- 构建 / 测试通过。
- notice.md 若涉及窗口/场景架构变化则更新。
- 命名清理无残留。

## Out of Scope (explicit)

- 后台行为(background actions)本期不扩展。
- 不新增 App 级设置项的具体功能(除非 B 方案下需要占位容器)——待定于 A/B 决策。

## Technical Notes

- `.defaultLaunchBehavior(.suppressed)`:阻止 SwiftUI 在启动时自动打开/状态恢复主窗口;**不**阻止程序化 `openWindow`。保留它,再按启动来源决定是否 `openWindow`。
- **登录项检测**(实现期核实):`SMAppService.mainApp` 登录拉起 vs 用户启动——经典做法是在 `applicationDidFinishLaunching` 读 `NSAppleEventManager.shared().currentAppleEvent`,判 `eventID == kAEOpenApplication` 且 `paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem`。需在 macOS 26 + SMAppService.mainApp 下验证仍有效(Phase 2 codebase/research 阶段确认,不臆造)。
- AppDelegate 经 `NSApplicationDelegateAdaptor` 接入;`openWindow` 只能在 SwiftUI 视图环境取,故 AppDelegate 检测后经一个轻量 `@Observable` 协调器/标志触发 App 侧 `openWindow`(具体桥接实现期定)。
- App 是 `LSUIElement` 菜单栏 agent;`showDockIcon` 运行时切 activationPolicy(`DockIconController`)。
- 文件:`RelayApp.swift`、`UI/SettingsContainer.swift`(删除)、`UI/SettingsRootView.swift`(重命名)、`UI/GeneralSettingsView.swift`(样式微调)、`UI/MenuBarContent.swift`(去 ⌘, 绑定)、新增 AppDelegate + 启动协调器。
