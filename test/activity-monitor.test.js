const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { ActivityMonitor } = require("../src/activity-monitor");

const NOW_MS = Date.parse("2026-07-10T02:23:07.016Z");
const RECENT_FILE_MS = 48 * 60 * 60 * 1_000;
const THREAD_ID = "019f0000-0000-7000-8000-000000000001";

function dateDirectory(sessionsRoot, nowMs, daysAgo = 0) {
  const date = new Date(nowMs);
  date.setDate(date.getDate() - daysAgo);
  return path.join(
    sessionsRoot,
    String(date.getFullYear()).padStart(4, "0"),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  );
}

function rolloutLine(type, timestamp, turnId = "turn-1", extraPayload = {}) {
  return JSON.stringify({
    timestamp,
    type: "event_msg",
    payload: { type, turn_id: turnId, ...extraPayload },
  });
}

function rolloutPathIn(sessionsRoot, nowMs = NOW_MS) {
  const dateDir = dateDirectory(sessionsRoot, nowMs);
  fs.mkdirSync(dateDir, { recursive: true });
  return path.join(dateDir, `rollout-${THREAD_ID}.jsonl`);
}

test("reads rollout and hook state without returning private content", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-activity-"));
  const sessionsRoot = path.join(root, "sessions");
  const hookStateRoot = path.join(root, "activity");
  const dateDir = dateDirectory(sessionsRoot, NOW_MS);
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
    now: () => NOW_MS,
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

test("rebuilds cached events after a same-size rollout rotation", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-rotation-"));
  const sessionsRoot = path.join(root, "sessions");
  const dateDir = dateDirectory(sessionsRoot, NOW_MS);
  fs.mkdirSync(dateDir, { recursive: true });
  const rolloutPath = path.join(
    dateDir,
    "rollout-019f0000-0000-7000-8000-000000000001.jsonl",
  );
  const started = JSON.stringify({
    timestamp: "2026-07-10T02:23:05.016Z",
    type: "event_msg",
    payload: { type: "task_started", turn_id: "turn-1" },
  });
  const completed = `${JSON.stringify({
    timestamp: "2026-07-10T02:23:06.016Z",
    type: "event_msg",
    payload: { type: "task_complete", turn_id: "turn-1" },
  })}\n`;
  fs.writeFileSync(rolloutPath, `${started}${" ".repeat(completed.length - started.length - 1)}\n`);

  const monitor = new ActivityMonitor({
    sessionsRoot,
    now: () => NOW_MS,
  });
  assert.equal(monitor.snapshot().status, "working");

  fs.renameSync(rolloutPath, `${rolloutPath}.1`);
  fs.writeFileSync(rolloutPath, completed);

  assert.equal(monitor.snapshot().status, "done");
});

test("rebuilds cached events after a same-size in-place rollout rewrite", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-rewrite-"));
  const sessionsRoot = path.join(root, "sessions");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  const started = rolloutLine("task_started", "2026-07-10T02:23:05.016Z");
  const completed = `${rolloutLine("task_complete", "2026-07-10T02:23:06.016Z")}\n`;
  const startedPadded = `${started}${" ".repeat(completed.length - started.length - 1)}\n`;
  fs.writeFileSync(rolloutPath, startedPadded);
  const initialTime = new Date(NOW_MS - 2_000);
  fs.utimesSync(rolloutPath, initialTime, initialTime);

  const fsImpl = Object.create(fs);
  fsImpl.statSync = (filePath) => {
    const stat = fs.statSync(filePath);
    return { ino: stat.ino, size: stat.size, mtimeMs: stat.mtimeMs };
  };
  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS, fsImpl });
  assert.equal(monitor.snapshot().status, "working");
  const initialStat = fs.statSync(rolloutPath);

  fs.writeFileSync(rolloutPath, completed);
  const rewrittenTime = new Date(NOW_MS - 1_000);
  fs.utimesSync(rolloutPath, rewrittenTime, rewrittenTime);
  const rewrittenStat = fs.statSync(rolloutPath);
  assert.equal(rewrittenStat.ino, initialStat.ino);
  assert.equal(rewrittenStat.size, initialStat.size);
  assert.notEqual(rewrittenStat.mtimeMs, initialStat.mtimeMs);

  assert.equal(monitor.snapshot().status, "done");
});

