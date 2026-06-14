<!--
README-zh_tw.md — 繁體中文版本，與 README.md（英文權威源）同結構、同資訊。
-->

<p align="right">
  <a href="README.md">English</a> ·
  <a href="README-zh_cn.md">简体中文</a> ·
  <b>繁體中文</b>
</p>

> **由 AI 打造，由人來執導。**
> Relay 由 AI 編碼助手端到端開發，開發者擔任 **創意總監與 QA**。
> `AGENTS.md`、`CLAUDE.md` 以及 `.trellis/` 工作流目錄都是 **刻意提交** 的——這是一個學習專案。歡迎閱讀、fork、送 PR。

<br />

<p align="center">
  <img src="docs/icon.png" alt="Relay 圖示" width="180" />
</p>

<h1 align="center">Relay</h1>

<p align="center">
  一款原生 macOS 全域 App 切換器——類 Thor——<br/>
  以場景化的 <b>設定檔（Profiles）</b> 管理全域快捷鍵，常駐選單列。
</p>

<p align="center">
  <a href="https://github.com/is52hertz/Relay/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/is52hertz/Relay?sort=semver&display_name=tag&include_prereleases" /></a>
  <a href="https://github.com/is52hertz/Relay/releases"><img alt="downloads" src="https://img.shields.io/github/downloads/is52hertz/Relay/total" /></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-26%2B-000?logo=apple&logoColor=white" />
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-555" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white" />
  <img alt="license" src="https://img.shields.io/badge/license-GPL--3.0-success" />
</p>

<p align="center">
  <a href="https://github.com/is52hertz/Relay/releases/latest"><b>⬇️ 下載最新 .dmg</b></a>
</p>

---

## Relay 是什麼？

Relay 是一款原生 macOS 全域 **應用程式切換器**，理念上類似 Thor。你為某個目標 App 綁定一個全域快捷鍵，
這個快捷鍵會依據該 App 目前的執行狀態，去啟動、聚焦、隱藏它，或把你切回上一個 App。綁定按 **設定檔
（Profiles）** 分組（例如 *Coding*、*Design*、*Writing*），於是你可以為不同工作流一次切換一整組
快捷鍵。任一時刻，只有 **使用中的設定檔** 的快捷鍵會被註冊。

它是一個輕巧的、單一使用者的 **選單列 agent**，只有一份本地小型資料集。一切都留在你的 Mac 上：**無帳號、
無網路、無遙測**。它以 un-sandboxed 方式執行（因為要控制其它 App），使用個人 Apple Development 憑證
簽署，面向本地 / 自用——**不** 上架 Mac App Store。

---

## ✨ 功能

- 🗂️ **場景化設定檔（快捷鍵組）**——按工作流把綁定分組，一次切換一整組。任一時刻只有 **使用中的設定檔**
  的快捷鍵被註冊。
- ⌨️ **全域快捷鍵**——經 Carbon `RegisterEventHotKey`（透過
  [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) 套件）註冊。快捷鍵本身
  **不需要輔助使用 / 輸入監控權限**。內建錄製器在錄製時會暫時停用全域快捷鍵，讓組合鍵被錄下而不是被觸發。
  同一設定檔內的重複組合會被偵測並標記。
- 🎯 **依執行狀態的啟用行為**——一個「行為」是一份具名、可重複使用的對應：把目標 App 的執行狀態對應到要
  執行的動作。綁定以名稱引用行為；改一次行為，所有引用它的綁定都會一起更新。

  | 目標 App 狀態 | 可選動作 |
  |---|---|
  | **未執行** | 啟動並聚焦 · 在背景啟動 · 不做任何動作 |
  | **背景執行** | 聚焦 · 顯示但不聚焦 · 最小化 |
  | **目前最前** | 返回上一個 · 隱藏 · 結束 · 最小化 · 不做任何動作 |

- 🔁 **返回上一個**——當目標 App 已經在最前時，Relay 會把你切回剛才所在的那個 App（深度 2 的 MRU，
  類似 ⌘-Tab），透過監聽 App 啟用事件來追蹤。
- 🧩 **控制其它 App 只用公開 AppKit**——用 `NSWorkspace.openApplication` 來啟動 / 聚焦 / 切回上一個，
  用 `NSRunningApplication.hide() / unhide()` 來隱藏 / 顯示。不用私有 API，不用 event tap。
- 🪟 **管理視窗**——設定檔側邊欄（鍵盤導航、內嵌重新命名、active 突顯）、綁定詳情，以及全域快捷鍵錄製。
- 📋 **選單列 agent**——常駐選單列；可選開啟 Dock 圖示。
- ⚙️ **設定**——*一般*（經 `SMAppService` 登入時啟動、在 Dock 中顯示圖示）與 *個人化*（介面語言：
  跟隨系統 / 简体中文 / 繁體中文 / English，切換後重新啟動生效）。
