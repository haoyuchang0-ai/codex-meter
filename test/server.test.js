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
