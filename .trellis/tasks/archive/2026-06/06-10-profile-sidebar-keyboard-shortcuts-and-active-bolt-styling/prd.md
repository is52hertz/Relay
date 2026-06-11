# Profile sidebar keyboard shortcuts and active-bolt styling

## Goal

给 Profiles 侧栏列表加键盘操作，并改善 active 闪电图标在选中态下的可见性与尺寸：
- 选中某 Profile 后，用键盘删除 / 改名 / 设为 active。
- 选中行整体变蓝时，蓝色 `bolt.fill` 看不清 → 选中时闪电改白色。
- 整体调大闪电图标。

## What I already know

- `ProfilesView`(`UI/ProfilesView.swift`)：`List(selection: $selectedProfileID)`，行 = `ProfileRow(name:isActive:)`。
- `ProfileRow` 闪电：`Image(systemName: "bolt.fill").font(.caption).foregroundStyle(.tint)` —— `.tint`(蓝) + `.caption`(小)。行当前**不感知是否被选中**。
- rename 现走 `.alert`（TextField + Rename/Cancel）；delete 现为**即时删除**（context menu Delete → `model.deleteProfile`，无二次确认）。
- 已有 context menu：Set as Active / Rename… / Delete。
- 标准 macOS SwiftUI 键盘 API：`.onDeleteCommand`（List 聚焦时 Delete/Backspace 触发）、`.onKeyPress(.return)`。macOS 26.5 可用。

## Assumptions (temporary)

- 闪电变白只在「该行被选中」时；未选中行仍用 `.tint`（蓝）。
- 删除键 = 即时删除选中 Profile（与现有 context menu Delete 行为一致，不加二次确认）。
- 闪电放大到与行文字相称（如 `.body`/`.headline` 量级），具体值实现时定。

## Confirmed decisions (this turn)

- **Return 键语义（双击 Return 计时消歧）**[user]：
  - 选中行按 Return → **立即**进入行内改名（无延迟，文字选中）。
  - 改名开始后 **~300ms 窗口内再按一次 Return** → 取消本次改名 + 设为 active（即"两次 Return 激活"）。
  - 窗口外按 Return → 正常提交改名。
  - **⌘Return** → 直接设为 active（不进改名）。
- **rename 改为行内编辑**[self,需user默认认可]：为让第二次 Return 能被聚焦的改名输入接住并按计时区分，rename 从现有 `.alert` 改成 Finder 式行内 TextField（聚焦 + 选中文字 + onSubmit 提交）。
- 已知小代价：进改名后 300ms 内提交未改动的名字会被判为"激活"——即双击 Return 手势本身，可接受。
- **闪电最终样式**[user]：尺寸 `.font(.body)`（用户在真机调定，去掉 imageScale）；颜色 `isSelected ? .white : .tint`。曾试 `@Environment(\.backgroundProminence)` 想让"按下即白"同步，但该 List 里它不变 `.increased`、闪电完全不变白，故**回退到 `isSelected`**；长按未释放瞬间的白色延迟为已知小代价，用户接受。
- **Profiles context menu 显示快捷键提示**[user]：三个 Button 加 `.keyboardShortcut` 仅作 NSMenu 提示字形（Set as Active `⌘↩` / Rename… `↩` / Delete `⌫`），实际按键仍由 `.onKeyPress`/`.onDeleteCommand`/隐藏 ⌘Return 按钮处理。
- **绑定行（BindingsDetailView）也加删除键 + 菜单提示**[user]：详情绑定列表支持选中某行 → Delete 键删除；`BindingRow` 的 "Remove" context menu 加 `⌫` 提示。
- **侧栏背景玻璃模糊度**：用户曾提"调清晰点"，但 NavigationSplitView sidebar 材质需覆盖系统 glass（与"依赖自动 Liquid Glass、勿手搓"张力）且落地不确定 → **本次放弃，不做**。[user]

## Requirements (evolving)

- 选中 Profile 后：
  - Delete/Backspace → 删除该 Profile（即时，与 context menu 一致）。
  - Return → 行内改名；300ms 内二次 Return → 取消改名 + 设 active。
  - ⌘Return → 设为 active。
- rename 改为行内编辑（替换 `.alert`）。
- `ProfileRow` 感知选中态：选中时 `bolt.fill` 用白色，未选中用 `.tint`；尺寸 `.font(.body)`。
- Profiles context menu 三项显示快捷键提示字形。
- **绑定行**：`BindingsDetailView` 列表加选中 + `.onDeleteCommand` 删除选中绑定；`BindingRow` "Remove" 加 `.keyboardShortcut(.delete, modifiers: [])` 提示。

## Acceptance Criteria (evolving)

- [ ] 侧栏聚焦、选中某 Profile 时，Delete 键删除该 Profile。
- [ ] 键盘可触发 rename 与 set-active（键位按决策）。
- [ ] 选中行的 active 闪电为白色、清晰可见；未选中行闪电为 tint 蓝。
- [ ] 闪电图标尺寸明显增大。
- [ ] Profiles 右键菜单显示 ⌘↩ / ↩ / ⌫ 提示字形。
- [ ] 绑定列表选中某行 → Delete 删除该绑定；"Remove" 菜单显示 ⌫ 提示。
- [ ] 构建 + RelayTests 通过。

## Definition of Done

- 构建 / 测试通过。
- 行为改动若影响 UI 约定则同步 `.trellis/spec/ui/swiftui.md` / notice。

## Out of Scope (explicit)

- 绑定行仅加「选中 + Delete 删除 + Remove 菜单 ⌫ 提示」；不动其录入器 / 配置选择器 / 排序等其它交互。
- 不动 Add Profile / 侧栏布局（上一任务已定）。
- 侧栏背景玻璃模糊度——本次放弃（见 Confirmed decisions）。

## Technical Notes

- 文件：`UI/ProfilesView.swift`（`ProfilesView` + `ProfileRow`）。
- 删除：`.onDeleteCommand`；改名/激活：`.onKeyPress(.return)` 或专用键位（待决策）。
- 选中态传入 `ProfileRow`：`isSelected: profile.id == selectedProfileID`。
