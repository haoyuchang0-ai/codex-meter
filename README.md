# Codex Meter

一个轻量的 macOS Codex 额度悬浮窗，实时显示主额度、周额度和重置时间，支持手动刷新与自动更新。

A lightweight macOS floating window for Codex quota, showing primary quota, weekly quota, and reset times with manual refresh and auto updates.

## 功能

- 原生 macOS 悬浮窗，常驻桌面，可拖动。
- 显示主额度和周额度的剩余百分比。
- 显示每个额度窗口的重置时间。
- 默认每 60 秒自动刷新，也支持手动刷新。
- 支持条形视图、圆形仪表盘视图和两套颜色风格。
- 支持胶囊模式和菜单栏隐藏，隐藏后可从 macOS 菜单栏恢复。
- 支持四种轻量状态提示：待确认、工作中、已完成、空闲。
- 保留本地网页调试入口。

## 使用方式

- 点击窗口右上角的收起按钮进入胶囊模式；点击胶囊可恢复完整窗口。
- 在 macOS 菜单栏的 Codex Meter 图标中，可以显示窗口、收起为胶囊、隐藏到菜单栏、手动刷新、切换风格或退出。
- 状态提示会显示在完整窗口左上角、胶囊模式和菜单栏；尺寸保持紧凑，不改变窗口大小。
- 关闭窗口不会退出应用，而是隐藏到菜单栏，避免隐藏后找不到。

## Usage

- Click the shrink button in the floating window to enter Capsule mode; click the capsule to restore the full window.
- Use the macOS menu bar icon to show the window, collapse to capsule, hide to the menu bar, refresh manually, switch styles, or quit.
- Activity states appear in the full window, Capsule mode, and menu bar: Waiting, Working, Done, and Idle.
- Closing the window hides it to the menu bar instead of quitting, so the app remains easy to recover.

## Quick Start

Requirements:

- macOS 13+
- Node.js 18+
- Xcode Command Line Tools
- Codex desktop app or Codex CLI with `app-server`

Run the floating window:

```bash
./launch-floating-window.command
```

The launcher starts the local quota service, builds `CodexQuotaFloat.app` if needed, and opens the floating window.

You can also start only the local service:

```bash
npm start
```

Debug endpoint:

```text
http://127.0.0.1:5487
```

## Build the macOS App

```bash
npm run build:mac
```

Or run the build script directly:

```bash
zsh scripts/build-floating-window.sh
```

The app bundle is generated locally as `CodexQuotaFloat.app`. Build outputs are intentionally ignored by Git.

## 配置

Change the local server port:

```bash
PORT=5490 npm start
```

Codex CLI path:

默认会自动查找 `/Applications/ChatGPT.app/Contents/Resources/codex` 和 `/Applications/Codex.app/Contents/Resources/codex`。如果你的 Codex CLI 在其他位置：

By default, the server auto-detects `/Applications/ChatGPT.app/Contents/Resources/codex` and `/Applications/Codex.app/Contents/Resources/codex`. If your Codex CLI is somewhere else:

```bash
CODEX_CLI=/path/to/codex npm start
```

## 开发

Run tests:

```bash
npm test
```

Project structure:

- `server.js`: local HTTP service and static debug page
- `src/`: Codex app-server client and quota normalization
- `FloatingWindow/`: native macOS floating window source
- `FloatingWindowTests/`: Swift model tests
- `test/`: Node.js tests
- `scripts/`: local build scripts

## 隐私与额度说明

这个工具读取 Codex app-server 的账户额度状态，不会主动创建 Codex 对话，也不发送模型请求。

This tool reads Codex app-server account quota state. It does not create Codex conversations or send model requests.
