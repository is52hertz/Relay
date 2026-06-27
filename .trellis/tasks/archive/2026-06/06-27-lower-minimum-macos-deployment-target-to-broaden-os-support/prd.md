# Lower minimum macOS deployment target (broaden OS support)

## Goal

把 Relay 的最低 macOS 从 `26.5` 降到 **macOS 14.0**，让更多系统能装能跑，同时保留现有 SwiftUI-first 架构（@Observable / MenuBarExtra / Window / SMAppService 全部不动）。

## Decision (ADR-lite)

**Context**: owner 希望尽可能广地支持旧系统（原话"至少 12.7"）。research（`research/macos-deployment-floor-analysis.md`）查明：
- 依赖 KeyboardShortcuts 2.4.0 最低 10.15，不挡路；卡点是 Relay 自身架构。
- 真实有效地板今天是 **15.0**（仅一个 scene 修饰符 `defaultLaunchBehavior(.suppressed)`），其余 ≤14。
- 13 需 @Observable→ObservableObject 全量迁移（~16 文件）；12.7 需重写 AppKit 外壳（MenuBarExtra/Window/SMAppService），≈ 推翻核心设计。

**Decision（最终）**: 目标定 **macOS 15.0**。12.7/13 否决；14 也放弃——原因见下两条构建期发现。
**构建期发现（research 静态扫描漏判，以真实构建为准）**:
1. **SceneBuilder 不支持控制流、且 SwiftUI 无 `AnyScene` 类型擦除** → `defaultLaunchBehavior(.suppressed)`（15+）
   无法「只在 15+ 条件应用」。要么保留（最低=15），要么彻底删除（才能到 14）。owner 选保留 → **15**。
2. 真实构建（target 15）报出 research 漏掉的 `ToolbarSpacer(.flexible)`（**macOS 26 API**，ProfilesView.swift）。
   toolbar builder 支持控制流，已 `if #available(macOS 26.0, *)` 守卫，旧系统降级为默认按钮位置（仅外观）。
**Consequences**: 覆盖 Sequoia 15 / macOS 26；对 owner 的 26.5 机器**行为零变化**（两个 >15 API 在 26 上仍原样生效）；
放弃 14/13/12.x。代码改动＝pbxproj 4 块 + ToolbarSpacer 一处守卫。

## Requirements (locked)

1. `MACOSX_DEPLOYMENT_TARGET`：`26.5 → 14.0`（project.pbxproj 的 4 个 build-config 块）。
2. `RelayApp.swift` 两处 `.defaultLaunchBehavior(.suppressed)`（行 36、50，macOS 15+）→ 用 `@SceneBuilder` 可用性守卫，仅 15+ 应用；14 走系统默认。
   - 该修饰符负重：两个 Window 是 secondary 场景（主场景是 MenuBarExtra，窗口经 openWindow 程序化开），全新启动一般不自动弹；它主要抑制"状态恢复重开窗"。14 上退化为系统默认（可接受）。
3. 在 macOS 26.5 SDK 下以 target 14 实际构建，修掉任何 >14 的残留可用性编译错误（research 静态扫描仅发现上面一个，但以真实构建为准）。
4. 同步"最低系统"对外表述（本任务即在改这个数）：
   - `.github/workflows/release.yml` release body：`macOS 26.5+ → macOS 14+`。
   - README.md / README-zh_cn.md / README-zh_tw.md：运行时要求与徽章 `macOS 26+ → macOS 14+`（**不动**"Build from source"的 Xcode 26 / 26.5 主机构建要求——那仍成立）。
   - 根 `notice.md`：补记最低系统与"为何 ci.yml 仍 build-only"的口径（见下）。

## Acceptance Criteria

- [ ] `xcodebuild -showBuildSettings` 显示 `MACOSX_DEPLOYMENT_TARGET = 14.0`（4 块全改）。
- [ ] 以 target 14 构建成功（macOS 26.5 SDK，未签名）。
- [ ] `defaultLaunchBehavior` 仅在 15+ 生效，14 编译通过且无该 API 的可用性报错。
- [ ] README（三语）+ release body 的最低系统已更新为 14。
- [ ] CI（ci.yml/release.yml）仍绿。

## Out of Scope

- 降到 13 / 12.7（已否决）。
- 把 @Observable 改 ObservableObject、重写 AppKit 外壳。
- 在 CI 启用单测（见风险）——目标降到 14 后托管 26.x runner 理论上可跑宿主单测，但属相邻改动，单列后续。

## Risks / Notes

- **14 的运行时行为 CI 测不了**：托管 runner 是 macOS 26.x，无法在 14/13 上跑；降级后的实际行为（尤其窗口自动开/状态恢复、SF Symbol 回退）需 owner 在真机 14（或 13）抽验一次。
- 全代码**零 `@available` 守卫**：若真实构建在 14 下冒出二级可用性错误，按出现逐个 `if #available` 守卫或替换。
- 降到 14 后，"为何 CI 不跑单测"的旧理由（runner 26.4 < 部署目标 26.5）**不再成立**——宿主单测理论上可在 26.x runner 上跑（app min 14 ≤ 26.4）。本任务不动 ci.yml 的测试策略，仅在 notice 注明可作后续。

## Research References

- [`research/macos-deployment-floor-analysis.md`](research/macos-deployment-floor-analysis.md) — 地板=15.0(单修饰符)；依赖不挡路；14 甜点、13 中等、12.7≈重写；逐 API 版本表 + file:line。
