# Localization: 简体 / 繁體中文 + 「个性化」设置标签页

## Goal

让 Relay 支持多语言（简体中文 zh-Hans + 繁體中文 zh-Hant，外加现有 English），用 Xcode 官方推荐的 **String Catalog（`Localizable.xcstrings`）** 做本地化基础设施；在设置窗口新开一个「个性化 / Personalization」标签页，内含语言选择器，可在「跟随系统 / 简体中文 / 繁體中文 / English」间切换，切换后自动重启 App 生效。全程不破坏现有功能。

## What I already know（现状勘查）

- **工程形态**：Xcode 工程，`GENERATE_INFOPLIST_FILE = YES`（无手写 Info.plist）、`developmentRegion = en`、`knownRegions = (en, Base)`、`LSUIElement = YES` 菜单栏 agent。**目前无任何本地化**（无 `.xcstrings` / `.lproj`）。
- **工程用 `PBXFileSystemSynchronizedRootGroup`**（notice.md 第 14 行）：放进 `Relay/Relay/` 的文件自动编译；Resources 构建阶段为空、由同步组接管。→ **`Localizable.xcstrings` 放进 `Relay/Relay/` 即自动随包编译，无需改 pbxproj 的文件引用 / Resources 阶段**。
- **唯一需手改 pbxproj 处**：`PBXProject.knownRegions` 增加 `"zh-Hans"`、`"zh-Hant"`（让构建产出对应 `.lproj`、系统识别为可用本地化）。`developmentRegion` 仍为 `en`。
- **设置窗口结构**：`SettingsRootView` = System Settings 风格 `NavigationSplitView`（始终双列、去折叠键），目前仅 `general` 一个 `Pane`，注释已预留「后续直接扩 Pane」。加「个性化」标签顺这个结构走。
- **服务注入约定**：服务经组合根 `AppController` 创建、`.environment(...)` 注入窗口（如 `minimizer`），**不用单例**（CLAUDE.md / notice.md）。语言服务照此办理。
- **文案两类**：
  - **自动可本地化**（字符串字面量 → `LocalizedStringKey`，只需 catalog 补译，不改调用点）：`Text("…")` / `Toggle` / `Section` / `Button("…")` / `Label("…", systemImage:)` / `LabeledContent` / `TableColumn` / `Picker("…")` / `.navigationTitle` / `.navigationSubtitle(三元两个字面量)` / `ContentUnavailableView` / `.confirmationDialog` / `.accessibilityLabel("字面量")` / `TextField("…")` / `.help("…")`。
  - **不会自动本地化，必须改源码为 `String(localized:)`**（`Text(变量)`、AppKit 控件属性都是 verbatim）：
    1. `Models/ActivationConfig.swift` — `NotRunningAction` / `BackgroundAction` / `FrontmostAction` 的 `displayName`（×3 枚举，被 `Text(action.displayName)` 用）。
    2. `UI/BindingsDetailView.swift` — `NSOpenPanel`：`panel.prompt = "Add"`、`panel.message = "Choose an application to add to this profile."`。
    3. `UI/ShortcutRecorder.swift` — `NSButton`：`"Type shortcut…"`、`"Record Shortcut"`。
    4. `State/AppController.swift` — `NSAlert`：`messageText`、`informativeText`、`addButton(withTitle:)` ×2（"Open System Settings" / "Later"）。
    5. 新建项默认名：`UI/ProfilesView.swift` 的 `"New Profile"`、`UI/GeneralSettingsView.swift` 的 `"New Behavior"`。
  - **用户/运行时数据，不本地化**：`Text(profile.name)` / `Text(config.name)` / `Text(binding.app.displayName)`（这些是用户内容或 App 名）。

## Confirmed decisions（this turn）

- **生效方式**：切换语言写入 `AppleLanguages`（UserDefaults），随后**自动重启 App** 生效。[user]
  - 自我补充（安全 UX）：重启前弹一次轻量确认（默认按钮「立即重启」，另「取消」回退选择），避免误点导致 App 在编辑途中被突兀杀掉；`willTerminate` 已 flush 保存，无数据丢失。[self]
- **翻译范围**：整个界面全译，简体 + 繁體（约 60 条静态文案 + 上述 5 处 `String(localized:)`）。[user]
- **语言选项**：跟随系统 + 简体中文 + 繁體中文 + English（四项）。[user]
  - 选项显示文案：语言名用本族自名（autonym）「简体中文」「繁體中文」「English」；「跟随系统」一项本地化（`String(localized:)`）。[self]
- **本地化机制**：String Catalog（`Localizable.xcstrings`），Apple 官方推荐、Xcode 15+ 标准；不引第三方、不 swizzle Bundle。[self]
- **语言服务归属**：新增 `LanguageService`（`@MainActor`，经 `AppController` 注入 Settings 窗口），读当前选择 / 应用并重启。源真相用 `AppleLanguages`（同 `LoginItemService` 同步 OS 状态的思路），**不写进 Codable JSON**（避免双真相）。[self]

## Requirements

### R1 本地化基础设施
- 新增 `Relay/Relay/Localizable.xcstrings`，`sourceLanguage = en`，含 `zh-Hans` / `zh-Hant` 两套翻译。
- pbxproj `knownRegions` 增加 `zh-Hans`、`zh-Hant`（仅此一处 pbxproj 改动）。

