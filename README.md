# 早会 Agent — Mac App

一个住在菜单栏的早会提醒 + Claude AI 引导对话 App。

## 功能

- ☕ **菜单栏常驻**，不占 Dock
- 🔔 **定时系统通知**：到点提醒，支持「现在开始」或「推迟 10 分钟」
- 📝 **本周目标管理**：在设置里写下这周要做什么，Claude 记住它们
- 🤖 **AI 早会引导**：开会时 Claude 主动帮你聚焦今天的优先事项，流式回复

## 环境要求

- macOS 14.0+
- Xcode 15+
- Claude API Key（在 [console.anthropic.com](https://console.anthropic.com) 获取）

## 快速开始

```bash
# 1. 用 Xcode 打开项目
open StandupAgent.xcodeproj

# 2. 选择 My Mac 作为 Run Destination

# 3. ⌘R 运行
```

首次运行后：
1. 点击菜单栏的 ☕ 图标 → **设置**
2. 填入你的 Claude API Key
3. 设置早会时间（默认 09:00）
4. 在「本周目标」标签页添加这周要做的事

## 项目结构

```
StandupAgent/
├── StandupAgentApp.swift      # App 入口、菜单栏、通知、定时器
├── Models/
│   └── AppSettings.swift      # 设置存储、WeeklyGoal 模型、Context 构建
├── Services/
│   └── ClaudeService.swift    # Claude API 调用（SSE 流式）
└── Views/
    ├── StandupView.swift       # 早会对话界面
    └── SettingsView.swift      # 设置 + 目标管理界面
```

## 自定义 Claude 的引导风格

在 `ClaudeService.swift` 里修改 `systemPrompt`，可以调整 Claude 的风格：

```swift
private let systemPrompt = """
你是一个专注、高效的早会引导 Agent。
// 在这里修改 Claude 的引导方式...
"""
```

## 常见问题

**通知不显示？**
系统偏好设置 → 通知与专注模式 → 找到 StandupAgent → 允许通知

**API 调用失败？**
检查 API Key 是否正确，以及网络是否能访问 `api.anthropic.com`

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
