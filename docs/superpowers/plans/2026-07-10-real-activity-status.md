# Real Codex Activity Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the quota-refresh-derived status with a local, global Codex task status and present it as the approved three-lamp signal strip.

**Architecture:** A Node.js activity monitor combines recent Codex rollout events with minimal per-session Hook state files, then exposes one privacy-safe `/api/activity` snapshot. The macOS client polls that endpoint once per second, keeps quota refresh behavior separate, and renders the approved fixed-size red/yellow/green signal strip in the expanded and capsule windows.

**Tech Stack:** Node.js 18+ (`node:test`, built-in `fs`, `http`), Python 3 for the Codex Hook writer, Swift/AppKit for the native macOS UI.

## Global Constraints

- Monitor all local Codex tasks, not only the foreground task.
- Aggregate with `waiting > working > done > idle` priority.
- Hold `done` for exactly 8 seconds and expire stale active/waiting records after 12 hours.
- Poll activity every 1 second; keep quota refresh at 60 seconds.
- Never send model requests and never persist prompts, replies, tool arguments, paths, or task titles.
- Keep the expanded window at `312 x 184 pt` and the capsule at `156 x 44 pt`.
- Use three persistent 8 pt lamps with a fixed-size label; only the active semantic lamp glows.
- Preserve every pre-existing Codex Hook when installing the integration.
- Keep normal states to `waiting`, `working`, `done`, and `idle`; use `unknown` only after the activity endpoint has failed continuously for 10 seconds.

---

## File Structure

- Create `src/activity-state.js`: pure rollout parsing and global state aggregation.
- Create `src/activity-monitor.js`: bounded local file discovery, cache, Hook-state reads, and snapshot production.
- Create `src/hook-installer.js`: idempotent merge/install logic for `~/.codex/hooks.json`.
- Create `scripts/codex-meter-state.py`: privacy-safe Hook event writer.
- Create `scripts/install-activity-hooks.js`: CLI entry point for Hook installation.
- Modify `server.js`: dependency-injectable request handler plus `/api/activity`.
- Modify `FloatingWindow/QuotaModels.swift`: decodable activity snapshot.
- Modify `FloatingWindow/main.swift`: one-second activity polling, failure grace period, and signal-light views.
- Modify `package.json`, `README.md`, and packaging tests: installation command and operating documentation.
- Create `test/activity-state.test.js`, `test/activity-monitor.test.js`, `test/hook-installer.test.js`, and `test/server.test.js`.
- Modify `FloatingWindowTests/QuotaModelsTests.swift` and `test/floating-style.test.js`.

---

### Task 1: Pure Activity Event Parsing And Aggregation

**Files:**
- Create: `src/activity-state.js`
- Create: `test/activity-state.test.js`

**Interfaces:**
- Produces: `parseRolloutText(text: string, threadId: string): ActivityEvent[]`
- Produces: `aggregateActivity({ rolloutEvents, hookStates, nowMs }): ActivitySnapshot`
- Produces constants: `DONE_HOLD_MS`, `STALE_ACTIVITY_MS`
- `ActivityEvent`: `{ threadId, turnId, status: "working" | "done", updatedAtMs }`
- `HookState`: `{ threadId, status: "waiting" | "working" | "done" | "idle", updatedAtMs }`

- [ ] **Step 1: Write the failing parser and reducer tests**

```js
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DONE_HOLD_MS,
  STALE_ACTIVITY_MS,
  aggregateActivity,
  parseRolloutText,
} = require("../src/activity-state");

test("parses only task lifecycle fields and skips malformed JSONL", () => {
  const text = [
    JSON.stringify({
      timestamp: "2026-07-10T02:23:05.016Z",
      type: "event_msg",
      payload: { type: "task_started", turn_id: "turn-1", secret: "omit" },
    }),
    "{broken",
    JSON.stringify({
      timestamp: "2026-07-10T02:23:13.016Z",
      type: "event_msg",
      payload: { type: "task_complete", turn_id: "turn-1", last_agent_message: "omit" },
    }),
  ].join("\n");

  assert.deepEqual(parseRolloutText(text, "thread-1"), [
    {
      threadId: "thread-1",
      turnId: "turn-1",
      status: "working",
      updatedAtMs: Date.parse("2026-07-10T02:23:05.016Z"),
    },
    {
      threadId: "thread-1",
      turnId: "turn-1",
      status: "done",
      updatedAtMs: Date.parse("2026-07-10T02:23:13.016Z"),
    },
  ]);
});

test("aggregates global states with waiting priority and eight-second done hold", () => {
  const nowMs = Date.parse("2026-07-10T02:23:15.000Z");
  const active = {
    threadId: "thread-active",
    turnId: "turn-active",
    status: "working",
    updatedAtMs: nowMs - 2_000,
  };
  const waiting = {
    threadId: "thread-waiting",
    status: "waiting",
    updatedAtMs: nowMs - 1_000,
  };

  assert.equal(
    aggregateActivity({ rolloutEvents: [active], hookStates: [waiting], nowMs }).status,
    "waiting",
  );

  const doneEvent = { ...active, status: "done", updatedAtMs: nowMs - 7_999 };
  assert.equal(
    aggregateActivity({ rolloutEvents: [active, doneEvent], hookStates: [], nowMs }).status,
    "done",
  );
  assert.equal(DONE_HOLD_MS, 8_000);

  assert.equal(
    aggregateActivity({
      rolloutEvents: [active, { ...doneEvent, updatedAtMs: nowMs - 8_001 }],
      hookStates: [],
      nowMs,
    }).status,
    "idle",
  );
});

test("ignores stale active and waiting records after twelve hours", () => {
  const nowMs = Date.parse("2026-07-10T15:00:00.000Z");
  const staleAt = nowMs - STALE_ACTIVITY_MS - 1;
  const snapshot = aggregateActivity({
    rolloutEvents: [{
      threadId: "thread-1",
      turnId: "turn-1",
      status: "working",
      updatedAtMs: staleAt,
    }],
    hookStates: [{ threadId: "thread-1", status: "waiting", updatedAtMs: staleAt }],
    nowMs,
  });

  assert.equal(STALE_ACTIVITY_MS, 12 * 60 * 60 * 1_000);
  assert.equal(snapshot.status, "idle");
  assert.equal(snapshot.activeCount, 0);
  assert.equal(snapshot.waitingCount, 0);
});

test("newer completion overrides an older waiting hook in the same thread", () => {
  const nowMs = Date.parse("2026-07-10T02:23:15.000Z");
  const snapshot = aggregateActivity({
    rolloutEvents: [
      {
        threadId: "thread-1",
        turnId: "turn-1",
        status: "working",
        updatedAtMs: nowMs - 5_000,
      },
      {
        threadId: "thread-1",
        turnId: "turn-1",
        status: "done",
        updatedAtMs: nowMs - 1_000,
      },
    ],
    hookStates: [{
      threadId: "thread-1",
      status: "waiting",
      updatedAtMs: nowMs - 3_000,
    }],
    nowMs,
  });

  assert.equal(snapshot.status, "done");
  assert.equal(snapshot.waitingCount, 0);
});
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
node --test test/activity-state.test.js
```

