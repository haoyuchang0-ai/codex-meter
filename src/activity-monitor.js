const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { aggregateActivity, parseRolloutText } = require("./activity-state");

const RECENT_FILE_MS = 48 * 60 * 60 * 1_000;
const THREAD_ID_PATTERN = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;

function safeJson(filePath, fsImpl) {
  try {
    return JSON.parse(fsImpl.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function walkJsonl(root, fsImpl) {
  if (!fsImpl.existsSync(root)) return [];

  let entries;
  try {
    entries = fsImpl.readdirSync(root, { withFileTypes: true });
  } catch {
    return [];
  }

  const files = [];
  for (const entry of entries) {
    const child = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...walkJsonl(child, fsImpl));
    else if (entry.isFile() && entry.name.endsWith(".jsonl")) files.push(child);
  }
  return files;
}

function readRange(filePath, offset, length, fsImpl) {
  if (length <= 0) return "";

  const descriptor = fsImpl.openSync(filePath, "r");
  try {
    const buffer = Buffer.alloc(length);
    const bytesRead = fsImpl.readSync(descriptor, buffer, 0, length, offset);
    return buffer.subarray(0, bytesRead).toString("utf8");
  } finally {
    fsImpl.closeSync(descriptor);
  }
}

class ActivityMonitor {
  constructor(options = {}) {
    const codexHome = options.codexHome || path.join(os.homedir(), ".codex");
    this.sessionsRoot = options.sessionsRoot || path.join(codexHome, "sessions");
    this.hookStateRoot = options.hookStateRoot || path.join(codexHome, "codex-meter", "activity");
    this.hooksConfigPath = options.hooksConfigPath || path.join(codexHome, "hooks.json");
    this.now = options.now || Date.now;
    this.fs = options.fsImpl || fs;
    this.cache = new Map();
  }

  readRolloutEvents() {
    const events = [];
    const discovered = new Set();
    for (const filePath of walkJsonl(this.sessionsRoot, this.fs)) {
      let stat;
      try {
        stat = this.fs.statSync(filePath);
      } catch {
        continue;
      }
      if (this.now() - stat.mtimeMs > RECENT_FILE_MS) continue;
      discovered.add(filePath);

      const cached = this.cache.get(filePath);
      const fileIdentity = Number.isFinite(stat.ino) ? stat.ino : null;
      const rotated = cached && fileIdentity !== null && cached.fileIdentity !== fileIdentity;
      if (!cached || cached.size !== stat.size || rotated) {
        const match = path.basename(filePath).match(THREAD_ID_PATTERN);
        if (!match) continue;

        const reset = !cached || stat.size < cached.size || rotated;
        const offset = reset ? 0 : cached.size;
        let chunk;
        try {
          chunk = readRange(filePath, offset, stat.size - offset, this.fs);
        } catch {
          continue;
        }
        const combined = `${reset ? "" : cached.remainder}${chunk}`;
        const lines = combined.split("\n");
        const remainder = lines.pop() || "";
        const parsed = parseRolloutText(lines.join("\n"), match[1]);
        this.cache.set(filePath, {
          fileIdentity,
          size: stat.size,
          remainder,
          events: [...(reset ? [] : cached.events), ...parsed],
        });
      }
      events.push(...this.cache.get(filePath).events);
    }

    for (const filePath of this.cache.keys()) {
      if (!discovered.has(filePath)) this.cache.delete(filePath);
    }
    return events;
  }

  readHookStates() {
    if (!this.fs.existsSync(this.hookStateRoot)) return [];

    let names;
    try {
      names = this.fs.readdirSync(this.hookStateRoot);
    } catch {
      return [];
    }

    const states = [];
    for (const name of names) {
      if (!name.endsWith(".json")) continue;
      const state = safeJson(path.join(this.hookStateRoot, name), this.fs);
      if (
        state && typeof state.threadId === "string" &&
        ["waiting", "working", "done", "idle"].includes(state.status) &&
        Number.isFinite(state.updatedAtMs)
      ) {
        states.push(state);
      }
    }
    return states;
  }

  hooksInstalled() {
    if (!this.fs.existsSync(this.hooksConfigPath)) return false;
    try {
      return this.fs.readFileSync(this.hooksConfigPath, "utf8").includes("codex-meter-state.py");
    } catch {
      return false;
    }
  }

  snapshot() {
    return {
      ...aggregateActivity({
        rolloutEvents: this.readRolloutEvents(),
        hookStates: this.readHookStates(),
        nowMs: this.now(),
      }),
      hooksInstalled: this.hooksInstalled(),
    };
  }
}

module.exports = { ActivityMonitor };
