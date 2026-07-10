const DONE_HOLD_MS = 8_000;
const STALE_ACTIVITY_MS = 12 * 60 * 60 * 1_000;

function parseRolloutText(text, threadId) {
  const events = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;

    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }

    if (record === null || typeof record !== "object" || Array.isArray(record)) continue;
    if (record.type !== "event_msg") continue;
    const payloadType = record.payload && record.payload.type;
    if (payloadType !== "task_started" && payloadType !== "task_complete") continue;

    const turnId = record.payload.turn_id;
    const updatedAtMs = Date.parse(record.timestamp);
    if (typeof turnId !== "string" || !Number.isFinite(updatedAtMs)) continue;

    events.push({
      threadId,
      turnId,
      status: payloadType === "task_started" ? "working" : "done",
      updatedAtMs,
    });
  }
  return events;
}

function resolveThreadStates({ rolloutEvents = [], hookStates = [], nowMs = Date.now() }) {
  const turns = new Map();
  for (const event of [...rolloutEvents].sort((a, b) => a.updatedAtMs - b.updatedAtMs)) {
    const turnKey = JSON.stringify([event.threadId, event.turnId]);
    turns.set(turnKey, event);
  }

  const latestByThread = new Map();
  const candidates = [...turns.values(), ...hookStates]
    .filter((state) => nowMs - state.updatedAtMs <= STALE_ACTIVITY_MS)
    .sort((a, b) => a.updatedAtMs - b.updatedAtMs);
  for (const candidate of candidates) {
    latestByThread.set(candidate.threadId, candidate);
  }

  return [...latestByThread.values()].sort((a, b) => a.updatedAtMs - b.updatedAtMs);
}

function aggregateActivity({ rolloutEvents = [], hookStates = [], nowMs = Date.now() }) {
  const threadStates = resolveThreadStates({ rolloutEvents, hookStates, nowMs });
  const waitingThreads = new Set(
    threadStates.filter((state) => state.status === "waiting").map((state) => state.threadId),
  );
  const activeThreads = new Set(
    threadStates.filter((state) => state.status === "working").map((state) => state.threadId),
  );
  const completionTimes = threadStates
    .filter((state) => state.status === "done")
    .map((state) => state.updatedAtMs);
  const latestCompletion = completionTimes.length ? Math.max(...completionTimes) : null;

  let status = "idle";
  if (waitingThreads.size > 0) status = "waiting";
  else if (activeThreads.size > 0) status = "working";
  else if (latestCompletion !== null && nowMs - latestCompletion <= DONE_HOLD_MS) status = "done";

  const updatedAtMs = Math.max(
    0,
    ...rolloutEvents.map((event) => event.updatedAtMs),
    ...hookStates.map((state) => state.updatedAtMs),
  );

  return {
    status,
    updatedAt: new Date(updatedAtMs || nowMs).toISOString(),
    activeCount: activeThreads.size,
    waitingCount: waitingThreads.size,
    source: "local",
  };
}

module.exports = {
  DONE_HOLD_MS,
  STALE_ACTIVITY_MS,
  aggregateActivity,
  parseRolloutText,
  resolveThreadStates,
};
