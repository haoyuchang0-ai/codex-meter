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

test("rebuilds cached events after a same-size rollout rotation", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-rotation-"));
  const sessionsRoot = path.join(root, "sessions");
  const dateDir = path.join(sessionsRoot, "2026", "07", "10");
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
    now: () => Date.parse("2026-07-10T02:23:07.016Z"),
  });
  assert.equal(monitor.snapshot().status, "working");

  fs.renameSync(rolloutPath, `${rolloutPath}.1`);
  fs.writeFileSync(rolloutPath, completed);

  assert.equal(monitor.snapshot().status, "done");
});
