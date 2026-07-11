# Codex Lifecycle Autostart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex Meter start when the macOS Codex desktop process starts and stop when that Codex process exits.

**Architecture:** A user LaunchAgent keeps a lightweight zsh watcher alive after login. The manager installs a self-contained runtime under `~/Library/Application Support/CodexMeter/runtime` so macOS background privacy does not block files stored in `Documents`. The watcher identifies each Codex session by the main ChatGPT process PID plus start time, persists that identifier so manual meter quit is respected across watcher restarts, and delegates startup to the installed launcher.

**Tech Stack:** zsh, macOS launchd/launchctl, PlistBuddy, Node.js built-in test runner, existing Swift/AppKit application.

## Global Constraints

- Detect only the main process whose full command is `/Applications/ChatGPT.app/Contents/MacOS/ChatGPT`.
- Poll every 3 seconds by default.
- Start the meter once per distinct Codex process session.
- Stop the meter app and owned local quota service when Codex exits.
- Do not relaunch a manually closed meter during the same Codex session.
- Never terminate a Node process unless its command contains this repository's absolute `server.js` path.
- Preserve all existing quota, activity, visual, and window behavior.
- Support repeatable install and uninstall operations.

---

### Task 1: Implement A Testable Lifecycle Watcher

**Files:**
- Create: `test/autostart.test.js`
- Create: `scripts/codex-lifecycle-watcher.sh`
- Modify: `.gitignore`
- Modify: `docs/superpowers/specs/2026-07-11-codex-lifecycle-autostart-design.md`

**Interfaces:**
- Consumes: `launch-floating-window.command`, `quota-window.pid`, the Codex main process, and optional test environment variables.
- Produces: `quota-window.session`, lifecycle event logging for tests, and `--stop` for explicit cleanup.

- [ ] **Step 1: Write failing transition and safety tests**

Create `test/autostart.test.js` with helpers that run the watcher against temporary roots. Cover these behaviors:

```javascript
test("watcher launches once per Codex session and stops on exit", () => {
  const events = runWatcherSequence("-,101,101,-,202");
  assert.deepEqual(events, ["launch:101", "stop:101", "launch:202"]);
});

test("watcher restart respects manual meter quit in the same Codex session", () => {
  const root = makeWatcherRoot();
  runWatcherSequence("301", root);
  const events = runWatcherSequence("301", root);
  assert.deepEqual(events, []);
});

test("watcher stops only the service recorded for its absolute server path", async () => {
  const owned = await spawnNodeFixture("server.js");
  writePidFile(owned.root, owned.pid);
  runWatcherSequence("401,-", owned.root, { dryRun: false });
  assert.equal(await processIsAlive(owned.pid), false);
});

test("watcher never kills a stale unrelated pid", async () => {
  const unrelated = spawn("/bin/sleep", ["30"]);
  const root = makeWatcherRoot();
  writePidFile(root, unrelated.pid);
  runWatcherSequence("501,-", root, { dryRun: false });
  assert.equal(await processIsAlive(unrelated.pid), true);
  unrelated.kill();
});
```

The test helper must set `CODEX_METER_TEST_SEQUENCE`, `CODEX_METER_ROOT`, `CODEX_METER_EVENT_LOG`, and `CODEX_METER_POLL_SECONDS=0`. Use temporary fake launchers so tests never open a GUI application.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
/Users/changhaoyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --test test/autostart.test.js
```

Expected: FAIL because `scripts/codex-lifecycle-watcher.sh` does not exist.

- [ ] **Step 3: Implement the watcher**

Create an executable zsh script with this structure:

```zsh
#!/bin/zsh
set -u

ROOT="${CODEX_METER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
POLL_SECONDS="${CODEX_METER_POLL_SECONDS:-3}"
SESSION_FILE="$ROOT/quota-window.session"
PID_FILE="$ROOT/quota-window.pid"
SERVER_PATH="$ROOT/server.js"
LAUNCHER="${CODEX_METER_LAUNCHER:-$ROOT/launch-floating-window.command}"
EVENT_LOG="${CODEX_METER_EVENT_LOG:-}"
DRY_RUN="${CODEX_METER_DRY_RUN:-0}"
CODEX_PATTERN='^/Applications/ChatGPT\.app/Contents/MacOS/ChatGPT$'

