const test = require("node:test");
const assert = require("node:assert/strict");

const { mergeActivityTasks } = require("../src/activity-tasks");

test("merges active states with thread names without exposing previews", () => {
  const tasks = mergeActivityTasks({
    activeStates: [
      { threadId: "thread-working", status: "working", updatedAtMs: 2000 },
      { threadId: "thread-waiting", status: "waiting", updatedAtMs: 3000 },
      { threadId: "thread-done", status: "done", updatedAtMs: 4000 },
    ],
    threads: [
      { id: "thread-working", name: "Build dashboard", preview: "private prompt" },
      { id: "thread-waiting", name: "  Review approval  ", preview: "private prompt" },
      { id: "thread-done", name: "Finished", preview: "private prompt" },
    ],
  });

  assert.deepEqual(tasks, [
    { threadId: "thread-waiting", title: "Review approval", status: "waiting", updatedAt: new Date(3000).toISOString() },
    { threadId: "thread-working", title: "Build dashboard", status: "working", updatedAt: new Date(2000).toISOString() },
  ]);
  assert.doesNotMatch(JSON.stringify(tasks), /private prompt|preview/);
});

test("uses a neutral title when Codex has no thread name", () => {
  assert.deepEqual(mergeActivityTasks({
    activeStates: [{ threadId: "thread-1", status: "working", updatedAtMs: 1000 }],
    threads: [{ id: "thread-1", name: "", preview: "do not expose" }],
  }), [{
    threadId: "thread-1",
    title: "未命名任务",
    status: "working",
    updatedAt: new Date(1000).toISOString(),
  }]);
});

test("excludes states that are not navigable top-level Codex tasks", () => {
  assert.deepEqual(mergeActivityTasks({
    activeStates: [
      { threadId: "top-level", status: "working", updatedAtMs: 3000 },
      { threadId: "subtask", status: "working", updatedAtMs: 2000 },
      { threadId: "missing", status: "working", updatedAtMs: 1000 },
    ],
    threads: [
      { id: "top-level", name: "Visible", parentThreadId: null },
      { id: "subtask", name: "Hidden", parentThreadId: "top-level" },
    ],
  }), [{
    threadId: "top-level",
    title: "Visible",
    status: "working",
    updatedAt: new Date(3000).toISOString(),
  }]);
});
