const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { aggregateActivity, parseRolloutText, resolveThreadStates } = require("./activity-state");

const RECENT_FILE_MS = 48 * 60 * 60 * 1_000;
const MAX_SCAN_DEPTH = 5;
const THREAD_ID_PATTERN = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;

function safeJson(filePath, fsImpl) {
  try {
    return JSON.parse(fsImpl.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function listRecentJsonl(root, nowMs, fsImpl, depth = 0) {
  if (!fsImpl.existsSync(root)) return [];

  let entries;
  try {
    entries = fsImpl.readdirSync(root, { withFileTypes: true });
  } catch {
    return [];
  }

  const files = [];
  for (const entry of entries) {
    const entryPath = path.join(root, entry.name);
    if (entry.isFile() && entry.name.endsWith(".jsonl")) {
      let stat;
      try {
        stat = fsImpl.statSync(entryPath);
      } catch {
        continue;
      }
      if (nowMs - stat.mtimeMs <= RECENT_FILE_MS) files.push(entryPath);
    } else if (entry.isDirectory() && depth < MAX_SCAN_DEPTH) {
      files.push(...listRecentJsonl(entryPath, nowMs, fsImpl, depth + 1));
    }
  }
  return files;
}

function readRange(filePath, offset, length, fsImpl) {
  if (length <= 0) return Buffer.alloc(0);

  const descriptor = fsImpl.openSync(filePath, "r");
  try {
    const buffer = Buffer.alloc(length);
    const bytesRead = fsImpl.readSync(descriptor, buffer, 0, length, offset);
    return buffer.subarray(0, bytesRead);
  } finally {
    fsImpl.closeSync(descriptor);
  }
}

function compactEvents(events) {
  const latestByTurn = new Map();
  for (const event of events) {
    const key = JSON.stringify([event.threadId, event.turnId]);
    const current = latestByTurn.get(key);
    if (!current || event.updatedAtMs >= current.updatedAtMs) latestByTurn.set(key, event);
  }
  return [...latestByTurn.values()];
}

function sameSizeMarkerChanged(cached, stat) {
  if (!cached || cached.size !== stat.size) return false;
  return ["mtimeMs", "ctimeMs"].some((field) => (
    Number.isFinite(cached[field]) &&
    Number.isFinite(stat[field]) &&
    cached[field] !== stat[field]
  ));
}

function containsMeterHookCommand(hooks) {
  return Object.values(hooks).some((groups) => (
    Array.isArray(groups) && groups.some((group) => (
      group !== null && typeof group === "object" && Array.isArray(group.hooks) &&
      group.hooks.some((entry) => (
        entry !== null && typeof entry === "object" &&
        entry.type === "command" &&
        typeof entry.command === "string" &&
        entry.command.includes("codex-meter-state.py")
      ))
    ))
  ));
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
    const nowMs = this.now();
    const files = listRecentJsonl(this.sessionsRoot, nowMs, this.fs);
    for (const filePath of files) {
      let stat;
      try {
        stat = this.fs.statSync(filePath);
      } catch {
        continue;
      }
      if (nowMs - stat.mtimeMs > RECENT_FILE_MS) continue;
      discovered.add(filePath);

      const cached = this.cache.get(filePath);
      const fileIdentity = Number.isFinite(stat.ino) ? stat.ino : null;
      const rotated = cached && fileIdentity !== null && cached.fileIdentity !== fileIdentity;
      const rewritten = sameSizeMarkerChanged(cached, stat);
      if (!cached || cached.size !== stat.size || rotated || rewritten) {
        const match = path.basename(filePath).match(THREAD_ID_PATTERN);
        if (!match) continue;

        const reset = !cached || stat.size < cached.size || rotated || rewritten;
        const offset = reset ? 0 : cached.offset;
        let chunk;
        try {
          chunk = readRange(filePath, offset, stat.size - offset, this.fs);
        } catch {
          continue;
        }
        const finalNewline = chunk.lastIndexOf(0x0a);
        const completeLength = finalNewline + 1;
        const parsed = parseRolloutText(
          chunk.subarray(0, completeLength).toString("utf8"),
          match[1],
        );
        this.cache.set(filePath, {
          fileIdentity,
          mtimeMs: Number.isFinite(stat.mtimeMs) ? stat.mtimeMs : null,
          ctimeMs: Number.isFinite(stat.ctimeMs) ? stat.ctimeMs : null,
          size: offset + chunk.length,
          offset: offset + completeLength,
          events: compactEvents([...(reset ? [] : cached.events), ...parsed]),
        });
      }
      events.push(...this.cache.get(filePath).events);
    }

    for (const filePath of this.cache.keys()) {
      if (!discovered.has(filePath)) this.cache.delete(filePath);
    }
    return compactEvents(events);
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
    const config = safeJson(this.hooksConfigPath, this.fs);
    if (
      config === null || typeof config !== "object" || Array.isArray(config) ||
      config.hooks === null || typeof config.hooks !== "object" || Array.isArray(config.hooks)
    ) return false;
    return containsMeterHookCommand(config.hooks);
  }

  activeTasks() {
    const states = resolveThreadStates({
      rolloutEvents: this.readRolloutEvents(),
      hookStates: this.readHookStates(),
      nowMs: this.now(),
    });
    return states
      .filter((state) => state.status === "waiting" || state.status === "working")
      .map(({ threadId, status, updatedAtMs }) => ({ threadId, status, updatedAtMs }))
      .sort((a, b) => {
        if (a.status !== b.status) return a.status === "waiting" ? -1 : 1;
        return b.updatedAtMs - a.updatedAtMs;
      });
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