record_event() {
  [[ -n "$EVENT_LOG" ]] && print -r -- "$1" >> "$EVENT_LOG"
}

current_codex_session() {
  local pid start_time
  pid=$(/usr/bin/pgrep -f "$CODEX_PATTERN" | /usr/bin/head -n 1)
  [[ -n "$pid" ]] || return 1
  start_time=$(/bin/ps -p "$pid" -o lstart= 2>/dev/null)
  [[ -n "$start_time" ]] || return 1
  print -r -- "$pid:$start_time"
}

launch_meter() {
  record_event "launch:$1"
  [[ "$DRY_RUN" == "1" ]] || /bin/zsh "$LAUNCHER"
}

stop_meter() {
  record_event "stop:$1"
  if [[ "$DRY_RUN" != "1" ]]; then
    /usr/bin/pkill -x CodexQuotaFloat >/dev/null 2>&1 || true
    stop_owned_service
  fi
}
```

Add `current_test_session()` to consume comma-separated `CODEX_METER_TEST_SEQUENCE` values, where `-` means no Codex process. The main loop compares the current session with the persisted session file:

```zsh
if [[ -n "$current_session" && "$current_session" != "$previous_session" ]]; then
  launch_meter "$current_session"
  print -r -- "$current_session" > "$SESSION_FILE"
elif [[ -z "$current_session" && -n "$previous_session" ]]; then
  stop_meter "$previous_session"
  /bin/rm -f "$SESSION_FILE"
fi
```

Implement `stop_owned_service()` by requiring a numeric PID and matching `SERVER_PATH` within `/bin/ps -p "$pid" -o command=` before sending `TERM`. Remove stale PID files after validation. Implement `--stop` to stop the current session immediately and clear the session file.

- [ ] **Step 4: Ignore watcher state and run focused tests**

Add:

```gitignore
quota-window.session
```

Update the design spec to say the Codex session identifier is persisted rather than held only in memory.

Run the focused test again. Expected: all watcher tests PASS.

---

### Task 2: Add The LaunchAgent Manager

**Files:**
- Modify: `test/autostart.test.js`
- Create: `scripts/manage-autostart.sh`

**Interfaces:**
- Consumes: `scripts/codex-lifecycle-watcher.sh`, user ID, user home, and launchctl.
- Produces: `~/Library/Application Support/CodexMeter/runtime`, `~/Library/LaunchAgents/com.haoyuchang.codex-meter.plist`, LaunchAgent registration, and uninstall cleanup.

- [ ] **Step 1: Write failing installer tests**

Add tests that run the manager with a temporary `CODEX_METER_HOME` and fake `CODEX_METER_LAUNCHCTL`:

```javascript
test("autostart installer writes a persistent user LaunchAgent", () => {
  const result = runManager("install");
  const plist = fs.readFileSync(result.plistPath, "utf8");
  assert.match(plist, /com\.haoyuchang\.codex-meter/);
  assert.match(plist, /codex-lifecycle-watcher\.sh/);
  assert.match(plist, /<key>RunAtLoad<\/key>[\s\S]*<true\/>/);
  assert.match(plist, /<key>KeepAlive<\/key>[\s\S]*<true\/>/);
});