test("enumerates only the three local date directories in the 48-hour window", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-dates-"));
  const sessionsRoot = path.join(root, "sessions");
  const expectedDirectories = [0, 1, 2].map((daysAgo) => dateDirectory(
    sessionsRoot,
    NOW_MS,
    daysAgo,
  ));
  for (const directory of expectedDirectories) fs.mkdirSync(directory, { recursive: true });
  fs.mkdirSync(path.join(sessionsRoot, "2020", "01", "01"), { recursive: true });

  const enumerated = [];
  const fsImpl = Object.create(fs);
  fsImpl.readdirSync = (directory, options) => {
    enumerated.push(directory);
    return fs.readdirSync(directory, options);
  };

  const monitor = new ActivityMonitor({
    sessionsRoot,
    hookStateRoot: path.join(root, "activity"),
    hooksConfigPath: path.join(root, "hooks.json"),
    now: () => NOW_MS,
    fsImpl,
  });
  monitor.snapshot();

  assert.deepEqual(enumerated.sort(), expectedDirectories.sort());
});

test("compacts cached rollout events to the latest event per thread and turn", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-compact-"));
  const sessionsRoot = path.join(root, "sessions");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  fs.writeFileSync(rolloutPath, [
    rolloutLine("task_started", "2026-07-10T02:23:03.016Z"),
    rolloutLine("task_complete", "2026-07-10T02:23:04.016Z"),
    rolloutLine("task_started", "2026-07-10T02:23:05.016Z"),
  ].join("\n") + "\n");

  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS });
  assert.equal(monitor.snapshot().status, "working");
  assert.equal(monitor.cache.get(rolloutPath).events.length, 1);
  assert.equal(monitor.cache.get(rolloutPath).events[0].status, "working");
});

test("globally compacts the latest thread and turn event across rollout files", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-cross-file-"));
  const sessionsRoot = path.join(root, "sessions");
  const dateDir = dateDirectory(sessionsRoot, NOW_MS);
  fs.mkdirSync(dateDir, { recursive: true });
  const olderPath = path.join(dateDir, `rollout-${THREAD_ID}.jsonl`);
  const newerPath = path.join(dateDir, `rollout-${THREAD_ID}-continued.jsonl`);
  fs.writeFileSync(
    olderPath,
    `${rolloutLine("task_started", "2026-07-10T02:23:04.016Z", "shared-turn")}\n`,
  );
  fs.writeFileSync(
    newerPath,
    `${rolloutLine("task_complete", "2026-07-10T02:23:06.016Z", "shared-turn")}\n`,
  );

  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS });
  assert.deepEqual(monitor.readRolloutEvents(), [{
    threadId: THREAD_ID,
    turnId: "shared-turn",
    status: "done",
    updatedAtMs: Date.parse("2026-07-10T02:23:06.016Z"),
  }]);
  assert.equal(monitor.cache.size, 2);
});

test("resets cached events when a rollout is truncated", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-truncate-"));
  const sessionsRoot = path.join(root, "sessions");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  fs.writeFileSync(rolloutPath, `${rolloutLine(
    "task_complete",
    "2026-07-10T02:23:04.016Z",
    "turn-before-truncate",
    { ignored: "x".repeat(500) },
  )}\n`);

  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS });
  assert.equal(monitor.snapshot().status, "done");

  fs.writeFileSync(rolloutPath, `${rolloutLine(
    "task_started",
    "2026-07-10T02:23:06.016Z",
    "turn-after-truncate",
  )}\n`);
  assert.equal(monitor.snapshot().status, "working");
  assert.equal(monitor.cache.get(rolloutPath).events.length, 1);
});

test("evicts cached events when a rollout disappears", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-evict-"));
  const sessionsRoot = path.join(root, "sessions");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  fs.writeFileSync(
    rolloutPath,
    `${rolloutLine("task_started", "2026-07-10T02:23:06.016Z")}\n`,
  );

  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS });
  assert.equal(monitor.snapshot().status, "working");
  assert.equal(monitor.cache.size, 1);

  fs.unlinkSync(rolloutPath);
  assert.equal(monitor.snapshot().status, "idle");
  assert.equal(monitor.cache.size, 0);
});

test("excludes rollout files older than 48 hours", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-stale-"));
  const sessionsRoot = path.join(root, "sessions");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  fs.writeFileSync(
    rolloutPath,
    `${rolloutLine("task_started", "2026-07-10T02:23:06.016Z")}\n`,
  );
  const staleTime = new Date(NOW_MS - RECENT_FILE_MS - 1);
  fs.utimesSync(rolloutPath, staleTime, staleTime);

  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS });
  assert.equal(monitor.snapshot().status, "idle");
  assert.equal(monitor.cache.size, 0);
});

test("ignores malformed rollout, hook-state, and hook-config JSON", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-malformed-"));
  const sessionsRoot = path.join(root, "sessions");
  const hookStateRoot = path.join(root, "activity");
  const hooksConfigPath = path.join(root, "hooks.json");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  fs.mkdirSync(hookStateRoot, { recursive: true });
  fs.writeFileSync(rolloutPath, "{not-json}\n");
  fs.writeFileSync(path.join(hookStateRoot, `${THREAD_ID}.json`), "{not-json}");
  fs.writeFileSync(hooksConfigPath, "{not-json}");

  const monitor = new ActivityMonitor({
    sessionsRoot,
    hookStateRoot,
    hooksConfigPath,
    now: () => NOW_MS,
  });
  assert.deepEqual(monitor.snapshot(), {
    status: "idle",
    updatedAt: new Date(NOW_MS).toISOString(),
    activeCount: 0,
    waitingCount: 0,
    source: "local",
    hooksInstalled: false,
  });
});

