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

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function matcherMatches(group, matcher) {
  return matcher === null
    ? !Object.prototype.hasOwnProperty.call(group, "matcher")
    : group.matcher === matcher;
}

function containsIntegration(group, matcher, command) {
  return isPlainObject(group) && matcherMatches(group, matcher) &&
    Array.isArray(group.hooks) && group.hooks.some((hook) => (
      isPlainObject(hook) && hook.type === "command" && hook.command === command
    ));
}

function installActivityHooks({ codexHome, sourceScript, now = Date.now }) {
  const hooksDir = path.join(codexHome, "hooks");
  const configPath = path.join(codexHome, "hooks.json");
  const configExists = fs.existsSync(configPath);
  const config = configExists
    ? JSON.parse(fs.readFileSync(configPath, "utf8"))
    : { hooks: {} };
  if (!isPlainObject(config)) {
    throw new TypeError("hooks.json root must be a plain object");
  }
  if (Object.prototype.hasOwnProperty.call(config, "hooks")) {
    if (!isPlainObject(config.hooks)) {
      throw new TypeError("hooks.json hooks must be a plain object");
    }
  } else {
    config.hooks = {};
  }

  let changed = false;
  for (const [event, matcher, status] of HOOKS) {
    config.hooks[event] = config.hooks[event] || [];
    const desiredGroup = groupFor(matcher, status);
    const desiredCommand = desiredGroup.hooks[0].command;
    const alreadyInstalled = config.hooks[event].some((group) => (
      containsIntegration(group, matcher, desiredCommand)
    ));
    if (!alreadyInstalled) {
      config.hooks[event].push(desiredGroup);
      changed = true;
    }
  }

  fs.mkdirSync(hooksDir, { recursive: true });
  fs.copyFileSync(sourceScript, path.join(hooksDir, "codex-meter-state.py"));

  let backupPath = null;
  if (changed && configExists) {
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
