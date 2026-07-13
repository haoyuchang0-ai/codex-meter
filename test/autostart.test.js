const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const projectRoot = path.join(__dirname, "..");
const watcherPath = path.join(
  projectRoot,
  "scripts",
  "codex-lifecycle-watcher.sh",
);
const managerPath = path.join(projectRoot, "scripts", "manage-autostart.sh");

function makeWatcherRoot() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-watcher-"));
  const launcher = path.join(root, "launch.command");
  fs.writeFileSync(launcher, "#!/bin/zsh\nexit 0\n", { mode: 0o755 });
  return root;
}

function runWatcher(sequence, root = makeWatcherRoot()) {
  const eventLog = path.join(root, "events.log");
  const result = spawnSync("/bin/zsh", [watcherPath], {
    cwd: projectRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      CODEX_METER_ROOT: root,
      CODEX_METER_LAUNCHER: path.join(root, "launch.command"),
      CODEX_METER_TEST_SEQUENCE: sequence,
      CODEX_METER_EVENT_LOG: eventLog,
      CODEX_METER_DRY_RUN: "1",
      CODEX_METER_POLL_SECONDS: "0",
    },
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const events = fs.existsSync(eventLog)
    ? fs.readFileSync(eventLog, "utf8").trim().split("\n").filter(Boolean)
    : [];
  return { events, root };
}

test("watcher launches once per Codex session and stops on exit", () => {
  const { events } = runWatcher("-,101,101,-,202");

  assert.deepEqual(events, ["launch:101", "stop:101", "launch:202"]);
});

test("watcher restart respects manual quit in the same Codex session", () => {
  const root = makeWatcherRoot();
  assert.deepEqual(runWatcher("301", root).events, ["launch:301"]);

  fs.rmSync(path.join(root, "events.log"));
  assert.deepEqual(runWatcher("301", root).events, []);
});

test("autostart installer writes a persistent user LaunchAgent", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "codex-meter-home-"));
  const fakeLaunchctl = path.join(home, "launchctl");
  fs.writeFileSync(fakeLaunchctl, "#!/bin/zsh\nexit 0\n", { mode: 0o755 });

  const result = spawnSync("/bin/zsh", [managerPath, "install"], {
    cwd: projectRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      CODEX_METER_HOME: home,
      CODEX_METER_LAUNCHCTL: fakeLaunchctl,
      CODEX_METER_DRY_RUN: "1",
    },
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const plistPath = path.join(
    home,
    "Library",
    "LaunchAgents",
    "com.haoyuchang.codex-meter.plist",
  );
  const plist = fs.readFileSync(plistPath, "utf8");
  const manager = fs.readFileSync(managerPath, "utf8");
  assert.match(plist, /codex-lifecycle-watcher\.sh/);
  assert.match(plist, /Application Support\/CodexMeter\/runtime/);
  assert.match(plist, /<key>RunAtLoad<\/key>[\s\S]*<true\/>/);
  assert.match(plist, /<key>KeepAlive<\/key>[\s\S]*<true\/>/);
  assert.match(
    manager,
    /CODEX_METER_DRY_RUN=0\s+\/bin\/zsh\s+"\$WATCHER"\s+--stop/,
  );
  assert.equal(
    fs.existsSync(
      path.join(
        home,
        "Library",
        "Application Support",
        "CodexMeter",
        "runtime",
        "server.js",
      ),
    ),
    true,
  );
});
