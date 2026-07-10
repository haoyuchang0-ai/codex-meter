const fs = require("node:fs");
const path = require("node:path");

const HOOKS = [
  ["SessionStart", "startup|resume|clear", "idle"],
  ["UserPromptSubmit", null, "working"],
  ["PermissionRequest", "*", "waiting"],
  ["PreToolUse", "request_user_input", "waiting"],
  ["PostToolUse", "request_user_input", "working"],
  ["Stop", null, "done"],
];

function groupFor(matcher, status) {
  const group = {
    hooks: [{
      type: "command",
      command: `python3 "\${CODEX_HOME:-$HOME/.codex}/hooks/codex-meter-state.py" ${status}`,
    }],
  };
  if (matcher) group.matcher = matcher;
  return group;
}

function installActivityHooks({ codexHome, sourceScript, now = Date.now }) {
  const hooksDir = path.join(codexHome, "hooks");
  const configPath = path.join(codexHome, "hooks.json");
  fs.mkdirSync(hooksDir, { recursive: true });
  fs.copyFileSync(sourceScript, path.join(hooksDir, "codex-meter-state.py"));

  const config = fs.existsSync(configPath)
    ? JSON.parse(fs.readFileSync(configPath, "utf8"))
    : { hooks: {} };
  config.hooks = config.hooks || {};

  let changed = false;
  for (const [event, matcher, status] of HOOKS) {
    config.hooks[event] = config.hooks[event] || [];
    const desiredGroup = groupFor(matcher, status);
    const desiredCommand = desiredGroup.hooks[0].command;
    const alreadyInstalled = config.hooks[event].some((group) => (
      Array.isArray(group.hooks) && group.hooks.some((hook) => hook.command === desiredCommand)
    ));
    if (!alreadyInstalled) {
      config.hooks[event].push(desiredGroup);
      changed = true;
    }
  }

  let backupPath = null;
  if (changed && fs.existsSync(configPath)) {
    backupPath = `${configPath}.codex-meter-backup-${now()}`;
    fs.copyFileSync(configPath, backupPath);
  }
  if (changed) {
    const temporary = `${configPath}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`);
    fs.renameSync(temporary, configPath);
  }
  return { changed, backupPath };
}

module.exports = { installActivityHooks };