- 🪟 **可選的「最小化」經輔助使用**——最小化目標視窗是一項受權限約束的能力，**首次使用時才延遲申請**
  輔助使用權限，**絕不在啟動時申請**。未授權時 App 照常可用；只有「最小化」會安全降級並給出一次性提示。

---

## 💻 執行需求

- **Apple Silicon** Mac
- **macOS 26.5 或更新版本**

---

## 📦 安裝

1. 從 [Releases](https://github.com/is52hertz/Relay/releases/latest) 下載 `Relay-vX.Y.Z.dmg` 並開啟。
2. 把 **Relay** 拖到 **應用程式（Applications）**。
3. **首次開啟（重要）**：此版本用個人 Apple Development 憑證簽署、**未做公證**，Gatekeeper 會攔截。
   請 **右鍵點按** App → **打開** → **打開**。若仍被拒絕，在「終端機」執行一次：
   ```sh
   xattr -dr com.apple.quarantine /Applications/Relay.app
   ```

---

## 🚀 使用

- Relay 常駐 **選單列**。打開選單，選擇開啟 **管理視窗**。
- 在視窗裡 **新建一個設定檔**，向它加入一個目標 App，然後為該綁定 **錄製一個全域快捷鍵**，並選擇（或新建）
  一個 **啟用行為**。
- 在任何地方觸發你的快捷鍵——Relay 會依據目標 App 目前的執行狀態去啟動 / 聚焦 / 隱藏 / 切回。
- **切換設定檔** 即可為不同工作流換上一整組不同的快捷鍵。
- 在 **設定 › 個人化** 裡更改 **介面語言**（App 會重新啟動以套用）。
- 在 **設定 › 一般** 裡切換 **登入時啟動** 與 **Dock 圖示**。

---

## 🛠 從原始碼建置

**需求：** Xcode 26，執行在 macOS 26.5+ 主機（Apple Silicon）上。

```sh
git clone https://github.com/is52hertz/Relay.git
cd Relay
open Relay/Relay.xcodeproj      # 用 Xcode 26 開啟後 ⌘R
```

或使用命令列：

```sh
xcodebuild -project Relay/Relay.xcodeproj -scheme Relay -configuration Release -destination 'generic/platform=macOS' build
```

> **App 沙盒被刻意關閉**（`ENABLE_APP_SANDBOX = NO`），因為 Relay 需要啟動並啟用其它任意 App。
> Hardened Runtime 開啟；以選單列 agent 形態發布（`LSUIElement = YES`）。

---

## 🔐 權限說明

- **全域快捷鍵不需要任何特殊權限。** 它們走 Carbon `RegisterEventHotKey`——不需要輔助使用、不需要輸入監控、
  不用 `CGEventTap`、不用全域事件監視器。
- **「最小化」是唯一受權限約束的功能。** 它使用輔助使用，並且 **在你第一次真正用到它時才延遲申請**——絕不在
  啟動時申請。未授權時 App 仍完全可用，只有「最小化」不可用，並會安全降級、給出一次性提示。

---

## 🕵️ 隱私

無網路、無帳號、無遙測。你的設定——幾個設定檔與綁定——以 Codable JSON 的形式本地存放在 Application
Support 裡（原子寫入、去抖儲存）。任何資料都不會離開你的 Mac。

---

## 🤖 AI 原生開發

本倉庫是 **AI 原生開發** 的一個實例。助手所需的上下文都被 **刻意提交**：

| 檔案 / 目錄 | 用途 |
|---|---|
| `AGENTS.md` | **唯一權威源**——產品規則、編碼規範、範圍紀律、提交策略。 |
| `CLAUDE.md` | 各工具入口（指向 `AGENTS.md` 的符號連結）。 |
| `.trellis/` | 任務工作流：PRD、規範，以及驅動每次改動的逐任務上下文。 |

> 由 AI 打造，由人來執導。歡迎閱讀這些檔案、fork 本倉庫，研究它是怎麼做出來的。

---

## 📜 授權

以 **GNU 通用公共授權條款 v3.0**（GPL-3.0）發布。

> 為什麼選 GPL？這個專案的存在是為了教學。GPL 保證衍生作品——包括 AI 生成的 fork——保持開放，讓下一個
> 學習者也能研究它們。如果你在它之上做了東西，請回饋出來。

Copyright (C) 2026 Teethe。完整文本見 [`LICENSE`](LICENSE)。
