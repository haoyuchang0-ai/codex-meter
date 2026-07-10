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