Expected: FAIL with `Cannot find module '../src/activity-state'`.

- [ ] **Step 3: Implement the pure parser and reducer**

```js
const DONE_HOLD_MS = 8_000;
const STALE_ACTIVITY_MS = 12 * 60 * 60 * 1_000;

function parseRolloutText(text, threadId) {
  const events = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;

    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }

    if (record.type !== "event_msg") continue;
    const payloadType = record.payload && record.payload.type;
    if (payloadType !== "task_started" && payloadType !== "task_complete") continue;

    const turnId = record.payload.turn_id;
    const updatedAtMs = Date.parse(record.timestamp);
    if (typeof turnId !== "string" || !Number.isFinite(updatedAtMs)) continue;

    events.push({
      threadId,
      turnId,
      status: payloadType === "task_started" ? "working" : "done",
      updatedAtMs,
    });
  }
  return events;
}

function aggregateActivity({ rolloutEvents = [], hookStates = [], nowMs = Date.now() }) {
  const turns = new Map();
  for (const event of [...rolloutEvents].sort((a, b) => a.updatedAtMs - b.updatedAtMs)) {
    turns.set(event.turnId, event);
  }

  const latestByThread = new Map();
  const candidates = [...turns.values(), ...hookStates]
    .filter((state) => nowMs - state.updatedAtMs <= STALE_ACTIVITY_MS)
    .sort((a, b) => a.updatedAtMs - b.updatedAtMs);
  for (const candidate of candidates) {
    latestByThread.set(candidate.threadId, candidate);
  }

  const threadStates = [...latestByThread.values()];
  const waitingThreads = new Set(
    threadStates.filter((state) => state.status === "waiting").map((state) => state.threadId),
  );
  const activeThreads = new Set(
    threadStates.filter((state) => state.status === "working").map((state) => state.threadId),
  );
  const completionTimes = threadStates
    .filter((state) => state.status === "done")
    .map((state) => state.updatedAtMs);
  const latestCompletion = completionTimes.length ? Math.max(...completionTimes) : null;

  let status = "idle";
  if (waitingThreads.size > 0) status = "waiting";
  else if (activeThreads.size > 0) status = "working";
  else if (latestCompletion !== null && nowMs - latestCompletion <= DONE_HOLD_MS) status = "done";

  const updatedAtMs = Math.max(
    0,
    ...rolloutEvents.map((event) => event.updatedAtMs),
    ...hookStates.map((state) => state.updatedAtMs),
  );

  return {
    status,
    updatedAt: new Date(updatedAtMs || nowMs).toISOString(),
    activeCount: activeThreads.size,
    waitingCount: waitingThreads.size,
    source: "local",
  };
}

module.exports = {
  DONE_HOLD_MS,
  STALE_ACTIVITY_MS,
  aggregateActivity,
  parseRolloutText,
};
```

- [ ] **Step 4: Run the tests and verify GREEN**

Run: `node --test test/activity-state.test.js`

Expected: 4 tests pass, 0 fail.

- [ ] **Step 5: Commit the pure state engine**

```bash
git add src/activity-state.js test/activity-state.test.js
git commit -m "Add local activity state engine"
```

---

### Task 2: Cached Local Activity Monitor

**Files:**
- Create: `src/activity-monitor.js`
- Create: `test/activity-monitor.test.js`

**Interfaces:**
- Consumes: `parseRolloutText()` and `aggregateActivity()` from Task 1.
- Produces: `new ActivityMonitor(options).snapshot(): ActivitySnapshot & { hooksInstalled: boolean }`
- Options: `{ sessionsRoot, hookStateRoot, hooksConfigPath, now, fsImpl }`

- [ ] **Step 1: Write the failing filesystem monitor test**

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { ActivityMonitor } = require("../src/activity-monitor");

