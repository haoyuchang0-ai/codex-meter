# Codex Meter

一个轻量的 macOS Codex 额度悬浮窗，实时显示主额度、周额度和重置时间，支持手动刷新与自动更新。

A lightweight macOS floating window for Codex quota, showing primary quota, weekly quota, and reset times with manual refresh and auto updates.

## 功能

- 原生 macOS 悬浮窗，常驻桌面，可拖动。
- 显示主额度和周额度的剩余百分比。
- 显示当前 Codex 订阅档位，例如 Pro 或 Plus。
- 额度进度根据剩余比例显示低饱和鼠尾草绿、赭金或柔和砖红预警。
- 显示每个额度窗口的重置时间。
- 默认每 60 秒自动刷新，也支持手动刷新。
- 支持条形视图、圆形仪表盘视图和两套颜色风格。
- 支持胶囊模式和菜单栏隐藏，隐藏后可从 macOS 菜单栏恢复。
- 使用动态状态胶囊显示所有本地 Codex 任务的待确认、工作中、已完成和空闲状态。
- 点击状态胶囊可查看当前待确认或工作中的顶层任务，点击任务即可跳转到 Codex。
- 保留本地网页调试入口。

## 使用方式

- 点击窗口右上角的收起按钮进入胶囊模式；点击胶囊可恢复完整窗口。
- 在 macOS 菜单栏的 Codex Meter 图标中，可以显示窗口、收起为胶囊、隐藏到菜单栏、手动刷新、切换风格或退出。
- 状态提示会显示在完整窗口左上角、胶囊模式和菜单栏；尺寸保持紧凑，不改变窗口大小。
- 点击完整窗口或胶囊模式中的状态提示，会弹出当前任务列表；选择任务后在 Codex 中打开。
- 关闭窗口不会退出应用，而是隐藏到菜单栏，避免隐藏后找不到。

## Usage

- Click the shrink button in the floating window to enter Capsule mode; click the capsule to restore the full window.
- Use the macOS menu bar icon to show the window, collapse to capsule, hide to the menu bar, refresh manually, switch styles, or quit.
- A dynamic status capsule shows aggregate activity across local Codex tasks in the full window and Capsule mode: Waiting, Working, Done, and Idle.
- Click the activity capsule to list active top-level tasks, then select one to open it in Codex.
- Shows the current Codex subscription tier, such as Pro or Plus, across the full window, Capsule mode, and menu bar menu.
- Quota progress changes from muted sage to ochre and soft brick red as remaining capacity decreases.
- Closing the window hides it to the menu bar instead of quitting, so the app remains easy to recover.

## Quick Start

Requirements:

- macOS 13+
- Node.js 18+
- Xcode Command Line Tools
- Codex desktop app or Codex CLI with `app-server`

Install the local activity Hooks once, then restart Codex:

```bash
npm run install:hooks
```

安装完成后需要重启一次 Codex，之后启动悬浮窗：

Restart Codex once after installation, then run the floating window:

```bash
./launch-floating-window.command
```

The launcher starts the local quota service, builds `CodexQuotaFloat.app` if needed, and opens the floating window.

## 随 Codex 自启动

安装一次 macOS 用户级 LaunchAgent：

```bash
npm run install:autostart
```

之后，打开 Codex 时会自动启动额度服务和悬浮窗；退出 Codex 时两者也会自动关闭。若在 Codex 仍运行时手动退出悬浮窗，本次 Codex 会话不会强制重新打开，下一次启动 Codex 时会恢复。

卸载自启动：

```bash
npm run uninstall:autostart
```

运行文件安装在 `~/Library/Application Support/CodexMeter/runtime/`，监听器日志位于 `~/Library/Logs/CodexMeter/`。

## Codex Lifecycle Autostart

Install the per-user macOS LaunchAgent once:

```bash
npm run install:autostart
```

Codex Meter will then start with Codex and stop when Codex exits. If you manually quit the meter while Codex remains open, it stays closed for that Codex session and returns the next time Codex starts.

Remove autostart with:

```bash
npm run uninstall:autostart
```

Runtime files are installed under `~/Library/Application Support/CodexMeter/runtime/`, and watcher logs are stored in `~/Library/Logs/CodexMeter/`.

活动状态每秒从本机读取一次，额度仍每 60 秒刷新一次。状态优先级为 `waiting > working > done > idle`；完成状态保留 8 秒。

Activity is read locally once per second, while quota still refreshes once per minute. Priority is `waiting > working > done > idle`, and Done remains visible for 8 seconds.

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

这个工具读取 Codex app-server 的账户额度状态和本地任务事件，不会主动创建 Codex 对话，也不发送模型请求，因此状态轮询本身不消耗 Codex 额度。

Hook 状态文件只包含会话 ID、状态和更新时间。工具不记录提示词、回复、工具参数、工作路径或任务标题。任务标题仅在点击状态胶囊时从本地 Codex 按需读取，不会持久化；所有数据都保留在本机。

This tool reads Codex app-server quota data and local task events. It does not create Codex conversations or send model requests, so activity polling does not consume Codex quota.

Hook state files contain only a session ID, status, and timestamp. Prompts, replies, tool arguments, working paths, and task titles are not recorded. Titles are read on demand from local Codex only when the activity capsule is clicked and are never persisted; all data stays local.
