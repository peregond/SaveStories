class BatchJobTimeoutError extends Error {
  constructor(message) {
    super(message);
    this.name = "BatchJobTimeoutError";
  }
}

function errorMessage(error) {
  if (error instanceof Error) {
    return error.message || String(error);
  }
  return String(error);
}

async function withTimeout(promise, timeoutMs, timeoutMessage) {
  let timer = null;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new BatchJobTimeoutError(timeoutMessage)), timeoutMs);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

function shouldRetryError(error) {
  const lowered = errorMessage(error).toLowerCase();
  return (
    lowered.includes("timeout") ||
    lowered.includes("timed out") ||
    lowered.includes("network") ||
    lowered.includes("econnreset") ||
    lowered.includes("socket") ||
    lowered.includes("503") ||
    lowered.includes("502") ||
    lowered.includes("429") ||
    lowered.includes("integrity") ||
    lowered.includes("target page, context or browser has been closed")
  );
}

async function withRetry(action, { attempts = 3, baseDelayMs = 600, onRetry = null } = {}) {
  let lastError = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await action(attempt);
    } catch (error) {
      lastError = error;
      if (attempt >= attempts || !shouldRetryError(error)) {
        throw error;
      }
      const delayMs = baseDelayMs * attempt;
      if (onRetry) {
        onRetry({ attempt, nextAttempt: attempt + 1, delayMs, error });
      }
      await sleep(delayMs);
    }
  }
  throw lastError;
}

function parseInteger(value) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function countsFromData(data, items) {
  const found = parseInteger(data.foundCount);
  const saved = parseInteger(data.savedCount);
  const processed = parseInteger(data.processedCount);
  const failed = parseInteger(data.failedCount);
  if (found === null && saved === null && processed === null && failed === null) return null;
  return {
    found: found ?? items.length,
    saved: saved ?? items.length,
    processed: processed ?? 0,
    failed: failed ?? 0,
  };
}

function batchResultsFromData(data) {
  if (!data.batchResults) return [];
  try {
    const parsed = JSON.parse(data.batchResults);
    return Array.isArray(parsed) ? parsed.filter((entry) => entry && typeof entry === "object") : [];
  } catch {
    return [];
  }
}

function runtimeFromData(data) {
  const runtime = data.runtime || "";
  if (!runtime) return null;
  return {
    kind: runtime,
    executable: data.node || data.python || "",
    browserProfile: data.browserProfile || "",
    playwrightBrowsers: data.playwrightBrowsers || "",
    manifests: data.manifests || "",
  };
}

function diagnosticCategory(status, message) {
  const lowered = `${status} ${message}`.toLowerCase();
  if (lowered.includes("требуется вход") || lowered.includes("session_missing") || lowered.includes("login")) {
    return "session_required";
  }
  if (lowered.includes("превысила лимит") || lowered.includes("timeout")) {
    return "timeout";
  }
  if (lowered.includes("browser has been closed") || lowered.includes("page has been closed") || lowered.includes("context closed")) {
    return "browser_closed";
  }
  if (lowered.includes("фрагмент видео") || lowered.includes("fragmented")) {
    return "partial_media";
  }
  if (lowered.includes("не найдено") || lowered.includes("не удалось получить") || lowered.includes("download_empty")) {
    return "media_not_found";
  }
  if (lowered.includes("playwright") || lowered.includes("chromium")) {
    return "runtime_missing";
  }
  return status.includes("error") || status.includes("failed") ? "worker_error" : "ok";
}

function buildWorkerResponse(ok, status, message, { data = {}, items = [], logs = [], diagnostics = {} } = {}) {
  const safeData = data && typeof data === "object" ? data : {};
  const safeItems = Array.isArray(items) ? items : [];
  const safeDiagnostics = {
    category: diagnosticCategory(status, message),
    ...diagnostics,
  };
  return {
    ok,
    status,
    message,
    protocolVersion: 2,
    data: safeData,
    counts: countsFromData(safeData, safeItems),
    batchResults: batchResultsFromData(safeData),
    runtime: runtimeFromData(safeData),
    diagnostics: safeDiagnostics,
    items: safeItems,
    logs: Array.isArray(logs) ? logs : [],
  };
}

async function closePageAfterBatchTimeout(error, page, slot, normalizedUrl, logs) {
  if (!(error instanceof BatchJobTimeoutError)) return false;
  try {
    await page.close({ runBeforeUnload: false });
    logs.push(`batch_slot_${slot}_timeout_page_closed=${normalizedUrl}`);
  } catch (closeError) {
    logs.push(`batch_slot_${slot}_timeout_page_close_error=${normalizedUrl} :: ${closeError}`);
  }
  return true;
}

function validateDownloadedMedia(body, mediaType, contentType = "") {
  if (!body || body.length < 512) {
    throw new Error("Downloaded media integrity check failed: file is too small.");
  }

  const loweredType = String(contentType || "").toLowerCase();
  const prefix = body.subarray(0, 32);
  const binaryPrefix = prefix.toString("binary");

  if (mediaType === "video") {
    const hasMp4Signature = binaryPrefix.includes("ftyp");
    const hasWebmSignature = prefix.length >= 4 && prefix[0] === 0x1a && prefix[1] === 0x45 && prefix[2] === 0xdf && prefix[3] === 0xa3;
    if (!hasMp4Signature && !hasWebmSignature && !loweredType.startsWith("video/")) {
      throw new Error("Downloaded media integrity check failed: video signature is missing.");
    }
    return;
  }

  const isJpeg = prefix[0] === 0xff && prefix[1] === 0xd8;
  const isPng = prefix.length >= 8 && prefix[0] === 0x89 && prefix[1] === 0x50 && prefix[2] === 0x4e && prefix[3] === 0x47;
  const isWebp = prefix.subarray(0, 4).toString("ascii") === "RIFF" && prefix.subarray(8, 12).toString("ascii") === "WEBP";
  if (!isJpeg && !isPng && !isWebp && !loweredType.startsWith("image/")) {
    throw new Error("Downloaded media integrity check failed: image signature is missing.");
  }
}

export {
  BatchJobTimeoutError,
  buildWorkerResponse,
  closePageAfterBatchTimeout,
  diagnosticCategory,
  errorMessage,
  shouldRetryError,
  validateDownloadedMedia,
  withRetry,
  withTimeout,
};
