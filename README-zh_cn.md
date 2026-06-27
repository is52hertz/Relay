<!--
README-zh_cn.md — 简体中文版本，与 README.md（英文权威源）同结构、同信息。
-->

<p align="right">
  <a href="README.md">English</a> ·
  <b>简体中文</b> ·
  <a href="README-zh_tw.md">繁體中文</a>
</p>

> **由 AI 构建，由人来执导。**
> Relay 由 AI 编码助手端到端开发，开发者担任 **创意总监与 QA**。
> `AGENTS.md`、`CLAUDE.md` 以及 `.trellis/` 工作流目录都是 **有意提交** 的——这是一个学习项目。欢迎阅读、fork、提 PR。

<br />

<p align="center">
  <img src="docs/icon.png" alt="Relay 图标" width="180" />
</p>

<h1 align="center">Relay</h1>

<p align="center">
  一款原生 macOS 全局 App 切换器——类 Thor——<br/>
  以场景化的 <b>配置（Profiles）</b> 管理全局热键，常驻菜单栏。
</p>

<p align="center">
  <a href="https://github.com/is52hertz/Relay/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/is52hertz/Relay?sort=semver&display_name=tag&include_prereleases" /></a>
  <a href="https://github.com/is52hertz/Relay/releases"><img alt="downloads" src="https://img.shields.io/github/downloads/is52hertz/Relay/total" /></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-15%2B-000?logo=apple&logoColor=white" />
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-555" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white" />
  <img alt="license" src="https://img.shields.io/badge/license-GPL--3.0-success" />
</p>

<p align="center">
  <a href="https://github.com/is52hertz/Relay/releases/latest"><b>⬇️ 下载最新 .dmg</b></a>
</p>

---

## Relay 是什么？

Relay 是一款原生 macOS 全局 **应用切换器**，理念上类似 Thor。你为某个目标 App 绑定一个全局热键，
这个热键会根据该 App 当前的运行状态，去启动、聚焦、隐藏它，或把你切回上一个 App。绑定按 **配置
（Profiles）** 分组（例如 *Coding*、*Design*、*Writing*），于是你可以为不同工作流一次性切换一整组
热键。任一时刻，只有 **已启用的配置** 的热键会被注册。

它是一个小巧的、单用户的 **菜单栏 agent**，只有一份本地小数据集。一切都留在你的 Mac 上：**无账号、
无网络、无遥测**。它以 un-sandboxed 方式运行（因为要控制其它 App），使用个人 Apple Development
证书签名，面向本地 / 自用——**不** 上架 Mac App Store。

---

## ✨ 功能

- 🗂️ **场景化配置（热键组）**——按工作流把绑定分组，一次切换一整组。任一时刻只有 **已启用的配置**
  的热键被注册。
- ⌨️ **全局热键**——经 Carbon `RegisterEventHotKey`（通过
  [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) 包）注册。热键本身
  **不需要辅助功能 / 输入监控权限**。内置录制器在录制时会临时禁用全局热键，让组合键被录下而不是被触发。
  同一配置内的重复组合会被检测并标记。
- 🎯 **按运行状态的激活行为**——一个「行为」是一份具名、可复用的映射：把目标 App 的运行状态映射到要执行
  的动作。绑定按名称引用行为；改一次行为，所有引用它的绑定都会一起更新。

  | 目标 App 状态 | 可选动作 |
  |---|---|
  | **未运行** | 启动并聚焦 · 在后台启动 · 不做任何操作 |
  | **后台运行** | 聚焦 · 显示但不聚焦 · 最小化 |
  | **当前最前** | 返回上一个 · 隐藏 · 退出 · 最小化 · 不做任何操作 |

- 🔁 **返回上一个**——当目标 App 已经在最前时，Relay 会把你切回刚才所在的那个 App（深度 2 的 MRU，
  类似 ⌘-Tab），通过监听 App 激活事件来跟踪。
- 🧩 **控制其它 App 只用公开 AppKit**——用 `NSWorkspace.openApplication` 来启动 / 聚焦 / 切回上一个，
  用 `NSRunningApplication.hide() / unhide()` 来隐藏 / 显示。不用私有 API，不用 event tap。
- 🪟 **管理窗口**——配置侧边栏（键盘导航、内联重命名、active 高亮）、绑定详情，以及全局快捷键录制。
- 📋 **菜单栏 agent**——常驻菜单栏；可选开启 Dock 图标。
- ⚙️ **设置**——*通用*（经 `SMAppService` 登录时启动、在 Dock 中显示图标）与 *个性化*（界面语言：
  跟随系统 / 简体中文 / 繁體中文 / English，切换后重启生效）。
