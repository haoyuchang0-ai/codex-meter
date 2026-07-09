const test = require("node:test");
const assert = require("node:assert/strict");

const { normalizeRateLimitSnapshot } = require("../src/normalize");

test("normalizes primary and secondary windows into remaining percentages", () => {
  const result = normalizeRateLimitSnapshot({
    rateLimits: {
      limitName: "Codex",
      planType: "plus",
      primary: {
        usedPercent: 27,
        resetsAt: 1783584000,
        windowDurationMins: 300,
      },
      secondary: {
        usedPercent: 64,
        resetsAt: 1783591200,
        windowDurationMins: 1440,
      },
    },
    rateLimitResetCredits: {
      availableCount: 1,
    },
  });

  assert.equal(result.title, "Codex");
  assert.equal(result.planType, "plus");
  assert.equal(result.resetCreditsAvailable, 1);
  assert.deepEqual(
    result.windows.map((window) => ({
      key: window.key,
      remainingPercent: window.remainingPercent,
      usedPercent: window.usedPercent,
      resetsAtEpochSeconds: window.resetsAtEpochSeconds,
      windowDurationMins: window.windowDurationMins,
    })),
    [
      {
        key: "primary",
        remainingPercent: 73,
        usedPercent: 27,
        resetsAtEpochSeconds: 1783584000,
        windowDurationMins: 300,
      },
      {
        key: "secondary",
        remainingPercent: 36,
        usedPercent: 64,
        resetsAtEpochSeconds: 1783591200,
        windowDurationMins: 1440,
      },
    ],
  );
});

test("returns an unavailable window when app-server omits a bucket", () => {
  const result = normalizeRateLimitSnapshot({
    rateLimits: {
      primary: null,
      secondary: {
        usedPercent: 0,
        resetsAt: null,
      },
    },
  });

  assert.deepEqual(
    result.windows.map((window) => ({
      key: window.key,
      status: window.status,
      remainingPercent: window.remainingPercent,
      resetsAtEpochSeconds: window.resetsAtEpochSeconds,
    })),
    [
      {
        key: "primary",
        status: "unavailable",
        remainingPercent: null,
        resetsAtEpochSeconds: null,
      },
      {
        key: "secondary",
        status: "ok",
        remainingPercent: 100,
        resetsAtEpochSeconds: null,
      },
    ],
  );
});