test("reads rollout and hook state without returning private content", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-activity-"));
  const sessionsRoot = path.join(root, "sessions");
  const hookStateRoot = path.join(root, "activity");
  const dateDir = path.join(sessionsRoot, "2026", "07", "10");
  fs.mkdirSync(dateDir, { recursive: true });
  fs.mkdirSync(hookStateRoot, { recursive: true });

  const rolloutPath = path.join(
    dateDir,
    "rollout-019f0000-0000-7000-8000-000000000001.jsonl",
  );
  fs.writeFileSync(
    rolloutPath,
    `${JSON.stringify({
      timestamp: "2026-07-10T02:23:05.016Z",
      type: "event_msg",
      payload: { type: "task_started", turn_id: "turn-1", prompt: "private" },
    })}\n`,
  );
  fs.writeFileSync(
    path.join(hookStateRoot, "019f0000-0000-7000-8000-000000000001.json"),
    JSON.stringify({
      threadId: "019f0000-0000-7000-8000-000000000001",
      status: "waiting",
      updatedAtMs: Date.parse("2026-07-10T02:23:06.016Z"),
    }),
  );

  const monitor = new ActivityMonitor({
    sessionsRoot,
    hookStateRoot,
    hooksConfigPath: path.join(root, "hooks.json"),
    now: () => Date.parse("2026-07-10T02:23:07.016Z"),
  });
  const snapshot = monitor.snapshot();

  assert.equal(snapshot.status, "waiting");
  assert.equal(snapshot.waitingCount, 1);
  assert.equal(snapshot.hooksInstalled, false);
  assert.doesNotMatch(JSON.stringify(snapshot), /private|rollout|sessions/);

  fs.appendFileSync(rolloutPath, `${JSON.stringify({
    timestamp: "2026-07-10T02:23:06.516Z",
    type: "event_msg",
    payload: { type: "task_complete", turn_id: "turn-1" },
  })}\n`);
  assert.equal(monitor.snapshot().status, "done");
});