test("degrades safely when rollout and JSON files cannot be read", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-read-errors-"));
  const sessionsRoot = path.join(root, "sessions");
  const hookStateRoot = path.join(root, "activity");
  const hooksConfigPath = path.join(root, "hooks.json");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  fs.mkdirSync(hookStateRoot, { recursive: true });
  fs.writeFileSync(rolloutPath, `${rolloutLine("task_started", "2026-07-10T02:23:06.016Z")}\n`);
  fs.writeFileSync(path.join(hookStateRoot, `${THREAD_ID}.json`), "{}");
  fs.writeFileSync(hooksConfigPath, "{}");

  const fsImpl = Object.create(fs);
  fsImpl.openSync = () => { throw new Error("rollout read denied"); };
  fsImpl.readFileSync = () => { throw new Error("JSON read denied"); };
  const monitor = new ActivityMonitor({
    sessionsRoot,
    hookStateRoot,
    hooksConfigPath,
    now: () => NOW_MS,
    fsImpl,
  });

  assert.equal(monitor.snapshot().status, "idle");
  assert.equal(monitor.snapshot().hooksInstalled, false);
});

test("rereads an unfinished JSONL tail without caching its raw content", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-partial-"));
  const sessionsRoot = path.join(root, "sessions");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  const line = rolloutLine(
    "task_started",
    "2026-07-10T02:23:06.016Z",
    "turn-partial",
    { prompt: "private prompt" },
  );
  const splitAt = line.indexOf("private prompt") + 7;
  fs.writeFileSync(rolloutPath, line.slice(0, splitAt));

  const readPositions = [];
  const fsImpl = Object.create(fs);
  fsImpl.readSync = (descriptor, buffer, offset, length, position) => {
    readPositions.push(position);
    return fs.readSync(descriptor, buffer, offset, length, position);
  };
  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS, fsImpl });

  assert.equal(monitor.snapshot().status, "idle");
  assert.doesNotMatch(JSON.stringify([...monitor.cache.values()]), /private/);

  fs.appendFileSync(rolloutPath, `${line.slice(splitAt)}\n`);
  assert.equal(monitor.snapshot().status, "working");
  assert.deepEqual(readPositions, [0, 0]);
});

test("does not reread unchanged rollout bytes and reads appends from the cached offset", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-offset-"));
  const sessionsRoot = path.join(root, "sessions");
  const rolloutPath = rolloutPathIn(sessionsRoot);
  const started = `${rolloutLine("task_started", "2026-07-10T02:23:05.016Z")}\n`;
  fs.writeFileSync(rolloutPath, started);

  const readPositions = [];
  const fsImpl = Object.create(fs);
  fsImpl.readSync = (descriptor, buffer, offset, length, position) => {
    readPositions.push(position);
    return fs.readSync(descriptor, buffer, offset, length, position);
  };
  const monitor = new ActivityMonitor({ sessionsRoot, now: () => NOW_MS, fsImpl });
  monitor.snapshot();
  monitor.snapshot();
  fs.appendFileSync(
    rolloutPath,
    `${rolloutLine("task_complete", "2026-07-10T02:23:06.016Z")}\n`,
  );
  monitor.snapshot();

  assert.deepEqual(readPositions, [0, Buffer.byteLength(started)]);
});

test("detects hooks only from structured command entries", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-hook-structure-"));
  const hooksConfigPath = path.join(root, "hooks.json");
  const monitor = new ActivityMonitor({
    sessionsRoot: path.join(root, "sessions"),
    hookStateRoot: path.join(root, "activity"),
    hooksConfigPath,
  });

  fs.writeFileSync(hooksConfigPath, JSON.stringify({ note: "codex-meter-state.py" }));
  assert.equal(monitor.snapshot().hooksInstalled, false);

  fs.writeFileSync(hooksConfigPath, JSON.stringify({
    hooks: {
      Stop: [{ hooks: [{ type: "prompt", command: "codex-meter-state.py" }] }],
    },
  }));
  assert.equal(monitor.snapshot().hooksInstalled, false);

  fs.writeFileSync(hooksConfigPath, JSON.stringify({
    hooks: {
      metadata: { type: "command", command: "codex-meter-state.py" },
    },
  }));
  assert.equal(monitor.snapshot().hooksInstalled, false);
});
