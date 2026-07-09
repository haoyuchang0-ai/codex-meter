const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

test("project README documents GitHub-ready usage in Chinese and English", () => {
  const readme = read("README.md");

  assert.match(readme, /# Codex Meter/);
  assert.match(readme, /## 功能/);
  assert.match(readme, /## Quick Start/);
  assert.match(readme, /## Build the macOS App/);
  assert.match(readme, /不会主动创建 Codex 对话/);
  assert.match(readme, /does not create Codex conversations/);
});

test("project metadata uses the GitHub repository name", () => {
  const pkg = JSON.parse(read("package.json"));

  assert.equal(pkg.name, "codex-meter");
  assert.equal(pkg.repository.url, "git+https://github.com/haoyuchang0-ai/codex-meter.git");
});

test("project ignores local-only generated files", () => {
  const gitignore = read(".gitignore");

  assert.match(gitignore, /^\.DS_Store$/m);
  assert.match(gitignore, /^node_modules\/$/m);
  assert.match(gitignore, /^build\/$/m);
  assert.match(gitignore, /^CodexQuotaFloat\.app\/$/m);
  assert.match(gitignore, /^quota-window\.log$/m);
});

test("launcher is portable and builds the native app when missing", () => {
  const launcher = read("launch-floating-window.command");

  assert.doesNotMatch(launcher, /\/Users\/changhaoyu/);
  assert.match(launcher, /command -v node/);
  assert.match(launcher, /scripts\/build-floating-window\.sh/);
  assert.match(launcher, /CodexQuotaFloat\.app/);
});

test("launcher only requires Node when it needs to start the local service", () => {
  const launcher = read("launch-floating-window.command");

  assert.ok(
    launcher.indexOf('/usr/bin/curl -fsS "$HEALTH_URL"') <
      launcher.indexOf('command -v node'),
  );
});
