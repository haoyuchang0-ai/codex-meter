const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

const { createRequestHandler, readActivityTasks } = require("../server");

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

test("GET /api/activity/tasks returns the local navigation list", async () => {
  const snapshot = {
    fetchedAt: "2026-07-10T02:23:05.016Z",
    source: "local",
    tasks: [{
      threadId: "019f0000-0000-7000-8000-000000000001",
      title: "Quota window polish",
      status: "working",
      updatedAt: "2026-07-10T02:23:04.016Z",
    }],
  };
  const server = http.createServer(createRequestHandler({
    rateLimitReader: async () => ({ windows: [] }),
    activityReader: () => ({ status: "working" }),
    activityTasksReader: async () => snapshot,
  }));
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const address = server.address();
  const body = await new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${address.port}/api/activity/tasks`, (response) => {
      let text = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => { text += chunk; });
      response.on("end", () => resolve(text));
    }).on("error", reject);
  });
  server.close();

  assert.deepEqual(JSON.parse(body), snapshot);
  assert.doesNotMatch(body, /preview|prompt|cwd|path/);
});

test("activity task lookup fails instead of pretending an unavailable index is empty", async () => {
  await assert.rejects(
    readActivityTasks({
      monitor: {
        activeTasks: () => [{ threadId: "thread-1", status: "working", updatedAtMs: 1000 }],
      },
      appServerClient: {
        request: async () => { throw new Error("index unavailable"); },
      },
    }),
    /index unavailable/,
  );
});

test("activity task lookup requests only navigable top-level interactive tasks", async () => {
  let capturedRequest;
  const snapshot = await readActivityTasks({
    monitor: {
      activeTasks: () => [{ threadId: "thread-1", status: "working", updatedAtMs: 1000 }],
    },
    appServerClient: {
      request: async (method, params) => {
        capturedRequest = { method, params };
        return { data: [{ id: "thread-1", name: "Visible", parentThreadId: null }] };
      },
    },
  });

  assert.equal(capturedRequest.method, "thread/list");
  assert.equal(capturedRequest.params.parentThreadId, null);
  assert.equal(capturedRequest.params.useStateDbOnly, true);
  assert.equal(capturedRequest.params.sourceKinds, undefined);
  assert.deepEqual(snapshot.tasks.map(({ threadId, title, status }) => ({ threadId, title, status })), [{
    threadId: "thread-1",
    title: "Visible",
    status: "working",
  }]);
});

test("activity task lookup follows cursors until every active task is found", async () => {
  const cursors = [];
  const snapshot = await readActivityTasks({
    monitor: {
      activeTasks: () => [{ threadId: "thread-2", status: "working", updatedAtMs: 1000 }],
    },
    appServerClient: {
      request: async (_method, params) => {
        cursors.push(params.cursor ?? null);
        if (!params.cursor) {
          return {
            data: [{ id: "thread-1", name: "Other", parentThreadId: null }],
            nextCursor: "page-2",
          };
        }
        return {
          data: [{ id: "thread-2", name: "Target", parentThreadId: null }],
          nextCursor: null,
        };
      },
    },
  });

  assert.deepEqual(cursors, [null, "page-2"]);
  assert.equal(snapshot.tasks[0].title, "Target");
});
