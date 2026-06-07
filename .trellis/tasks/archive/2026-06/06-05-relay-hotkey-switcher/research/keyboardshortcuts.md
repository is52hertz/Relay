# Research: KeyboardShortcuts (Sindre Sorhus) — Relay 集成

Verified 2026-06-05 via Context7 `/sindresorhus/keyboardshortcuts` (rep High, 107 snippets) + GitHub readme.

## 包信息
- SPM: `https://github.com/sindresorhus/KeyboardShortcuts`，min macOS 10.15+（远高于我们 26.5 目标，安全）。MIT。
- 底层 Carbon `RegisterEventHotKey`：**无需 Accessibility/Input Monitoring**，沙箱内可用。

## 确认可用的 API（写码即用）
```swift
// Shortcut 构造与字段（我方 Hotkey ↔ Shortcut 互转的依据）
KeyboardShortcuts.Shortcut(.t, modifiers: [.command, .shift])         // Key + NSEvent.ModifierFlags
KeyboardShortcuts.Shortcut(carbonKeyCode: Int, carbonModifiers: Int) // 由 carbon 码构造
shortcut.carbonKeyCode      // Int
shortcut.carbonModifiers    // Int
shortcut.key?.rawValue      // Key?
shortcut.modifiers          // NSEvent.ModifierFlags
KeyboardShortcuts.Shortcut(event: NSEvent)  // 从事件构造
shortcut.toSwiftUI          // -> SwiftUI.KeyboardShortcut

// 程序化读写（我们用它把 active profile 的快捷键推入库）
KeyboardShortcuts.setShortcut(_ shortcut: Shortcut?, for name: Name)  // nil=清除
KeyboardShortcuts.getShortcut(for name: Name) -> Shortcut?
name.shortcut  // 可读写属性

// 启用/禁用（profile 切换用；不删除存储，仅停用）
KeyboardShortcuts.disable(_ names: Name...)
KeyboardShortcuts.enable(_ names: Name...)
KeyboardShortcuts.isEnabled(for: Name) -> Bool
KeyboardShortcuts.isEnabled = false   // 全局总开关

// 触发回调
KeyboardShortcuts.onKeyDown(for: Name) { ... }   // 可多 handler
KeyboardShortcuts.onKeyUp(for: Name) { ... }
```

## 动态 Name
- Name 支持运行时构造：`KeyboardShortcuts.Name(rawValue)` / `Self(String)`，readme 明确「可动态创建并自行存储」。
- Relay 用法：每个 binding 一个 `Name(binding.id.uuidString)`。

## SwiftUI Recorder（两种模式，决定我们用哪种）
```swift
// (A) Name 模式：自动注册全局热键 + 自动持久化到 UserDefaults + 自带「与系统/主菜单冲突」警告
KeyboardShortcuts.Recorder("Label:", name: .someName)

// (B) Binding 模式：写入我方 State/Model；【关键】不自动注册全局热键、也不写 UserDefaults
KeyboardShortcuts.Recorder("Label:", shortcut: $shortcut)  // $shortcut: Binding<Shortcut?>
```

## Relay 的集成决策（据上确认）
- **SoT = 我方 JSON 的 `Hotkey{carbonKeyCode,carbonModifiers}`**；UI 用 **Binding 模式 Recorder**（不自动注册、不双写 UserDefaults），把录入结果转成我方 `Hotkey` 存进 model。
- **注册只针对 active profile**：对每个有热键的 binding → `Name(id)` + `setShortcut(Shortcut(carbonKeyCode:carbonModifiers:), for:)` + `onKeyDown{ activation.handle(binding) }`。
- **profile 切换**：对旧组 `setShortcut(nil, for:)`（或 `disable`）解除；对新组 set+enable。setShortcut 会写库自身的 UserDefaults，仅作运行态载体，非我方 SoT，下次启动由 JSON 重推。
- handler 稳定性：每个 Name 保持一个 handler，内部按当前 active binding 取动作；清空 shortcut 即不再触发，无需复杂反注册。（`removeAllHandlers()` 是否公开**写码时再确认**，非阻断。）

## 冲突检测（落实 P1-11）
- ✅ **组内重复**：我们对 active profile 的 `Hotkey` 自行比较，可靠、与库无关。
- ⚠️ **系统/他应用占用**：库**不暴露注册失败的程序化错误**（内部 Carbon 注册失败仅 log）。Recorder 仅对「系统快捷键 + 本 App 主菜单」做静态警告，**无法**程序化判定「被另一运行中 App 占用」。→ ② 为 best-effort：依赖 Recorder 内置警告 + 我们的兜底文案「可能被占用/未生效」。**不臆造**注册失败 API。

## 风险/待写码确认（非阻断）
- `removeAllHandlers(for:)`/`removeAllHandlers()` 的确切签名。
- 大量动态 Name 同时 set 的开销（预计可忽略；Carbon 注册是廉价系统调用）。
