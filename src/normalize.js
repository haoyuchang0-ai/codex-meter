function clampPercent(value) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return null;
  }

  return Math.max(0, Math.min(100, Math.round(value)));
}

function normalizeWindow(key, source) {
  if (!source || typeof source !== "object") {
    return {
      key,
      label: key === "primary" ? "Primary" : "Secondary",
      status: "unavailable",
      usedPercent: null,
      remainingPercent: null,
      resetsAtEpochSeconds: null,
      windowDurationMins: null,
    };
  }

  const usedPercent = clampPercent(source.usedPercent);
  const remainingPercent =
    usedPercent === null ? null : clampPercent(100 - usedPercent);

  return {
    key,
    label: key === "primary" ? "Primary" : "Secondary",
    status: "ok",
    usedPercent,
    remainingPercent,
    resetsAtEpochSeconds:
      typeof source.resetsAt === "number" ? source.resetsAt : null,
    windowDurationMins:
      typeof source.windowDurationMins === "number"
        ? source.windowDurationMins
        : null,
  };
}

function normalizeRateLimitSnapshot(payload) {
  const snapshot = payload && payload.rateLimits ? payload.rateLimits : {};

  return {
    title: snapshot.limitName || "Codex",
    planType: snapshot.planType || null,
    resetCreditsAvailable:
      payload &&
      payload.rateLimitResetCredits &&
      typeof payload.rateLimitResetCredits.availableCount === "number"
        ? payload.rateLimitResetCredits.availableCount
        : null,
    windows: [
      normalizeWindow("primary", snapshot.primary),
      normalizeWindow("secondary", snapshot.secondary),
    ],
    raw: payload || null,
  };
}

module.exports = {
  normalizeRateLimitSnapshot,
};
