function mergeActivityTasks({ activeStates = [], threads = [] }) {
  const threadsById = new Map(
    threads
      .filter((thread) => (
        thread &&
        typeof thread.id === "string" &&
        thread.parentThreadId == null
      ))
      .map((thread) => [thread.id, thread]),
  );

  return activeStates
    .filter((state) => state.status === "waiting" || state.status === "working")
    .filter((state) => threadsById.has(state.threadId))
    .map((state) => {
      const rawName = threadsById.get(state.threadId)?.name;
      const title = typeof rawName === "string" && rawName.trim()
        ? rawName.trim()
        : "未命名任务";
      return {
        threadId: state.threadId,
        title,
        status: state.status,
        updatedAt: new Date(state.updatedAtMs).toISOString(),
      };
    })
    .sort((a, b) => {
      if (a.status !== b.status) return a.status === "waiting" ? -1 : 1;
      return Date.parse(b.updatedAt) - Date.parse(a.updatedAt);
    });
}

module.exports = { mergeActivityTasks };
