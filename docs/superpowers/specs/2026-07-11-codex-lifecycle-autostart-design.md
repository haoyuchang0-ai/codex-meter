# Codex Lifecycle Autostart Design

## Goal

Start Codex Meter automatically when the macOS Codex desktop application starts, and stop the floating window and local quota service when Codex exits.

## Root Cause

Codex Meter was previously kept alive by a detached `screen` session. That session does not survive logout or restart and is not recreated when Codex launches, so the meter disappears even though the application bundle remains valid.

## Selected Behavior

- A lightweight watcher starts at macOS login through a user LaunchAgent.
- The watcher detects the main Codex desktop process at `/Applications/ChatGPT.app/Contents/MacOS/ChatGPT`.
- An absent-to-running transition launches Codex Meter exactly once for that Codex session.
- A running-to-absent transition stops the floating window and Codex Meter's local quota service.
- If the user manually quits the floating window while Codex remains open, the watcher does not relaunch it during the same Codex session.
- Starting Codex again re-arms the watcher and launches Codex Meter again.

## Components

### Lifecycle Watcher

Add `scripts/codex-lifecycle-watcher.sh` as a long-running, low-frequency shell process. It polls the exact main-process command every three seconds and keeps transition state in memory. It invokes the existing launcher only on an absent-to-running transition.

On a running-to-absent transition, it terminates `CodexQuotaFloat` by exact process name and stops only the Node process recorded in `quota-window.pid` after verifying that its command contains the repository's absolute `server.js` path. A stale or invalid PID file must not terminate any process.

### LaunchAgent Manager

Add `scripts/manage-autostart.sh` with `install` and `uninstall` actions.

Installation generates `~/Library/LaunchAgents/com.haoyuchang.codex-meter.plist` with absolute paths to the repository and watcher. The agent uses `RunAtLoad` and `KeepAlive` so the watcher is restored after login or an unexpected watcher exit. Standard output and errors go to `~/Library/Logs/CodexMeter/`.

Uninstallation boots out the user agent and removes only the generated plist. It also stops the watcher-managed meter processes so uninstall leaves no background component behind.

### Existing Launcher

Keep `launch-floating-window.command` as the single path that builds the native app when needed, starts the quota service, and opens the app. Change the service invocation to pass an absolute `server.js` path so the watcher can safely validate process ownership before stopping it.

### Package And Documentation

Expose these commands:

```bash
npm run install:autostart
npm run uninstall:autostart
```

Document the Codex lifecycle behavior, installation, uninstallation, and log location in Chinese and English.

## Failure Handling

- If the watcher cannot find Codex, it remains idle and does not start Node or the native app.
- If the launcher fails, the watcher records the failure in the LaunchAgent error log and does not retry until Codex exits and starts again.
- If the PID file is missing, malformed, stale, or points to a command other than this repository's absolute `server.js`, the watcher removes no unrelated process.
- If the LaunchAgent is already installed, installation replaces it idempotently by booting out the old definition before bootstrapping the new one.
- If the LaunchAgent is absent, uninstallation still succeeds.

## Testing

- Add source and behavior tests for the watcher transition rules, exact Codex process detection, safe PID validation, and manual-quit behavior.
- Add packaging tests for LaunchAgent keys, absolute-path generation, install/uninstall scripts, and npm commands.
- Run the complete Node test suite and Swift model tests.
- Install the LaunchAgent locally and verify it starts the current Codex Meter instance.
- Simulate the lifecycle without closing the user's active Codex session by running the watcher against controlled test commands and temporary state.
- Verify exactly one floating-window process and one quota-service process remain after installation.

## Success Criteria

- Codex Meter appears automatically after Codex starts, including after a macOS login or restart.
- Codex Meter exits after Codex exits.
- Manual meter quit is respected until the next Codex launch.
- Installation and uninstallation are repeatable and do not affect unrelated processes.
- Existing quota refresh, activity status, task navigation, display modes, visual styles, and window dimensions remain unchanged.
