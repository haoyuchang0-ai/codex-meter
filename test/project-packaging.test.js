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
  assert.match(readme, /胶囊模式/);
  assert.match(readme, /菜单栏/);
  assert.match(readme, /待确认/);
  assert.match(readme, /工作中/);
  assert.match(readme, /已完成/);
  assert.match(readme, /空闲/);
  assert.match(readme, /Capsule mode/);
  assert.match(readme, /menu bar/);
  assert.match(readme, /Waiting/);
  assert.match(readme, /Working/);
  assert.match(readme, /Done/);
  assert.match(readme, /Idle/);
  assert.match(readme, /ChatGPT\.app/);
  assert.match(readme, /CODEX_CLI/);
  assert.match(readme, /不会主动创建 Codex 对话/);
  assert.match(readme, /does not create Codex conversations/);
  assert.match(readme, /npm run install:hooks/);
  assert.match(readme, /重启一次 Codex/);
  assert.match(readme, /每秒从本机读取一次/);
  assert.match(readme, /不记录提示词/);
  assert.match(readme, /waiting > working > done > idle/);
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
  assert.match(gitignore, /^quota-window\.pid$/m);
  assert.match(gitignore, /^\.superpowers\/$/m);
});

test("project exposes the local Hook installer", () => {
  const pkg = JSON.parse(read("package.json"));

  assert.equal(pkg.scripts["install:hooks"], "node scripts/install-activity-hooks.js");
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

test("launcher keeps the local quota service alive after launch", () => {
  const launcher = read("launch-floating-window.command");

  assert.match(launcher, /PID_FILE="\$ROOT\/quota-window\.pid"/);
  assert.match(launcher, /codex-primary-runtime\/dependencies\/node\/bin\/node/);
  assert.match(launcher, /nohup\s+"\$NODE_BIN"\s+server\.js/);
  assert.match(launcher, /echo\s+\$!\s+>\s+"\$PID_FILE"/);
  assert.match(launcher, /disown/);
});

test("native build signs the complete app bundle after replacing its executable", () => {
  const buildScript = read("scripts/build-floating-window.sh");

  assert.match(buildScript, /codesign\s+--force\s+--deep\s+--sign\s+-\s+"\$APP_DIR"/);
});

test("native build retries the compatible Command Line Tools SDK", () => {
  const buildScript = read("scripts/build-floating-window.sh");

  assert.match(buildScript, /FALLBACK_SDK=.*MacOSX15\.4\.sdk/);
  assert.match(buildScript, /if\s+!\s+swiftc\s+-sdk\s+"\$SDK_PATH"/);
  assert.match(buildScript, /swiftc\s+-sdk\s+"\$FALLBACK_SDK"/);
});