test("detects an installed Codex Meter hook without exposing hook commands", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-hooks-"));
  const hooksConfigPath = path.join(root, "hooks.json");
  fs.writeFileSync(hooksConfigPath, JSON.stringify({
    hooks: {
      Stop: [{ hooks: [{ type: "command", command: "python3 ~/.codex/hooks/codex-meter-state.py done" }] }],
    },
  }));

  const monitor = new ActivityMonitor({
    sessionsRoot: path.join(root, "sessions"),
    hookStateRoot: path.join(root, "activity"),
    hooksConfigPath,
  });
  assert.equal(monitor.snapshot().hooksInstalled, true);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `node --test test/activity-monitor.test.js`

Expected: FAIL with `Cannot find module '../src/activity-monitor'`.

- [ ] **Step 3: Implement bounded discovery, caching, and Hook-state reads**

```js
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { aggregateActivity, parseRolloutText } = require("./activity-state");

const THREAD_ID_PATTERN = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;

function safeJson(filePath, fsImpl) {
  try {
    return JSON.parse(fsImpl.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function walkJsonl(root, fsImpl) {
  if (!fsImpl.existsSync(root)) return [];
  const files = [];
  for (const entry of fsImpl.readdirSync(root, { withFileTypes: true })) {
    const child = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...walkJsonl(child, fsImpl));
    else if (entry.isFile() && entry.name.endsWith(".jsonl")) files.push(child);
  }
  return files;
}

function readRange(filePath, offset, length, fsImpl) {
  if (length <= 0) return "";
  const descriptor = fsImpl.openSync(filePath, "r");
  try {
    const buffer = Buffer.alloc(length);
    const bytesRead = fsImpl.readSync(descriptor, buffer, 0, length, offset);
    return buffer.subarray(0, bytesRead).toString("utf8");
  } finally {
    fsImpl.closeSync(descriptor);
  }
}

class ActivityMonitor {
  constructor(options = {}) {
    const codexHome = options.codexHome || path.join(os.homedir(), ".codex");
    this.sessionsRoot = options.sessionsRoot || path.join(codexHome, "sessions");
    this.hookStateRoot = options.hookStateRoot || path.join(codexHome, "codex-meter", "activity");
    this.hooksConfigPath = options.hooksConfigPath || path.join(codexHome, "hooks.json");
    this.now = options.now || Date.now;
    this.fs = options.fsImpl || fs;
    this.cache = new Map();
  }

  readRolloutEvents() {
    const events = [];
    for (const filePath of walkJsonl(this.sessionsRoot, this.fs)) {
      let stat;
      try { stat = this.fs.statSync(filePath); } catch { continue; }
      if (this.now() - stat.mtimeMs > 48 * 60 * 60 * 1_000) continue;

      const cached = this.cache.get(filePath);
      if (!cached || cached.size !== stat.size) {
        const match = path.basename(filePath).match(THREAD_ID_PATTERN);
        if (!match) continue;

        const reset = !cached || stat.size < cached.size;
        const offset = reset ? 0 : cached.size;
        let chunk;
        try { chunk = readRange(filePath, offset, stat.size - offset, this.fs); } catch { continue; }
        const combined = `${reset ? "" : cached.remainder}${chunk}`;
        const lines = combined.split("\n");
        const remainder = lines.pop() || "";
        const parsed = parseRolloutText(lines.join("\n"), match[1]);
        this.cache.set(filePath, {
          size: stat.size,
          remainder,
          events: [...(reset ? [] : cached.events), ...parsed],
        });
      }
      events.push(...this.cache.get(filePath).events);
    }
    return events;
  }

  readHookStates() {
    if (!this.fs.existsSync(this.hookStateRoot)) return [];
    const states = [];
    for (const name of this.fs.readdirSync(this.hookStateRoot)) {
      if (!name.endsWith(".json")) continue;
      const state = safeJson(path.join(this.hookStateRoot, name), this.fs);
      if (
        state && typeof state.threadId === "string" &&
        ["waiting", "working", "done", "idle"].includes(state.status) &&
        Number.isFinite(state.updatedAtMs)
      ) states.push(state);
    }
    return states;
  }

  hooksInstalled() {
    if (!this.fs.existsSync(this.hooksConfigPath)) return false;
    try {
      return this.fs.readFileSync(this.hooksConfigPath, "utf8").includes("codex-meter-state.py");
    } catch {
      return false;
    }
  }

  snapshot() {
    return {
      ...aggregateActivity({
        rolloutEvents: this.readRolloutEvents(),
        hookStates: this.readHookStates(),
        nowMs: this.now(),
      }),
      hooksInstalled: this.hooksInstalled(),
    };
  }
}

module.exports = { ActivityMonitor };
```

- [ ] **Step 4: Run the test and verify GREEN**

Run: `node --test test/activity-monitor.test.js`

Expected: 2 tests pass, 0 fail.

- [ ] **Step 5: Commit the local monitor**

```bash
git add src/activity-monitor.js test/activity-monitor.test.js
git commit -m "Add cached local activity monitor"
```

---

### Task 3: Privacy-Safe Hook Writer And Idempotent Installer

**Files:**
- Create: `scripts/codex-meter-state.py`
- Create: `src/hook-installer.js`
- Create: `scripts/install-activity-hooks.js`
- Create: `test/hook-installer.test.js`
- Modify: `package.json`

**Interfaces:**
- Produces: `installActivityHooks({ codexHome, sourceScript, now }): { changed, backupPath }`
- Hook command contract: `python3 "${CODEX_HOME:-$HOME/.codex}/hooks/codex-meter-state.py" <status>` with Hook JSON on stdin.

- [ ] **Step 1: Write the failing idempotency and preservation test**

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { installActivityHooks } = require("../src/hook-installer");

test("installs Codex Meter hooks twice without duplicating or deleting existing hooks", () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-install-"));
  const sourceScript = path.join(codexHome, "source.py");
  fs.writeFileSync(sourceScript, "print('hook')\n");
  fs.writeFileSync(path.join(codexHome, "hooks.json"), JSON.stringify({
    hooks: {
      Stop: [{ hooks: [{ type: "command", command: "python3 existing.py" }] }],
    },
  }));

  const first = installActivityHooks({
    codexHome,
    sourceScript,
    now: () => 1783650000000,
  });
  const second = installActivityHooks({
    codexHome,
    sourceScript,
    now: () => 1783650001000,
  });
  const installed = JSON.parse(fs.readFileSync(path.join(codexHome, "hooks.json"), "utf8"));
  const serialized = JSON.stringify(installed);

  assert.equal(first.changed, true);
  assert.ok(first.backupPath.endsWith("hooks.json.codex-meter-backup-1783650000000"));
  assert.equal(second.changed, false);
  assert.match(serialized, /python3 existing\.py/);
  assert.equal((serialized.match(/codex-meter-state\.py/g) || []).length, 6);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `node --test test/hook-installer.test.js`

Expected: FAIL with `Cannot find module '../src/hook-installer'`.

- [ ] **Step 3: Implement the Hook writer**

```python
#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

VALID = {"waiting", "working", "done", "idle"}


def main() -> int:
    status = sys.argv[1] if len(sys.argv) > 1 else ""
    if status not in VALID:
        return 0

    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0

    thread_id = payload.get("session_id") or payload.get("thread_id")
    if (
        not isinstance(thread_id, str)
        or len(thread_id) != 36
        or any(character not in "0123456789abcdefABCDEF-" for character in thread_id)
    ):
        return 0

    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    state_dir = codex_home / "codex-meter" / "activity"
    state_dir.mkdir(parents=True, exist_ok=True)
    destination = state_dir / f"{thread_id}.json"
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(
        json.dumps({
            "threadId": thread_id,
            "status": status,
            "updatedAtMs": int(time.time() * 1000),
        }, separators=(",", ":")),
        encoding="utf-8",
    )
    temporary.replace(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Implement the installer and CLI wrapper**

```js
// src/hook-installer.js
const fs = require("node:fs");
const path = require("node:path");

const HOOKS = [
  ["SessionStart", "startup|resume|clear", "idle"],
  ["UserPromptSubmit", null, "working"],
  ["PermissionRequest", "*", "waiting"],
  ["PreToolUse", "request_user_input", "waiting"],
  ["PostToolUse", "request_user_input", "working"],
  ["Stop", null, "done"],
];

function groupFor(matcher, status) {
  const group = {
    hooks: [{
      type: "command",
      command: `python3 "\${CODEX_HOME:-$HOME/.codex}/hooks/codex-meter-state.py" ${status}`,
    }],
  };
  if (matcher) group.matcher = matcher;
  return group;
}

function installActivityHooks({ codexHome, sourceScript, now = Date.now }) {
  const hooksDir = path.join(codexHome, "hooks");
  const configPath = path.join(codexHome, "hooks.json");
  fs.mkdirSync(hooksDir, { recursive: true });
  fs.copyFileSync(sourceScript, path.join(hooksDir, "codex-meter-state.py"));

  const config = fs.existsSync(configPath)
    ? JSON.parse(fs.readFileSync(configPath, "utf8"))
    : { hooks: {} };
  config.hooks = config.hooks || {};

  let changed = false;
  for (const [event, matcher, status] of HOOKS) {
    config.hooks[event] = config.hooks[event] || [];
    const desiredGroup = groupFor(matcher, status);
    const desiredCommand = desiredGroup.hooks[0].command;
    const alreadyInstalled = config.hooks[event].some((group) =>
      Array.isArray(group.hooks) && group.hooks.some((hook) => hook.command === desiredCommand),
    );
    if (!alreadyInstalled) {
      config.hooks[event].push(desiredGroup);
      changed = true;
    }
  }

  let backupPath = null;
  if (changed && fs.existsSync(configPath)) {
    backupPath = `${configPath}.codex-meter-backup-${now()}`;
    fs.copyFileSync(configPath, backupPath);
  }
  if (changed) {
    const temporary = `${configPath}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`);
    fs.renameSync(temporary, configPath);
  }
  return { changed, backupPath };
}

module.exports = { installActivityHooks };
```

```js
#!/usr/bin/env node
// scripts/install-activity-hooks.js
const os = require("node:os");
const path = require("node:path");
const { installActivityHooks } = require("../src/hook-installer");

const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
const result = installActivityHooks({
  codexHome,
  sourceScript: path.join(__dirname, "codex-meter-state.py"),
});
console.log(result.changed ? "Codex Meter activity hooks installed." : "Codex Meter activity hooks already installed.");
if (result.backupPath) console.log(`Backup: ${result.backupPath}`);
console.log("Restart Codex to activate the hooks.");
```

Add to `package.json`:

```json
"install:hooks": "node scripts/install-activity-hooks.js"
```

- [ ] **Step 5: Run Hook installer and all Node tests**

Run:

```bash
node --test test/hook-installer.test.js
npm test
```

Expected: Hook installer test passes; existing Node suite remains green.

- [ ] **Step 6: Commit the Hook integration**

```bash
git add scripts/codex-meter-state.py scripts/install-activity-hooks.js src/hook-installer.js test/hook-installer.test.js package.json
git commit -m "Add privacy-safe Codex activity hooks"
```

---

### Task 4: Activity HTTP Endpoint

**Files:**
- Modify: `server.js:1-113`
- Create: `test/server.test.js`

**Interfaces:**
- Consumes: `ActivityMonitor.snapshot()` from Task 2.
- Produces: `createRequestHandler({ rateLimitReader, activityReader }): (req, res) => Promise<void>`
- Produces endpoint: `GET /api/activity`.

- [ ] **Step 1: Write the failing endpoint test**

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

const { createRequestHandler } = require("../server");

test("GET /api/activity returns only the local aggregate snapshot", async () => {
  const snapshot = {
    status: "working",
    updatedAt: "2026-07-10T02:23:05.016Z",
    activeCount: 1,
    waitingCount: 0,
    source: "local",
    hooksInstalled: true,
  };
  const server = http.createServer(createRequestHandler({
    rateLimitReader: async () => ({ windows: [] }),
    activityReader: () => snapshot,
  }));
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const address = server.address();
  const body = await new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${address.port}/api/activity`, (response) => {
      let text = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => { text += chunk; });
      response.on("end", () => resolve(text));
    }).on("error", reject);
  });
  server.close();

  assert.deepEqual(JSON.parse(body), snapshot);
  assert.doesNotMatch(body, /prompt|cwd|title|path/);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `node --test test/server.test.js`

