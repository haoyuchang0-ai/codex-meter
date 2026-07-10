const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { resolveCodexCli } = require("../src/codex-app-server-client");

test("Codex app-server client prefers an explicit CODEX_CLI path", () => {
  const resolved = resolveCodexCli({
    env: {
      CODEX_CLI: "/custom/codex",
      PATH: "/usr/local/bin",
    },
    existsSync: () => true,
  });

  assert.equal(resolved, "/custom/codex");
});

test("Codex app-server client resolves the ChatGPT bundled codex on macOS", () => {
  const chatGptCodex = "/Applications/ChatGPT.app/Contents/Resources/codex";
  const codexAppCodex = "/Applications/Codex.app/Contents/Resources/codex";
  const resolved = resolveCodexCli({
    env: {
      PATH: "/usr/local/bin",
    },
    existsSync: (candidate) => candidate === chatGptCodex || candidate === codexAppCodex,
  });

  assert.equal(resolved, chatGptCodex);
});

test("Codex app-server client falls back to codex on PATH", () => {
  const pathCodex = path.join("/opt/dev/bin", "codex");
  const resolved = resolveCodexCli({
    env: {
      PATH: ["/opt/dev/bin", "/usr/local/bin"].join(path.delimiter),
    },
    existsSync: (candidate) => candidate === pathCodex,
  });

  assert.equal(resolved, pathCodex);
});
