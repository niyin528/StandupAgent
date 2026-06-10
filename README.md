# 早会 Agent — Mac App

[![Download](https://img.shields.io/github/v/release/niyin528/StandupAgent?label=下载最新版&logo=apple)](https://github.com/niyin528/StandupAgent/releases/latest)

早上起来头脑一片空白？打开它，AI 会自动把你的本周目标拆解成今天能做的事，帮你立刻找回状态、专注行动。

一个住在菜单栏的早会提醒 + AI 引导对话 App，支持 Claude、ChatGPT、Gemini、DeepSeek 多种 AI 服务。

## 功能

- 👥 **菜单栏常驻**，不占 Dock
- 🔔 **定时系统通知**：到点提醒，支持「现在开始」或「推迟 10 分钟」
- 📝 **本周目标管理**：在设置里写下这周要做什么，AI 记住它们
- 🤖 **AI 早会引导**：开会时 AI 主动帮你聚焦今天的优先事项，流式回复
- 🔀 **多 AI 服务支持**：可在 Claude、ChatGPT（OpenAI）、Gemini、DeepSeek 之间自由切换

## 环境要求

- macOS 14.0+
- 至少一个 AI 服务的 API Key：
  - **Claude**：在 [console.anthropic.com](https://console.anthropic.com) 获取
  - **ChatGPT**：在 [platform.openai.com](https://platform.openai.com) 获取
  - **Gemini**：在 [aistudio.google.com](https://aistudio.google.com) 获取
  - **DeepSeek**：在 [platform.deepseek.com](https://platform.deepseek.com) 获取
- Xcode 15+ （如需从源代码编译）

首次运行后：
1. 点击菜单栏的 👥 图标 → **设置**
2. 选择 AI 服务（Claude / ChatGPT / Gemini / DeepSeek），填入对应的 API Key
3. 设置早会时间（默认 09:00）
4. 在「本周目标」标签页添加这周要做的事

## 如何用 Xcode 编译运行项目

```bash
# 1. 用 Xcode 打开项目
open StandupAgent.xcodeproj

# 2. 选择 My Mac 作为 Run Destination

# 3. ⌘R 运行
```

## 项目结构

```
StandupAgent/
├── StandupAgentApp.swift      # App 入口、菜单栏、通知、定时器
├── Models/
│   └── AppSettings.swift      # 设置存储、WeeklyGoal 模型、Context 构建
├── Services/
│   └── LLMService.swift       # AI API 调用（支持 Claude / OpenAI / Gemini / DeepSeek，SSE 流式）
└── Views/
    ├── StandupView.swift       # 早会对话界面
    └── SettingsView.swift      # 设置 + 目标管理界面
```

## 自定义 AI 的引导风格

在 `LLMService.swift` 里修改 `systemPrompt`，可以调整 AI 的引导风格（对所有 provider 生效）：

```swift
private let systemPrompt = """
你是一个专注、高效的早会引导 Agent。
// 在这里修改引导方式...
"""
```

## 常见问题

**通知不显示？**
系统偏好设置 → 通知与专注模式 → 找到 StandupAgent → 允许通知

**API 调用失败？**
检查所选 AI 服务的 API Key 是否正确，以及网络是否能访问对应的 API 端点（`api.anthropic.com` / `api.openai.com` / `generativelanguage.googleapis.com` / `api.deepseek.com`）

**想让 App 开机自启？**
系统设置 → 通用 → 登录项目 → 添加 StandupAgent.app

## 开发调试

**杀掉、重新构建并重启 App（只驻留菜单栏，不弹主界面）：**

保留终端 stdout 日志，适合排查打印输出。启动后需要点菜单栏的 ☕ → "开始早会" 才能看到主界面。

```bash
killall StandupAgent 2>/dev/null; xcodebuild -project StandupAgent.xcodeproj -scheme StandupAgent -configuration Debug build 2>&1 | tail -3 && sleep 0.3 && ~/Library/Developer/Xcode/DerivedData/StandupAgent-*/Build/Products/Debug/StandupAgent.app/Contents/MacOS/StandupAgent &
```

**杀掉、重新构建并重启 App，并自动打开早会主界面：**

通过 `--open-standup` 启动参数让 App 启动后直接弹出早会窗口，适合快速预览 UI。

```bash
killall StandupAgent 2>/dev/null; xcodebuild -project StandupAgent.xcodeproj -scheme StandupAgent -configuration Debug build 2>&1 | tail -3 && sleep 0.3 && open ~/Library/Developer/Xcode/DerivedData/StandupAgent-*/Build/Products/Debug/StandupAgent.app --args --open-standup
```

---

# Standup Agent — Mac App

Ever wake up with a blank mind, not sure where to begin? Open this app and the AI breaks your weekly goals down into concrete things you can actually do today — so you can get focused and moving in seconds.

A menu bar standup reminder + AI-guided conversation app for macOS, supporting Claude, ChatGPT, Gemini, and DeepSeek.

## Features

- ☕ **Lives in the menu bar** — no Dock icon
- 🔔 **Scheduled system notifications** — reminds you at standup time with "Start Now" or "Snooze 10 min"
- 📝 **Weekly goal tracking** — write down what you want to accomplish this week; the AI keeps them in context
- 🤖 **AI-guided standup** — the AI proactively helps you focus on today's priorities with streaming responses
- 🔀 **Multi-provider support** — freely switch between Claude, ChatGPT (OpenAI), Gemini, and DeepSeek

## Requirements

- macOS 14.0+
- An API Key for at least one AI provider:
  - **Claude**: get one at [console.anthropic.com](https://console.anthropic.com)
  - **ChatGPT**: get one at [platform.openai.com](https://platform.openai.com)
  - **Gemini**: get one at [aistudio.google.com](https://aistudio.google.com)
  - **DeepSeek**: get one at [platform.deepseek.com](https://platform.deepseek.com)
- Xcode 15+ (if building from source)

On first launch:
1. Click the ☕ icon in the menu bar → **Settings**
2. Choose your AI provider (Claude / ChatGPT / Gemini / DeepSeek) and enter the corresponding API Key
3. Set your standup time (default: 09:00)
4. Add this week's goals in the "Weekly Goals" tab

## How to build and run with Xcode

```bash
# 1. Open the project in Xcode
open StandupAgent.xcodeproj

# 2. Select "My Mac" as the Run Destination

# 3. Press ⌘R to run
```

## Project Structure

```
StandupAgent/
├── StandupAgentApp.swift      # App entry, menu bar, notifications, timer
├── Models/
│   └── AppSettings.swift      # Settings storage, WeeklyGoal model, context builder
├── Services/
│   └── LLMService.swift       # AI API calls (Claude / OpenAI / Gemini / DeepSeek, SSE streaming)
└── Views/
    ├── StandupView.swift       # Standup chat UI
    └── SettingsView.swift      # Settings + goal management UI
```

## Customizing the AI Persona

Edit `systemPrompt` in `LLMService.swift` to change the AI's coaching style (applies to all providers):

```swift
private let systemPrompt = """
You are a focused, efficient standup facilitator Agent.
// Modify the guidance style here...
"""
```

## FAQ

**Notifications not showing?**
System Preferences → Notifications & Focus → StandupAgent → Allow Notifications

**API call failing?**
Check that the API Key for your selected provider is correct and that your network can reach the corresponding endpoint (`api.anthropic.com` / `api.openai.com` / `generativelanguage.googleapis.com` / `api.deepseek.com`)

**Want the app to launch at login?**
System Settings → General → Login Items → Add StandupAgent.app

## Development & Debugging

**Kill, rebuild, and relaunch (menu bar only, no main window):**

Keeps stdout logs in the terminal — useful for debugging print output. After launch, click ☕ → "Start Standup" to open the main window.

```bash
killall StandupAgent 2>/dev/null; xcodebuild -project StandupAgent.xcodeproj -scheme StandupAgent -configuration Debug build 2>&1 | tail -3 && sleep 0.3 && ~/Library/Developer/Xcode/DerivedData/StandupAgent-*/Build/Products/Debug/StandupAgent.app/Contents/MacOS/StandupAgent &
```

**Kill, rebuild, and relaunch with the standup window open automatically:**

Uses the `--open-standup` launch argument to open the standup window immediately — handy for quick UI previews.

```bash
killall StandupAgent 2>/dev/null; xcodebuild -project StandupAgent.xcodeproj -scheme StandupAgent -configuration Debug build 2>&1 | tail -3 && sleep 0.3 && open ~/Library/Developer/Xcode/DerivedData/StandupAgent-*/Build/Products/Debug/StandupAgent.app --args --open-standup
```