Expected: FAIL because `createRequestHandler` is not exported and requiring `server.js` starts a listener.

- [ ] **Step 3: Refactor the handler and add the endpoint**

Add at module scope:

```js
const { ActivityMonitor } = require("./src/activity-monitor");
const activityMonitor = new ActivityMonitor();

function createRequestHandler(options = {}) {
  const rateLimitReader = options.rateLimitReader || readRateLimits;
  const activityReader = options.activityReader || (() => activityMonitor.snapshot());

  return async function requestHandler(req, res) {
    if (req.url === "/api/health") {
      sendJson(res, 200, { ok: true });
      return;
    }

    if (req.url === "/api/activity") {
      try {
        sendJson(res, 200, activityReader());
      } catch (error) {
        sendJson(res, 503, {
          ok: false,
          error: "Activity status unavailable",
          fetchedAt: new Date().toISOString(),
        });
      }
      return;
    }

    if (req.url === "/api/rate-limits") {
      try {
        sendJson(res, 200, await rateLimitReader());
      } catch (error) {
        sendJson(res, 502, {
          ok: false,
          error: error.message,
          details: error.details || null,
          fetchedAt: new Date().toISOString(),
        });
      }
      return;
    }

    if (req.method !== "GET") {
      res.writeHead(405, { allow: "GET" });
      res.end("Method not allowed");
      return;
    }
    sendStatic(req, res);
  };
}
```

Replace immediate handler construction and guard process startup:

