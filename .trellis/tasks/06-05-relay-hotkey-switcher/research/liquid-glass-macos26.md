# Research: macOS 26 Liquid Glass — Relay UI

Verified 2026-06-05 via Apple Docs MCP（符号确认存在）。

## 确认存在的公开 API（符号名属实，非臆造）
- SwiftUI 修饰符：
  - `glassEffect(_:in:isEnabled:)` — 给自定义视图加玻璃。
  - `glassEffectID(_:in:)` — 配合 `@Namespace` 做形变过渡。
  - `glassEffectTransition(_:isEnabled:)`。
  - `glassEffectUnion(id:namespace:)` — 合并多个玻璃形状。
  - `GlassEffectContainer`（容器，分组玻璃元素以正确混合）。
  - 按钮：`.buttonStyle(.glass)` / `.glassProminent`（写码时确认确切拼写）。
- AppKit：`NSGlassEffectView`（含 `NSGlassEffectView.Style`）。

## 关键设计判断
- 目标 26.5 → **Liquid Glass 全可用，零 fallback**。
- **不要手抹玻璃**：标准容器在链接 26 SDK 后**自动**采用 Liquid Glass：
  - `NavigationSplitView` 侧栏、`.toolbar`、`List`/`Form`、`sheet`、`MenuBarExtra`。
- **v1 不主动用 `.glassEffect`**：Relay 是工具类（菜单栏 + 设置窗），靠系统自动玻璃化即可。
  - 仅当后续做「类 Spotlight 浮层快速切换面板」才考虑 `GlassEffectContainer`+`glassEffect`。
- 内容层不要玻璃；玻璃只属于导航/控件层（HIG 指引）。

## 可访问性/适配（系统控件免费获得）
- 深浅色：系统材质自动适配，勿硬编码颜色，用语义色 / `Color.primary` 等。
- VoiceOver/键盘导航：用标准控件即得；图标按钮补 `.accessibilityLabel`。
- 降级：本项目无需（仅 26.5）。若未来降目标，自定义玻璃需 `if #available(macOS 26, *)` 包裹并回退到 `Material`/`.background`。

## 待写 UI 时再核对（非阻断）
- `.buttonStyle(.glass)` / `.glassProminent` 确切拼写与可用性。
- MenuBarExtra `.menu` vs `.window` 风格在 26 下的玻璃表现。
