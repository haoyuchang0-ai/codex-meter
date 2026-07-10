const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const { installActivityHooks } = require("../src/hook-installer");

const INTEGRATIONS = [
  ["SessionStart", "startup|resume|clear", "idle"],
  ["UserPromptSubmit", null, "working"],
  ["PermissionRequest", "*", "waiting"],
  ["PreToolUse", "request_user_input", "waiting"],
  ["PostToolUse", "request_user_input", "working"],
  ["Stop", null, "done"],
];

function commandFor(status) {
  return `python3 "\${CODEX_HOME:-$HOME/.codex}/hooks/codex-meter-state.py" ${status}`;
}

function matcherMatches(group, matcher) {
  return matcher === null
    ? !Object.prototype.hasOwnProperty.call(group, "matcher")
    : group.matcher === matcher;
}

function countIntendedIntegrations(config) {
  return INTEGRATIONS.reduce((count, [event, matcher, status]) => (
    count + (config.hooks[event] || []).filter((group) => (
      group && matcherMatches(group, matcher) && Array.isArray(group.hooks) &&
      group.hooks.some((hook) => (
        hook && hook.type === "command" && hook.command === commandFor(status)
      ))
    )).length
  ), 0);
}

function assertRejectedWithoutMutation(configText) {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-invalid-config-"));
  const hooksDir = path.join(codexHome, "hooks");
  const configPath = path.join(codexHome, "hooks.json");
  const installedWriter = path.join(hooksDir, "codex-meter-state.py");
  const sourceScript = path.join(codexHome, "source.py");
  fs.mkdirSync(hooksDir);
  fs.writeFileSync(sourceScript, "new writer\n");
  fs.writeFileSync(installedWriter, "existing writer\n");
  fs.writeFileSync(configPath, configText);

  assert.throws(() => installActivityHooks({ codexHome, sourceScript }));
  assert.equal(fs.readFileSync(configPath, "utf8"), configText);
  assert.equal(fs.readFileSync(installedWriter, "utf8"), "existing writer\n");
  assert.deepEqual(
    fs.readdirSync(codexHome).sort(),
    ["hooks", "hooks.json", "source.py"],
  );
  assert.deepEqual(fs.readdirSync(hooksDir), ["codex-meter-state.py"]);
}

test("installs Codex Meter hooks twice without duplicating or deleting existing hooks", () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-install-"));
  const sourceScript = path.join(codexHome, "source.py");
  fs.writeFileSync(sourceScript, "print('hook')\n");
  fs.writeFileSync(path.join(codexHome, "hooks.json"), JSON.stringify({
    hooks: {
      Stop: [{ hooks: [{ type: "command", command: "python3 existing.py" }] }],
    },
  }));

  const first = installActivityHooks({
    codexHome,
    sourceScript,
    now: () => 1783650000000,
  });
  const second = installActivityHooks({
    codexHome,
    sourceScript,
    now: () => 1783650001000,
  });
  const installed = JSON.parse(fs.readFileSync(path.join(codexHome, "hooks.json"), "utf8"));
  const serialized = JSON.stringify(installed);

  assert.equal(first.changed, true);
  assert.ok(first.backupPath.endsWith("hooks.json.codex-meter-backup-1783650000000"));
  assert.equal(second.changed, false);
  assert.match(serialized, /python3 existing\.py/);
  assert.equal((serialized.match(/codex-meter-state\.py/g) || []).length, 6);
  assert.equal(countIntendedIntegrations(installed), 6);
  assert.equal(
    fs.readFileSync(first.backupPath, "utf8"),
    JSON.stringify({
      hooks: {
        Stop: [{ hooks: [{ type: "command", command: "python3 existing.py" }] }],
      },
    }),
  );
});

for (const [label, config] of [
  ["null root", null],
  ["false root", false],
  ["string root", "hooks"],
  ["array root", []],
  ["null hooks", { hooks: null }],
  ["false hooks", { hooks: false }],
  ["string hooks", { hooks: "Stop" }],
  ["array hooks", { hooks: [] }],
]) {
  test(`rejects ${label} before mutating config or installed writer`, () => {
    assertRejectedWithoutMutation(JSON.stringify(config));
  });
}

test("matches installed hooks by event, matcher, type, and exact command", () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-matcher-"));
  const sourceScript = path.join(codexHome, "source.py");
  fs.writeFileSync(sourceScript, "print('hook')\n");
  fs.writeFileSync(path.join(codexHome, "hooks.json"), JSON.stringify({
    hooks: {
      SessionStart: [{
        matcher: "resume",
        hooks: [{ type: "command", command: commandFor("idle") }],
      }],
      UserPromptSubmit: [{
        matcher: "*",
        hooks: [{ type: "command", command: commandFor("working") }],
      }],
      PermissionRequest: [{
        matcher: "*",
        hooks: [{ type: "command", command: commandFor("waiting") }],
      }],
      Stop: [{
        hooks: [{ type: "prompt", command: commandFor("done") }],
      }],
    },
  }));

  const first = installActivityHooks({ codexHome, sourceScript });
  const second = installActivityHooks({ codexHome, sourceScript });
  const installed = JSON.parse(fs.readFileSync(path.join(codexHome, "hooks.json"), "utf8"));

  assert.equal(first.changed, true);
  assert.equal(second.changed, false);
  assert.equal(countIntendedIntegrations(installed), 6);
  assert.equal(installed.hooks.SessionStart[0].matcher, "resume");
  assert.equal(installed.hooks.UserPromptSubmit[0].matcher, "*");
  assert.equal(installed.hooks.Stop[0].hooks[0].type, "prompt");
});

test("hook writer persists only activity metadata for a valid thread", () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-writer-"));
  const threadId = "019f0000-0000-7000-8000-000000000001";
  const result = spawnSync("python3", [path.join(__dirname, "..", "scripts", "codex-meter-state.py"), "waiting"], {
    input: JSON.stringify({ session_id: threadId, prompt: "private prompt" }),
    encoding: "utf8",
    env: { ...process.env, CODEX_HOME: codexHome },
  });

  assert.equal(result.status, 0, result.stderr);
  const state = JSON.parse(fs.readFileSync(
    path.join(codexHome, "codex-meter", "activity", `${threadId}.json`),
    "utf8",
  ));
  assert.deepEqual(Object.keys(state).sort(), ["status", "threadId", "updatedAtMs"]);
  assert.equal(state.threadId, threadId);
  assert.equal(state.status, "waiting");
  assert.equal(Number.isFinite(state.updatedAtMs), true);
});

test("hook writer ignores invalid status and thread input", () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-writer-invalid-"));
  const writer = path.join(__dirname, "..", "scripts", "codex-meter-state.py");

  const invalidStatus = spawnSync("python3", [writer, "not-a-status"], {
    input: JSON.stringify({ session_id: "019f0000-0000-7000-8000-000000000001" }),
    encoding: "utf8",
    env: { ...process.env, CODEX_HOME: codexHome },
  });
  const invalidThread = spawnSync("python3", [writer, "working"], {
    input: JSON.stringify({ session_id: "private" }),
    encoding: "utf8",
    env: { ...process.env, CODEX_HOME: codexHome },
  });

  assert.equal(invalidStatus.status, 0, invalidStatus.stderr);
  assert.equal(invalidThread.status, 0, invalidThread.stderr);
  assert.equal(fs.existsSync(path.join(codexHome, "codex-meter")), false);
});