```js
const server = http.createServer(createRequestHandler());

if (require.main === module) {
  server.listen(PORT, HOST, () => {
    console.log(`Codex quota window: http://${HOST}:${PORT}`);
  });

  const shutdown = () => {
    client.close();
    server.close(() => process.exit(0));
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

module.exports = { createRequestHandler, readRateLimits };
```

- [ ] **Step 4: Run endpoint and regression tests**

Run:

```bash
node --test test/server.test.js
npm test
```

Expected: endpoint test and complete Node suite pass.

- [ ] **Step 5: Commit the endpoint**

```bash
git add server.js test/server.test.js
git commit -m "Expose local Codex activity endpoint"
```

---

### Task 5: Swift Activity Polling And Quota Lifecycle Separation

**Files:**
- Modify: `FloatingWindow/QuotaModels.swift`
- Modify: `FloatingWindowTests/QuotaModelsTests.swift`
- Modify: `FloatingWindow/main.swift:1-120,560-825`
- Modify: `test/floating-style.test.js`

**Interfaces:**
- Consumes: `GET /api/activity` from Task 4.
- Produces: `ActivitySnapshot: Decodable` with status, counts, source, and `hooksInstalled`.
- Produces: `refreshActivityNow()` and 1-second `activityTimer`.

- [ ] **Step 1: Extend the Swift model test first**

Add this call to `main()`:

```swift
try parsesActivityResponse()
```

Add this test:

```swift
private static func parsesActivityResponse() throws {
    let json = """
    {
      "status": "waiting",
      "updatedAt": "2026-07-10T02:23:05.016Z",
      "activeCount": 2,
      "waitingCount": 1,
      "source": "local",
      "hooksInstalled": true
    }
    """
    let snapshot = try JSONDecoder().decode(ActivitySnapshot.self, from: Data(json.utf8))
    assertEqual(snapshot.status, "waiting")
    assertEqual(snapshot.activeCount, 2)
    assertEqual(snapshot.waitingCount, 1)
    assertEqual(snapshot.hooksInstalled, true)
}
```

In `test/floating-style.test.js`, replace the refresh-lifecycle assertion with:

```js
test("native activity status polls independently from quota refresh", () => {
  const source = readMainSwift();
  assert.match(source, /activityEndpoint/);
  assert.match(source, /activityRefreshInterval:\s*TimeInterval\s*=\s*1/);
  assert.match(source, /refreshActivityNow\(\)/);
  assert.match(source, /private\s+var\s+activityTimer:\s*Timer\?/);
  assert.doesNotMatch(source, /refreshNow[\s\S]{0,220}setActivityStatus\(\.working\)/);
  assert.doesNotMatch(source, /render\(_\s+snapshot:\s*QuotaSnapshot\)[\s\S]{0,500}setActivityStatus\(\.done\)/);
  assert.doesNotMatch(source, /idleStatusTimer/);
  assert.match(source, /onActivityIntegrationChanged/);
  assert.match(source, /状态监听：需安装 Hooks/);
});
```

- [ ] **Step 2: Run Swift and style tests and verify RED**

Run:

```bash
swiftc -module-cache-path build/swift-module-cache FloatingWindowTests/QuotaModelsTests.swift FloatingWindow/QuotaModels.swift -o /private/tmp/quota-models-test
/private/tmp/quota-models-test
node --test test/floating-style.test.js
```

Expected: Swift compile fails because `ActivitySnapshot` is missing; style test fails because quota refresh still sets activity.

- [ ] **Step 3: Add the activity model**

Append to `FloatingWindow/QuotaModels.swift`:

```swift
struct ActivitySnapshot: Decodable {
    let status: String
    let updatedAt: String?
    let activeCount: Int
    let waitingCount: Int
    let source: String?
    let hooksInstalled: Bool
}
```

- [ ] **Step 4: Add independent polling and failure grace logic**

Add constants and the exceptional state:

```swift
private let activityRefreshInterval: TimeInterval = 1
private let activityFailureGraceInterval: TimeInterval = 10
private let activityEndpoint = URL(string: "http://127.0.0.1:5487/api/activity")!

enum ActivityStatus {
    case waiting, working, done, idle, unknown

    var label: String {
        switch self {
        case .waiting: return "待确认"
        case .working: return "工作中"
        case .done: return "已完成"
        case .idle: return "空闲"
        case .unknown: return "状态未知"
        }
    }

    var menuTitle: String { "状态：\(label)" }

    var color: NSColor {
        switch self {
        case .waiting: return .systemRed
        case .working: return .systemYellow
        case .done: return .systemGreen
        case .idle: return NSColor(calibratedWhite: 0.58, alpha: 1)
        case .unknown: return NSColor(calibratedWhite: 0.46, alpha: 1)
        }
    }

    init(apiValue: String) {
        switch apiValue {
        case "waiting": self = .waiting
        case "working": self = .working
        case "done": self = .done
        case "idle": self = .idle
        default: self = .unknown
        }
    }
}
```

Add controller state:

```swift
private var activityTimer: Timer?
private var lastActivitySuccessAt: Date?
var onActivityIntegrationChanged: ((Bool) -> Void)?
```

In `viewDidLoad()` start activity polling without changing the quota timer:

```swift
refreshNow()
refreshActivityNow()
refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
    guard let self, self.isAutoRefreshEnabled else { return }
    self.refreshNow()
}
activityTimer = Timer.scheduledTimer(withTimeInterval: activityRefreshInterval, repeats: true) { [weak self] _ in
    self?.refreshActivityNow()
}
```

Add the polling methods:

```swift
private func refreshActivityNow() {
    URLSession.shared.dataTask(with: activityEndpoint) { [weak self] data, _, error in
        DispatchQueue.main.async {
            guard let self else { return }
            guard error == nil,
                  let data,
                  let snapshot = try? JSONDecoder().decode(ActivitySnapshot.self, from: data) else {
                self.handleActivityFailure()
                return
            }
            self.lastActivitySuccessAt = Date()
            self.setActivityStatus(ActivityStatus(apiValue: snapshot.status))
            self.onActivityIntegrationChanged?(snapshot.hooksInstalled)
        }
    }.resume()
}

