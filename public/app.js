const REFRESH_INTERVAL_SECONDS = 60;

const elements = {
  statusPill: document.querySelector("#statusPill"),
  primaryMeter: document.querySelector("#primaryMeter"),
  secondaryMeter: document.querySelector("#secondaryMeter"),
  planType: document.querySelector("#planType"),
  resetCredits: document.querySelector("#resetCredits"),
  lastUpdated: document.querySelector("#lastUpdated"),
  message: document.querySelector("#message"),
  refreshButton: document.querySelector("#refreshButton"),
  autoRefresh: document.querySelector("#autoRefresh"),
  countdown: document.querySelector("#countdown"),
};

let refreshInFlight = false;
let nextRefreshAt = Date.now() + REFRESH_INTERVAL_SECONDS * 1000;

function formatDateTime(epochSeconds) {
  if (!epochSeconds) {
    return "--";
  }

  return new Intl.DateTimeFormat("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(epochSeconds * 1000));
}

function formatClock(isoString) {
  if (!isoString) {
    return "--";
  }

  return new Intl.DateTimeFormat("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date(isoString));
}

function setStatus(text, mode = "ok") {
  elements.statusPill.textContent = text;
  elements.statusPill.classList.toggle("error", mode === "error");
}

function setMessage(text, mode = "ok") {
  elements.message.textContent = text;
  elements.message.classList.toggle("error", mode === "error");
}

function renderWindow(meter, window) {
  const remaining = meter.querySelector('[data-field="remaining"]');
  const used = meter.querySelector('[data-field="used"]');
  const reset = meter.querySelector('[data-field="reset"]');
  const bar = meter.querySelector('[data-field="bar"]');

  if (!window || window.status === "unavailable") {
    remaining.textContent = "--%";
    used.textContent = "暂无数据";
    reset.textContent = "重置 --";
    bar.style.width = "0%";
    return;
  }

  const remainingPercent =
    typeof window.remainingPercent === "number" ? window.remainingPercent : null;
  const usedPercent =
    typeof window.usedPercent === "number" ? window.usedPercent : null;

  remaining.textContent =
    remainingPercent === null ? "--%" : `${remainingPercent}%`;
  used.textContent = usedPercent === null ? "已用 --%" : `已用 ${usedPercent}%`;
  reset.textContent = `重置 ${formatDateTime(window.resetsAtEpochSeconds)}`;
  bar.style.width = `${remainingPercent || 0}%`;
}

function render(data) {
  const windows = new Map(data.windows.map((window) => [window.key, window]));
  renderWindow(elements.primaryMeter, windows.get("primary"));
  renderWindow(elements.secondaryMeter, windows.get("secondary"));

  elements.planType.textContent = data.planType || "--";
  elements.resetCredits.textContent =
    typeof data.resetCreditsAvailable === "number"
      ? String(data.resetCreditsAvailable)
      : "--";
  elements.lastUpdated.textContent = formatClock(data.fetchedAt);
}

async function refreshNow(reason = "manual") {
  if (refreshInFlight) {
    return;
  }

  refreshInFlight = true;
  elements.refreshButton.disabled = true;
  elements.refreshButton.textContent = "刷新中";
  setStatus("更新中");

  try {
    const response = await fetch("/api/rate-limits", {
      cache: "no-store",
    });
    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "读取失败");
    }

    render(data);
    setStatus("已更新");
    setMessage(
      reason === "auto" ? "已按 60 秒节奏自动更新。" : "已手动更新。",
    );
    nextRefreshAt = Date.now() + REFRESH_INTERVAL_SECONDS * 1000;
  } catch (error) {
    setStatus("失败", "error");
    setMessage(error.message, "error");
  } finally {
    refreshInFlight = false;
    elements.refreshButton.disabled = false;
    elements.refreshButton.textContent = "刷新";
    updateCountdown();
  }
}

function updateCountdown() {
  if (!elements.autoRefresh.checked) {
    elements.countdown.textContent = "手动";
    return;
  }

  const remainingMs = Math.max(0, nextRefreshAt - Date.now());
  const remainingSeconds = Math.ceil(remainingMs / 1000);
  elements.countdown.textContent = `${remainingSeconds}s`;

  if (remainingSeconds <= 0 && !refreshInFlight) {
    refreshNow("auto");
  }
}

elements.refreshButton.addEventListener("click", () => refreshNow("manual"));

elements.autoRefresh.addEventListener("change", () => {
  nextRefreshAt = Date.now() + REFRESH_INTERVAL_SECONDS * 1000;
  setMessage(elements.autoRefresh.checked ? "自动更新已开启。" : "自动更新已暂停。");
  updateCountdown();
});

setInterval(updateCountdown, 1000);
refreshNow("initial");
