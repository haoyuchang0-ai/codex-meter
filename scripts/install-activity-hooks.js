#!/usr/bin/env node
const os = require("node:os");
const path = require("node:path");
const { installActivityHooks } = require("../src/hook-installer");

const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
const result = installActivityHooks({
  codexHome,
  sourceScript: path.join(__dirname, "codex-meter-state.py"),
});
console.log(result.changed ? "Codex Meter activity hooks installed." : "Codex Meter activity hooks already installed.");
if (result.backupPath) console.log(`Backup: ${result.backupPath}`);
console.log("Restart Codex to activate the hooks.");