private func handleActivityFailure() {
    if let lastActivitySuccessAt,
       Date().timeIntervalSince(lastActivitySuccessAt) <= activityFailureGraceInterval {
        return
    }
    setActivityStatus(.unknown)
}
```

Remove every task-state mutation from `refreshNow`, `render`, `handleRefreshFailure`, and `markRefreshFailed`. Reduce `setActivityStatus` to propagation only:

```swift
private func setActivityStatus(_ status: ActivityStatus) {
    activityPill.update(status: status)
    onActivityStatusChanged?(status)
}
```

Wire Hook integration state into the menu without adding another main-window label:

```swift
// AppDelegate properties
private var activityIntegrationMenuItem: NSMenuItem?

// applicationDidFinishLaunching
controller.onActivityIntegrationChanged = { [weak self] installed in
    self?.updateActivityIntegration(installed)
}

// configureStatusItem, immediately after activityItem
let integrationItem = NSMenuItem(title: "状态监听：检查中", action: nil, keyEquivalent: "")
menu.addItem(integrationItem)
activityIntegrationMenuItem = integrationItem

private func updateActivityIntegration(_ installed: Bool) {
    activityIntegrationMenuItem?.title = installed
        ? "状态监听：完整"
        : "状态监听：需安装 Hooks"
    activityIntegrationMenuItem?.toolTip = installed
        ? "Codex Meter 正在读取完整本地任务状态"
        : "在项目目录运行 npm run install:hooks，然后重启 Codex"
}
```

- [ ] **Step 5: Run the model, style, and complete Node tests**

Run the commands from Step 2, then `npm test`.

Expected: all tests pass and no test expects the old 2.8-second quota lifecycle.

- [ ] **Step 6: Commit activity polling separation**

```bash
git add FloatingWindow/QuotaModels.swift FloatingWindowTests/QuotaModelsTests.swift FloatingWindow/main.swift test/floating-style.test.js
git commit -m "Poll real activity independently from quota"
```

---

### Task 6: Approved Three-Lamp Signal Strip

**Files:**
- Modify: `FloatingWindow/main.swift:27-115,450-555,570-690,890-1090`
- Modify: `test/floating-style.test.js`

**Interfaces:**
- Consumes: `ActivityStatus` updates from Task 5.
- Produces: reusable `ActivitySignalView` for expanded and capsule windows.
- Keeps menu bar representation as one active semantic dot plus quota values.

- [ ] **Step 1: Write source-level visual contract tests**

Replace old `ActivityPillView` size assertions with:

```js
test("native activity signal uses three persistent lamps without layout shift", () => {
  const source = readMainSwift();
  assert.match(source, /final\s+class\s+SignalLampView/);
  assert.match(source, /final\s+class\s+ActivitySignalView/);
  assert.match(source, /redLamp/);
  assert.match(source, /yellowLamp/);
  assert.match(source, /greenLamp/);
  assert.match(source, /widthAnchor\.constraint\(equalToConstant:\s*84\)/);
  assert.match(source, /heightAnchor\.constraint\(equalToConstant:\s*22\)/);
  assert.match(source, /widthAnchor\.constraint\(equalToConstant:\s*8\)/);
  assert.match(source, /shadowRadius\s*=\s*4/);
  assert.match(source, /accessibilityDisplayShouldReduceMotion/);
  assert.match(source, /CATransaction\.setAnimationDuration\(0\.2\)/);
  assert.doesNotMatch(source, /ActivityPillView/);
});

test("capsule reuses the three-lamp activity signal", () => {
  const source = readMainSwift();
  assert.match(source, /private\s+let\s+activityCapsuleSignal\s*=\s*ActivitySignalView/);
  assert.doesNotMatch(source, /dotCapsuleLabel/);
});
```

- [ ] **Step 2: Run the style test and verify RED**

Run: `node --test test/floating-style.test.js`

Expected: FAIL because `ActivityPillView` still exists and only one dot is rendered.

- [ ] **Step 3: Implement the lamp and fixed-size signal strip**

```swift
final class SignalLampView: NSView {
    private let semanticColor: NSColor

    init(color: NSColor) {
        semanticColor = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.shadowRadius = 4
        layer?.shadowOffset = .zero
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 8),
            heightAnchor.constraint(equalToConstant: 8)
        ])
        setActive(false)
    }

    required init?(coder: NSCoder) { nil }

    func setActive(_ active: Bool) {
        layer?.backgroundColor = semanticColor.withAlphaComponent(active ? 1 : 0.18).cgColor
        layer?.shadowColor = semanticColor.cgColor
        layer?.shadowOpacity = active ? 0.42 : 0
    }
}

final class ActivitySignalView: NSView {
    private let redLamp = SignalLampView(color: .systemRed)
    private let yellowLamp = SignalLampView(color: .systemYellow)
    private let greenLamp = SignalLampView(color: .systemGreen)
    private let textLabel = NSTextField(labelWithString: ActivityStatus.idle.label)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.44).cgColor

        textLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        textLabel.alignment = .left
        textLabel.lineBreakMode = .byClipping
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        let lamps = NSStackView(views: [redLamp, yellowLamp, greenLamp])
        lamps.orientation = .horizontal
        lamps.spacing = 4
        lamps.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lamps)
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 84),
            heightAnchor.constraint(equalToConstant: 22),
            lamps.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            lamps.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLabel.leadingAnchor.constraint(equalTo: lamps.trailingAnchor, constant: 5),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        update(status: .idle, animated: false)
    }

    required init?(coder: NSCoder) { nil }

    func update(status: ActivityStatus, animated: Bool = true) {
        let apply = {
            self.redLamp.setActive(status == .waiting)
            self.yellowLamp.setActive(status == .working)
            self.greenLamp.setActive(status == .done)
            self.textLabel.font = .systemFont(
                ofSize: status == .unknown ? 8.5 : 10,
                weight: .semibold
            )
            self.textLabel.stringValue = status.label
            self.setAccessibilityLabel(status.menuTitle)
            self.toolTip = status.menuTitle
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            apply()
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        apply()
        CATransaction.commit()
    }
}
```

The exceptional `状态未知` label uses 8.5 pt so it fits the fixed label area; all four normal labels remain 10 pt. Its menu-bar dot uses the neutral `ActivityStatus.unknown.color` from Task 5.

- [ ] **Step 4: Replace expanded and capsule status views**

In `QuotaViewController`:

```swift
private let activityPill = ActivitySignalView()
```

In `CapsuleViewController`, replace the single dot and activity label with:

```swift
private let activityCapsuleSignal = ActivitySignalView()
private let quotaCapsuleLabel = NSTextField(labelWithString: "--/--")