test("autostart uninstall is idempotent and removes the generated plist", () => {
  const result = runManager("install");
  runManager("uninstall", result.home);
  runManager("uninstall", result.home);
  assert.equal(fs.existsSync(result.plistPath), false);
});
```

- [ ] **Step 2: Run focused tests and verify the new tests fail**

Expected: FAIL because `scripts/manage-autostart.sh` does not exist.

- [ ] **Step 3: Implement install and uninstall**

Create an executable zsh script with:

```zsh
LABEL="com.haoyuchang.codex-meter"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${CODEX_METER_HOME:-$HOME}"
PLIST="$HOME_DIR/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME_DIR/Library/Logs/CodexMeter"
RUNTIME="$HOME_DIR/Library/Application Support/CodexMeter/runtime"
DOMAIN="gui/$(/usr/bin/id -u)"
LAUNCHCTL="${CODEX_METER_LAUNCHCTL:-/bin/launchctl}"
```

For `install`, create directories, boot out an old registration, generate the plist with `/usr/libexec/PlistBuddy`, validate it using `/usr/bin/plutil -lint`, then run `bootstrap`, `enable`, and `kickstart -k`.

Before generating the plist, copy the signed app, `server.js`, `src`, `public`, launcher, and watcher into `RUNTIME`. The plist must define `Label`, `ProgramArguments` (`/bin/zsh` and the installed watcher path), installed `WorkingDirectory`, `RunAtLoad=true`, `KeepAlive=true`, `ProcessType=Background`, `StandardOutPath`, and `StandardErrorPath`.

For `uninstall`, boot out the label if present, run the watcher with `--stop`, and remove only the generated plist. Unknown actions exit with usage text and status 2.

- [ ] **Step 4: Run focused tests and verify they pass**

Expected: every test in `test/autostart.test.js` PASS.

---

### Task 3: Integrate, Install, And Verify

**Files:**
- Modify: `launch-floating-window.command`
- Modify: `test/project-packaging.test.js`
- Modify: `package.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: watcher and manager scripts.
- Produces: npm commands, safe absolute server process identity, user documentation, and a live LaunchAgent installation.

- [ ] **Step 1: Write failing packaging assertions**

Add assertions for:

```javascript
assert.equal(pkg.scripts["install:autostart"], "zsh scripts/manage-autostart.sh install");
assert.equal(pkg.scripts["uninstall:autostart"], "zsh scripts/manage-autostart.sh uninstall");
assert.match(launcher, /nohup\s+"\$NODE_BIN"\s+"\$ROOT\/server\.js"/);
assert.match(readme, /npm run install:autostart/);
assert.match(readme, /npm run uninstall:autostart/);
```

Run `test/project-packaging.test.js`. Expected: FAIL on the new assertions.

- [ ] **Step 2: Update launcher, package scripts, and README**

Change the launcher service command to:

```zsh
nohup "$NODE_BIN" "$ROOT/server.js" >> "$ROOT/quota-window.log" 2>&1 &
```

Add the npm scripts exactly as asserted. Document in Chinese and English that Codex Meter starts and stops with Codex, respects manual quit for the current session, stores LaunchAgent logs under `~/Library/Logs/CodexMeter/`, and can be uninstalled with the npm command.

- [ ] **Step 3: Run all automated verification**

Run:

```bash
/Users/changhaoyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --test test/*.test.js
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk -module-cache-path /private/tmp/codex-meter-swift-cache FloatingWindow/QuotaModels.swift FloatingWindowTests/QuotaModelsTests.swift -o /private/tmp/codex-meter-model-tests
/private/tmp/codex-meter-model-tests
zsh scripts/build-floating-window.sh
codesign --verify --deep --strict --verbose=2 CodexQuotaFloat.app
```

Expected: all Node and Swift tests pass, native build succeeds, and code signing is valid.

- [ ] **Step 4: Install and inspect the live LaunchAgent**

Run:

```bash
npm run install:autostart
launchctl print gui/$(id -u)/com.haoyuchang.codex-meter
```

Because Codex is currently open, verify the watcher launches one `CodexQuotaFloat` process and one absolute-path `server.js` process. Verify the floating window is visible and remains visually unchanged.

- [ ] **Step 5: Verify controlled lifecycle transitions**

Use `CODEX_METER_TEST_SEQUENCE` with temporary roots to verify start, stop, restart, and manual-quit behavior without closing the user's active Codex application. Confirm the live LaunchAgent remains loaded afterward.

- [ ] **Step 6: Commit and push**

Run:

```bash
git add .gitignore README.md package.json launch-floating-window.command scripts/codex-lifecycle-watcher.sh scripts/manage-autostart.sh test/autostart.test.js test/project-packaging.test.js docs/superpowers/specs/2026-07-11-codex-lifecycle-autostart-design.md docs/superpowers/plans/2026-07-11-codex-lifecycle-autostart.md
git commit -m "Start Codex Meter with Codex lifecycle"
git push origin main
```

Expected: `origin/main` includes the autostart implementation and the worktree is clean.
