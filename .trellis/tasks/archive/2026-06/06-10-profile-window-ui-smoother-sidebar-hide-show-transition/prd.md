# Profile window UI: smoother sidebar hide/show transition

## Goal

改进 Profiles 主窗口（`ProfilesView`，`NavigationSplitView`）的侧栏显示/隐藏体验。当前点「hide sidebar」折叠时，侧栏头部的工具栏按钮（Add Profile ＋、系统侧栏折叠钮）会突兀地跳到红绿灯右侧并套上玻璃胶囊，内容区重排，动画衔接不自然。

## What I already know

- `ProfilesView`(`UI/ProfilesView.swift`)= 标准 `NavigationSplitView`，**未固定 columnVisibility**（默认可折叠，带系统 sidebarToggle）。
  - 侧栏 toolbar：`Add Profile`（ToolbarItem，plus）。
  - 详情 = `BindingsDetailView`：`navigationTitle(profile.name)` + `navigationSubtitle(Active/Inactive)`；detail toolbar：`Add App`（plus）+ `Set as Active`（bolt/bolt.fill）。
- 折叠时 leading 区按钮重排 + 玻璃胶囊浮现是 SwiftUI `NavigationSplitView` 折叠的固有表现。
- 对照组：`SettingsRootView` 用 `NavigationSplitView(columnVisibility: .constant(.doubleColumn))` + `.toolbar(removing: .sidebarToggle)` → **侧栏始终可见、无折叠按钮**，规避了该重排问题（System Settings 风格）。
- 主窗口定位：Profiles 管理为根，需保留 `Add Profile` 工具栏（住在 Window，不能进 Settings 场景）。

## Assumptions (temporary)

- 用户主要诉求是「折叠时不要那么生硬」，而非彻底重做 Profile UI。
- 主窗口偏向"工具型窗口"，侧栏是否可折叠是产品决策点。

## Confirmed decisions (this turn)

- 方向：**侧栏始终可见、去掉折叠按钮**（对齐 Settings 场景做法），彻底消除折叠时的工具栏跳变。[user]

- 范围：**仅改侧栏这一项**；其它 Profile UI 想法后续另开任务。[user]

## Open Questions

- (none — 范围与方向已确认)

## Requirements (evolving)

- Profiles 主窗口侧栏始终可见、不可折叠：`NavigationSplitView(columnVisibility: .constant(.doubleColumn))` + `.toolbar(removing: .sidebarToggle)`。
- `Add Profile` ＋ 工具栏保留在侧栏头部；详情 toolbar 不变。

## Acceptance Criteria (evolving)

- [ ] Profiles 主窗口侧栏始终可见，无系统侧栏折叠按钮。
- [ ] 不再出现折叠时工具栏按钮跳到红绿灯旁 / 玻璃胶囊浮现的突兀重排。
- [ ] `Add Profile` ＋ 仍在侧栏头部、详情 toolbar（Add App / Set as Active）不变。
- [ ] 构建 + RelayTests 通过。

## Definition of Done

- 构建 / 测试通过。
- 改动若影响窗口架构描述则同步 `Relay/notice.md`（本次仅侧栏可见性，预计无需）。

## Out of Scope (explicit)

- 其它 Profile UI 调整（布局/工具栏/空态/交互重做）——后续另开任务。
- 详情区（BindingsDetailView）行为不动。

## Technical Notes

- 文件：`UI/ProfilesView.swift`(主)；参考 `UI/SettingsRootView.swift` 的 `.constant(.doubleColumn)` + `.toolbar(removing: .sidebarToggle)` 处理。
- 详情 toolbar 在 `UI/BindingsDetailView.swift`。
