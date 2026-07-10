const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const { installActivityHooks } = require("../src/hook-installer");

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