### R2 全量翻译
- 所有「自动可本地化」字面量在 catalog 里有 zh-Hans + zh-Hant（state=translated）条目；key = 源英文字面量；唯一插值串 `Delete “\(name)”?` 的 key 为 `Delete “%@”?`（SwiftUI 插值→`%@`）。
- 上述 5 处源码改 `String(localized:)`，其 key 同样进 catalog 补译。

### R3 个性化标签页
- `SettingsRootView` 加 `Pane.personalization`（icon 如 `paintbrush` 或 `globe`，标签「Personalization」本地化）。
- 新增 `UI/PersonalizationSettingsView.swift`：`Form` + 语言 `Picker`（四选项）；与 General 风格一致（`.formStyle(.grouped)`）。

### R4 语言服务与重启
- 新增 `Services/LanguageService.swift`：`AppLanguage` 枚举（`.system` / `.english` / `.simplifiedChinese` / `.traditionalChinese`）；
  - 读当前：从 `AppleLanguages.first` 映射，无匹配 → `.system`。
  - 应用：`.system` → `removeObject(forKey: "AppleLanguages")`；其余 → `set([code], forKey:)`；`synchronize()` 后重启。
  - 重启：`/usr/bin/open -n <bundlePath>`（Process）拉新实例后 `NSApp.terminate(nil)`；新实例读新 `AppleLanguages`。
- 经 `AppController` 创建并 `.environment(...)` 注入 Settings 窗口（`RelayApp.swift`）。
- 切换前弹确认 `NSAlert`（立即重启 / 取消）。

## Acceptance Criteria
- [ ] `xcodebuild build`（CODE_SIGNING_ALLOWED=NO）通过；`RelayTests` 通过（13 用例不回归）。
- [ ] 设置窗口出现「个性化 / Personalization」标签页，含四项语言选择器；当前选择正确回显。
- [ ] 选简体 / 繁體 → 确认重启 → 重启后菜单栏、设置、Profiles、绑定行、空状态、`NSOpenPanel`、`NSAlert`、录入器按钮、action 下拉项均为对应中文。
- [ ] 选「跟随系统」→ 移除覆盖、回退系统语言；选 English → 回到英文。
- [ ] 用户数据（Profile 名、Config 名、App 名）不被翻译；现有功能（热键、激活、登录项、Dock、最小化）无回归。
- [ ] `knownRegions` 含 zh-Hans / zh-Hant；产物 bundle 内有 `zh-Hans.lproj` / `zh-Hant.lproj`。

## Definition of Done
- 构建 + RelayTests 绿。
- `Relay/notice.md` 增补：本地化机制（String Catalog）、个性化标签、`LanguageService`、`knownRegions`、`String(localized:)` 改动点、「切换语言=重启生效」「用户数据不译」等约定。
- 真机手测项列清（语言切换+重启、各界面中文、跟随系统/English 回退）——构建不能验证，交用户手测。

## Out of Scope（explicit）
- 首次启动种子数据名（`Default` Profile、4 个种子 Config 名 `Return to Previous` 等）保持英文存储数据，**不**做种子级本地化（它们是可改名的持久化数据；切语言不回溯改名已存数据，属预期）。新建项默认名走 `String(localized:)` 仅影响新建那一刻取的默认值。
- 免重启热切换（swizzle Bundle）——明确不做。
- 其它语言（日/韩/欧语等）、地区格式（日期/数字）专门适配——本期只做简/繁/英三语 UI 文案。
- App 显示名 / 菜单栏图标 / Info.plist 展示名本地化——不在本期。

## Technical Notes
- **String Catalog 写回**：先建 catalog（可先空），构建后视 `xcodebuild` 是否自动抽取 key 决定是否手填；若不自动抽取则按源字面量手写 key（缺译只回退英文、不会 build 失败）。验证靠真机分语言运行目视。
- **`String(localized:)` 与 SwiftUI `Text("…")` 同表**：默认表名 `Localizable`，共用 `Localizable.xcstrings`。
- **Models 约束**：`String(localized:)` 是 Foundation API，`ActivationConfig.swift` 仍只 `import Foundation`，不破坏 nonisolated / no-AppKit-SwiftUI。
- **重启时序**：`UserDefaults.standard.synchronize()` 必须在拉新实例前调用，否则新实例可能读到旧 `AppleLanguages`。
- **验证命令**：
  ```bash
  cd Relay
  xcodebuild -scheme Relay -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
  xcodebuild test -scheme Relay -only-testing:RelayTests -destination 'platform=macOS'
  ```
- 涉及文件：新增 `Localizable.xcstrings` / `UI/PersonalizationSettingsView.swift` / `Services/LanguageService.swift`；改 `SettingsRootView.swift` / `RelayApp.swift` / `AppController.swift` / `Models/ActivationConfig.swift` / `UI/BindingsDetailView.swift` / `UI/ShortcutRecorder.swift` / `UI/ProfilesView.swift` / `UI/GeneralSettingsView.swift` / `Relay.xcodeproj/project.pbxproj`（knownRegions）。
