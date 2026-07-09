const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const { CodexAppServerClient } = require("./src/codex-app-server-client");
const { normalizeRateLimitSnapshot } = require("./src/normalize");

const PORT = Number(process.env.PORT || 5487);
const HOST = process.env.HOST || "127.0.0.1";
const PUBLIC_DIR = path.join(__dirname, "public");

const client = new CodexAppServerClient();

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(body);
}

function sendStatic(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
  const normalizedPath = path.normalize(pathname).replace(/^(\.\.[/\\])+/, "");
  const filePath = path.join(PUBLIC_DIR, normalizedPath);

  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  fs.readFile(filePath, (error, data) => {
    if (error) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }

    const ext = path.extname(filePath);
    res.writeHead(200, {
      "content-type": contentTypes[ext] || "application/octet-stream",
      "cache-control": "no-store",
    });
    res.end(data);
  });
}

async function readRateLimits() {
  const payload = await client.request("account/rateLimits/read");
  const normalized = normalizeRateLimitSnapshot(payload);
  delete normalized.raw;

  return {
    fetchedAt: new Date().toISOString(),
    source: "codex-app-server",
    ...normalized,
  };
}

const server = http.createServer(async (req, res) => {
  if (req.url === "/api/health") {
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.url === "/api/rate-limits") {
    try {
      const data = await readRateLimits();
      sendJson(res, 200, data);
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
});

server.listen(PORT, HOST, () => {
  console.log(`Codex quota window: http://${HOST}:${PORT}`);
});

function shutdown() {
  client.close();
  server.close(() => {
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