func updateActivityStatus(_ status: ActivityStatus) {
    currentActivityStatus = status
    activityCapsuleSignal.update(status: status)
    updateTooltip()
}
```

Build the capsule stack from `[activityCapsuleSignal, quotaCapsuleLabel]`. Keep the capsule width `156 pt`, the quota label width `52 pt`, and stack spacing `6 pt`.

- [ ] **Step 5: Run style tests and build the app**

Run:

```bash
node --test test/floating-style.test.js
zsh scripts/build-floating-window.sh
```

Expected: style tests pass; build completes without warnings or errors.

- [ ] **Step 6: Commit the approved visual treatment**

```bash
git add FloatingWindow/main.swift test/floating-style.test.js
git commit -m "Add three-lamp activity signal"
```

---

### Task 7: Documentation, Installation, And End-To-End Verification

**Files:**
- Modify: `README.md`
- Modify: `test/project-packaging.test.js`
- Modify: `launch-floating-window.command` only if runtime detection needs correction during verification.

**Interfaces:**
- Consumes: `npm run install:hooks`, `/api/activity`, and the native app from prior tasks.
- Produces: documented setup, privacy behavior, restart requirement, and verified live state flow.

- [ ] **Step 1: Write failing packaging expectations**

Add assertions:

```js
assert.match(readme, /npm run install:hooks/);
assert.match(readme, /重启 Codex/);
assert.match(readme, /每秒读取本地状态/);
assert.match(readme, /不记录提示词/);
assert.match(readme, /waiting > working > done > idle/);
assert.match(gitignore, /^\.superpowers\/$/m);
assert.equal(pkg.scripts["install:hooks"], "node scripts/install-activity-hooks.js");
```

- [ ] **Step 2: Run packaging tests and verify RED**

Run: `node --test test/project-packaging.test.js`

Expected: FAIL because README does not yet document Hook installation or activity privacy.

- [ ] **Step 3: Update README with exact operating steps**

Document this sequence in Chinese and English:

```bash
npm run install:hooks
./launch-floating-window.command
```

State that Codex must be restarted once after Hook installation, the app reads local status once per second, quota still refreshes once per minute, Hook files contain only session ID/status/timestamp, and no model request or quota is consumed. Document the state priority exactly as `waiting > working > done > idle`.

- [ ] **Step 4: Run the complete automated verification suite**

Run:

```bash
npm test
swiftc -module-cache-path build/swift-module-cache FloatingWindowTests/QuotaModelsTests.swift FloatingWindow/QuotaModels.swift -o /private/tmp/quota-models-test
/private/tmp/quota-models-test
zsh scripts/build-floating-window.sh
git diff --check
```

Expected: all Node tests pass, Swift model executable exits 0, native app builds, and `git diff --check` reports no whitespace errors.

- [ ] **Step 5: Install Hooks on the current Mac with explicit approval**

Run outside the workspace only after the user approves the `~/.codex` write:

```bash
npm run install:hooks
```

Expected: existing `~/.codex/hooks.json` is backed up and preserved; six Codex Meter hook entries are present exactly once. Do not restart or quit Codex without explicit user direction; tell the user a restart is required for live waiting-state capture.

- [ ] **Step 6: Verify the local API without model calls**

Run:

```bash
curl -sS http://127.0.0.1:5487/api/activity
curl -sS http://127.0.0.1:5487/api/rate-limits
```

Expected: activity JSON contains only status/timestamps/counts/source/integration state; quota JSON remains unchanged. Compare quota before and after local polling and confirm no additional model conversation or request is created.

- [ ] **Step 7: Run visual and real-state QA**

Open the rebuilt app, then verify these states with controlled local fixtures first:

1. `idle`: all three lamps dim, text `空闲`.
2. `working`: yellow lamp active, text `工作中`.
3. `waiting`: red lamp active, text `待确认`.
4. `done`: green lamp active for 8 seconds, then idle.
5. `unknown`: all lamps dim and text `状态未知` only after 10 seconds of endpoint failure.

Capture and inspect screenshots for expanded/capsule modes in both cream-blue and minimalist themes. Confirm the Codex title remains centered, right-side controls do not overlap the 84 pt signal strip, labels do not clip, and the menu bar remains compact.

After Codex restart, start a real task and verify the full sequence:

```text
working -> waiting -> working -> done (8s) -> idle
```

- [ ] **Step 8: Commit documentation and verification updates**

```bash
git add README.md test/project-packaging.test.js launch-floating-window.command
git commit -m "Document real Codex activity monitoring"
```

- [ ] **Step 9: Final review and repository status**

Run:

```bash
git status --short
git log --oneline -8
```

Expected: clean worktree and seven focused implementation commits after the design commit.