- 🪟 **可选的「最小化」经辅助功能**——最小化目标窗口是一项受权限约束的能力，**首次使用时才懒申请**
  辅助功能权限，**绝不在启动时申请**。未授权时 App 照常可用；只有「最小化」会安全降级并给出一次性提示。

---

## 💻 运行要求

- **Apple Silicon** Mac
- **macOS 15（Sequoia）或更高版本**

---

## 📦 安装

1. 从 [Releases](https://github.com/is52hertz/Relay/releases/latest) 下载 `Relay-vX.Y.Z.dmg` 并打开。
2. 把 **Relay** 拖到 **应用程序（Applications）**。
3. **首次打开（重要）**：此版本用个人 Apple Development 证书签名、**未做公证**，Gatekeeper 会拦截。
   请 **右键点按** App → **打开** → **打开**。若仍被拒绝，在「终端」执行一次：
   ```sh
   xattr -dr com.apple.quarantine /Applications/Relay.app
   ```

---

## 🚀 使用

- Relay 常驻 **菜单栏**。打开菜单，选择打开 **管理窗口**。
- 在窗口里 **新建一个配置**，向它添加一个目标 App，然后为该绑定 **录制一个全局热键**，并选择（或新建）
  一个 **激活行为**。
- 在任何地方触发你的热键——Relay 会根据目标 App 当前的运行状态去启动 / 聚焦 / 隐藏 / 切回。
- **切换配置** 即可为不同工作流换上一整组不同的热键。
- 在 **设置 › 个性化** 里更改 **界面语言**（App 会重启以应用）。
- 在 **设置 › 通用** 里切换 **登录时启动** 和 **Dock 图标**。

---

## 🛠 从源码构建

**要求：** Xcode 26，运行在 macOS 26.5+ 主机（Apple Silicon）上。

```sh
git clone https://github.com/is52hertz/Relay.git
cd Relay
open Relay/Relay.xcodeproj      # 用 Xcode 26 打开后 ⌘R
```

或使用命令行：

```sh
xcodebuild -project Relay/Relay.xcodeproj -scheme Relay -configuration Release -destination 'generic/platform=macOS' build
```

> **App 沙盒被有意关闭**（`ENABLE_APP_SANDBOX = NO`），因为 Relay 需要启动并激活其它任意 App。
> Hardened Runtime 开启；以菜单栏 agent 形态发布（`LSUIElement = YES`）。

---

## 🔐 权限说明

- **全局热键不需要任何特殊权限。** 它们走 Carbon `RegisterEventHotKey`——不需要辅助功能、不需要输入监控、
  不用 `CGEventTap`、不用全局事件监视器。
- **「最小化」是唯一受权限约束的功能。** 它使用辅助功能，并且 **在你第一次真正用到它时才懒申请**——绝不在
  启动时申请。未授权时 App 仍完全可用，只有「最小化」不可用，并会安全降级、给出一次性提示。

---

## 🕵️ 隐私

无网络、无账号、无遥测。你的配置——几个配置和绑定——以 Codable JSON 的形式本地存放在 Application
Support 里（原子写、去抖保存）。任何数据都不会离开你的 Mac。

---

## 🤖 AI 原生开发

本仓库是 **AI 原生开发** 的一个实例。助手所需的上下文都被 **有意提交**：

| 文件 / 目录 | 用途 |
|---|---|
| `AGENTS.md` | **唯一权威源**——产品规则、编码规范、范围纪律、提交策略。 |
| `CLAUDE.md` | 各工具入口（指向 `AGENTS.md` 的符号链接）。 |
| `.trellis/` | 任务工作流：PRD、规范，以及驱动每次改动的逐任务上下文。 |

> 由 AI 构建，由人来执导。欢迎阅读这些文件、fork 本仓库，研究它是怎么做出来的。

---

## 📜 许可

以 **GNU 通用公共许可证 v3.0**（GPL-3.0）发布。

> 为什么选 GPL？这个项目的存在是为了教学。GPL 保证衍生作品——包括 AI 生成的 fork——保持开放，让下一个
> 学习者也能研究它们。如果你在它之上做了东西，请回馈出来。

Copyright (C) 2026 Teethe。完整文本见 [`LICENSE`](LICENSE)。
