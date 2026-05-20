#!/usr/bin/env node

import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import os from "node:os";
import process from "node:process";
import { createHash, randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import {
  extractUsername,
  isAudioOnlyVariant,
  isStoryMediaUrl,
  mediaVariantTag,
  mediaVariantScore,
  normalizeMediaUrl,
  sanitizeFilename,
  shouldSkipMediaVariant,
} from "./media_utils.mjs";
import { downloadReelsCommand } from "./reels_downloader.mjs";
import {
  buildWorkerResponse,
  closePageAfterBatchTimeout,
  errorMessage,
  validateDownloadedMedia,
  withRetry,
  withTimeout,
} from "./worker_utils.mjs";

const APP_NAME = "SaveMe";
const LEGACY_APP_NAMES = ["SaveStories", "DimaSave"];
const BATCH_JOB_TIMEOUT_MS = 120_000;
let didEmitResponse = false;

function emit(ok, status, message, options = {}) {
  if (didEmitResponse) {
    emitProgress(`suppressed_extra_response=${status} :: ${message}`);
    return;
  }
  didEmitResponse = true;
  const response = buildWorkerResponse(ok, status, message, options);
  void appendWorkerEvent({
    type: "response",
    ok,
    status,
    message,
    category: response.diagnostics?.category || "unknown",
    counts: response.counts,
    itemCount: response.items.length,
  });
  process.stdout.write(JSON.stringify(response));
}

function emitProgress(message) {
  process.stderr.write(`${message}\n`);
}

function isClosedTargetMessage(message) {
  const lowered = String(message || "").toLowerCase();
  return (
    lowered.includes("target page, context or browser has been closed") ||
    lowered.includes("browser has been closed") ||
    lowered.includes("page has been closed") ||
    lowered.includes("page closed") ||
    lowered.includes("context closed") ||
    lowered.includes("session closed")
  );
}

function isClosedTargetError(error) {
  return isClosedTargetMessage(errorMessage(error));
}

async function closeSessionSafely(session, logs = null) {
  if (!session) {
    return;
  }
  try {
    await session.close();
  } catch (error) {
    const message = errorMessage(error);
    if (logs) {
      logs.push(`session_close_error=${message}`);
    }
    emitProgress(`session_close_error=${message}`);
  }
}

async function readRequest() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) {
    throw new Error("Worker received an empty request.");
  }
  return JSON.parse(raw);
}

function currentPlatform() {
  return process.platform;
}

function preferredAppSupportPath() {
  if (currentPlatform() === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support", APP_NAME);
  }
  if (currentPlatform() === "win32") {
    const root = process.env.LOCALAPPDATA || process.env.APPDATA;
    if (root) {
      return path.join(root, APP_NAME);
    }
    return path.join(os.homedir(), "AppData", "Local", APP_NAME);
  }
  return path.join(os.homedir(), ".local", "share", APP_NAME);
}

function preferredDownloadsPath() {
  if (currentPlatform() === "win32") {
    const root = process.env.USERPROFILE;
    if (root) {
      return path.join(root, "Downloads", APP_NAME);
    }
  }
  return path.join(os.homedir(), "Downloads", APP_NAME);
}

async function canWrite(directory) {
  let candidate = directory;
  while (candidate && candidate !== path.dirname(candidate)) {
    try {
      await fs.access(candidate, fs.constants.W_OK);
      return true;
    } catch {
      candidate = path.dirname(candidate);
    }
  }
  return false;
}

async function defaultAppSupport() {
  const preferred = preferredAppSupportPath();
  try {
    await fs.access(preferred);
  } catch {
    const legacyCandidates = LEGACY_APP_NAMES.map((legacyName) => path.join(path.dirname(preferred), legacyName));
    for (const candidate of legacyCandidates) {
      try {
        await fs.access(candidate);
        return candidate;
      } catch {
        // try next candidate
      }
    }
  }
  if (await canWrite(path.dirname(preferred))) {
    return preferred;
  }
  return path.join(process.cwd(), ".runtime", APP_NAME);
}

async function defaultDownloads(appSupport) {
  const preferred = preferredDownloadsPath();
  if (await canWrite(path.dirname(preferred))) {
    return preferred;
  }
  return path.join(appSupport, "Downloads");
}

const APP_SUPPORT = process.env.SAVESTORIES_APP_SUPPORT || (await defaultAppSupport());
const WORKER_ROOT = path.join(APP_SUPPORT, "worker");
const BROWSER_PROFILE = process.env.SAVESTORIES_BROWSER_PROFILE || path.join(WORKER_ROOT, "browser-profile");
const PLAYWRIGHT_BROWSERS =
  process.env.SAVESTORIES_PLAYWRIGHT_BROWSERS || path.join(WORKER_ROOT, "ms-playwright");
const MANIFESTS_DIRECTORY = process.env.SAVESTORIES_MANIFESTS || path.join(APP_SUPPORT, "manifests");
const SESSION_STATE = process.env.SAVESTORIES_SESSION_STATE || path.join(WORKER_ROOT, "storage-state.json");
const DEFAULT_DOWNLOADS =
  process.env.SAVESTORIES_DEFAULT_DOWNLOADS || (await defaultDownloads(APP_SUPPORT));
const LOGS_DIRECTORY = process.env.SAVESTORIES_LOGS || path.join(APP_SUPPORT, "logs");
const WORKER_EVENTS_LOG = path.join(LOGS_DIRECTORY, "worker-events.jsonl");

async function ensureDirectories() {
  await Promise.all(
    [APP_SUPPORT, WORKER_ROOT, BROWSER_PROFILE, PLAYWRIGHT_BROWSERS, MANIFESTS_DIRECTORY, DEFAULT_DOWNLOADS, LOGS_DIRECTORY].map(
      (entry) => fs.mkdir(entry, { recursive: true }),
    ),
  );
}

async function appendWorkerEvent(event) {
  try {
    fsSync.mkdirSync(LOGS_DIRECTORY, { recursive: true });
    const payload = {
      timestamp: new Date().toISOString(),
      ...event,
    };
    fsSync.appendFileSync(WORKER_EVENTS_LOG, `${JSON.stringify(payload)}\n`, "utf8");
  } catch {
    // Diagnostics must never break downloads.
  }
}

async function retryingGoto(page, url, options, logs, label = "goto") {
  return await withRetry(
    async () => await page.goto(url, options),
    {
      attempts: 2,
      baseDelayMs: 800,
      onRetry: ({ attempt, delayMs, error }) => {
        logs?.push(`${label}_retry=${attempt}:${url}:${errorMessage(error)}`);
        void appendWorkerEvent({ type: "retry", operation: label, url, attempt, delayMs, error: errorMessage(error) });
      },
    },
  );
}

async function importPlaywright() {
  try {
    process.env.PLAYWRIGHT_BROWSERS_PATH ||= PLAYWRIGHT_BROWSERS;
    return await import("playwright");
  } catch (error) {
    throw new Error("Playwright не установлен. Подготовьте среду в настройках приложения.");
  }
}

async function launchContext(headless = false) {
  const { chromium } = await importPlaywright();
  const executablePath = chromium.executablePath();
  const options = {
    headless: Boolean(headless),
    viewport: { width: 1440, height: 940 },
    acceptDownloads: true,
  };
  if (executablePath) {
    options.executablePath = executablePath;
  }
  const context = await chromium.launchPersistentContext(BROWSER_PROFILE, options);
  return {
    context,
    browser: null,
    background: headless,
    async firstPage() {
      const pages = context.pages();
      if (pages.length > 0) {
        return pages[0];
      }
      return await context.newPage();
    },
    async close() {
      await context.close();
    },
  };
}

async function persistSessionState(context, logs = null) {
  try {
    await fs.mkdir(path.dirname(SESSION_STATE), { recursive: true });
    await context.storageState({ path: SESSION_STATE });
    if (logs) {
      logs.push(`storage_state_saved=${SESSION_STATE}`);
    }
  } catch (error) {
    if (logs) {
      logs.push(`storage_state_error=${error}`);
    }
  }
}

async function prepareBackgroundWindow(session, page, logs = null) {
  if (!session.background) {
    return;
  }

  try {
    const cdp = await page.context().newCDPSession(page);
    const windowInfo = await cdp.send("Browser.getWindowForTarget");
    const windowId = windowInfo.windowId;
    if (windowId !== undefined && windowId !== null) {
      await cdp.send("Browser.setWindowBounds", {
        windowId,
        bounds: { windowState: "minimized" },
      });
      if (logs) {
        logs.push("background_window=minimized");
      }
    }
  } catch (error) {
    if (logs) {
      logs.push(`background_window_error=${error}`);
    }
  }
}

async function hasActiveInstagramSession(context) {
  try {
    const cookies = await context.cookies();
    for (const cookie of cookies) {
      const name = String(cookie.name || "").toLowerCase();
      const value = String(cookie.value || "");
      const domain = String(cookie.domain || "").toLowerCase();
      if (name === "sessionid" && value && domain.includes("instagram.com")) {
        return true;
      }
    }
  } catch {
    return false;
  }
  return false;
}

async function isLoggedIn(page) {
  if (await hasActiveInstagramSession(page.context())) {
    return true;
  }

  try {
    if ((await page.locator('input[name="username"], input[name="password"]').count()) > 0) {
      return false;
    }
  } catch {}

  try {
    if (
      (await page
        .locator('a[href="/direct/inbox/"], a[href="/accounts/edit/"], svg[aria-label="Home"], svg[aria-label="Домой"]')
        .count()) > 0
    ) {
      return true;
    }
  } catch {}

  const loweredUrl = page.url().toLowerCase();
  if (loweredUrl.includes("/accounts/login") || loweredUrl.includes("login")) {
    return false;
  }
  if (loweredUrl.includes("/challenge/") || loweredUrl.includes("/checkpoint/")) {
    return false;
  }
  return false;
}

async function waitForLogin(page, timeoutSeconds = 600) {
  const deadline = Date.now() + timeoutSeconds * 1000;
  while (Date.now() < deadline) {
    await page.waitForTimeout(1000);
    if (await isLoggedIn(page)) {
      return true;
    }
  }
  return false;
}

async function environmentCommand() {
  await ensureDirectories();
  const logs = [
    `app_support=${APP_SUPPORT}`,
    `browser_profile=${BROWSER_PROFILE}`,
    `playwright_browsers=${PLAYWRIGHT_BROWSERS}`,
    `session_state=${SESSION_STATE}`,
    `manifests=${MANIFESTS_DIRECTORY}`,
    `default_downloads=${DEFAULT_DOWNLOADS}`,
    `logs=${LOGS_DIRECTORY}`,
    `node=${process.execPath}`,
  ];
  const healthChecks = await runHealthChecks();
  logs.push(...healthChecks.map((check) => `health_${check.name}=${check.ok ? "ok" : "failed"}:${check.message}`));

  try {
    const workerPackagePath = path.join(path.dirname(fileURLToPath(import.meta.url)), "package.json");
    const packageRaw = await fs.readFile(workerPackagePath, "utf8");
    const packageJson = JSON.parse(packageRaw);
    logs.push(`playwright=${packageJson.dependencies?.playwright || "installed"}`);
    emit(true, "environment_ready", "Среда Node worker готова. Пакет Playwright установлен.", {
      data: {
        runtime: "node",
        node: process.execPath,
        playwrightInstalled: "true",
        browserProfile: BROWSER_PROFILE,
        playwrightBrowsers: PLAYWRIGHT_BROWSERS,
        sessionState: SESSION_STATE,
        manifests: MANIFESTS_DIRECTORY,
        logsDirectory: LOGS_DIRECTORY,
        health: JSON.stringify(healthChecks),
      },
      logs,
      diagnostics: { health: JSON.stringify(healthChecks) },
    });
  } catch {
    emit(false, "environment_missing", "Playwright не найден. Подготовьте среду в настройках приложения, чтобы установить Chromium.", {
      data: {
        runtime: "node",
        node: process.execPath,
        playwrightInstalled: "false",
        browserProfile: BROWSER_PROFILE,
        playwrightBrowsers: PLAYWRIGHT_BROWSERS,
        sessionState: SESSION_STATE,
        manifests: MANIFESTS_DIRECTORY,
        logsDirectory: LOGS_DIRECTORY,
        health: JSON.stringify(healthChecks),
      },
      logs,
      diagnostics: { health: JSON.stringify(healthChecks) },
    });
  }
}

async function checkHealth(name, action) {
  try {
    const message = await action();
    return { name, ok: true, message: String(message || "OK") };
  } catch (error) {
    return { name, ok: false, message: errorMessage(error) };
  }
}

async function runHealthChecks() {
  return await Promise.all([
    checkHealth("app_support_writable", async () => {
      await fs.access(APP_SUPPORT, fs.constants.W_OK);
      return APP_SUPPORT;
    }),
    checkHealth("downloads_writable", async () => {
      await fs.mkdir(DEFAULT_DOWNLOADS, { recursive: true });
      const probe = path.join(DEFAULT_DOWNLOADS, `.write_probe_${randomUUID()}.tmp`);
      await fs.writeFile(probe, "ok", "utf8");
      await fs.rm(probe, { force: true });
      return DEFAULT_DOWNLOADS;
    }),
    checkHealth("node_runtime", async () => process.execPath),
    checkHealth("playwright_package", async () => {
      await importPlaywright();
      return "installed";
    }),
    checkHealth("chromium_executable", async () => {
      const { chromium } = await importPlaywright();
      return chromium.executablePath();
    }),
    checkHealth("session_state", async () => {
      try {
        await fs.access(SESSION_STATE);
        return SESSION_STATE;
      } catch {
        return "missing";
      }
    }),
  ]);
}

async function healthCommand() {
  await ensureDirectories();
  const checks = await runHealthChecks();
  const ok = checks.every((check) => check.ok);
  emit(ok, ok ? "health_ready" : "health_failed", ok ? "Preflight checks passed." : "Некоторые проверки preflight не прошли.", {
    data: {
      runtime: "node",
      node: process.execPath,
      health: JSON.stringify(checks),
      logsDirectory: LOGS_DIRECTORY,
    },
    logs: checks.map((check) => `health_${check.name}=${check.ok ? "ok" : "failed"}:${check.message}`),
    diagnostics: { health: JSON.stringify(checks) },
  });
}

async function loginCommand() {
  await ensureDirectories();
  const logs = [];
  let session = null;

  try {
    session = await launchContext(false);
    const page = await session.firstPage();
    await retryingGoto(page, "https://www.instagram.com/accounts/login/", { waitUntil: "domcontentloaded" }, logs, "login_goto");
    await page.waitForTimeout(1500);
    logs.push(`opened=${page.url()}`);

    if (await isLoggedIn(page)) {
      emit(true, "already_logged_in", "Сохранённая сессия Instagram уже существует.", {
        data: { loggedIn: "true", currentURL: page.url() },
        logs,
      });
      return;
    }

    const loggedIn = await waitForLogin(page);
    if (!loggedIn) {
      emit(false, "login_timeout", "Браузер для входа был открыт, но до истечения таймаута активная сессия Instagram не появилась.", {
        data: { loggedIn: "false", currentURL: page.url() },
        logs,
      });
      return;
    }

    await persistSessionState(page.context(), logs);
    emit(true, "login_ready", "Сессия Instagram обнаружена и сохранена в постоянном профиле браузера.", {
      data: { loggedIn: "true", currentURL: page.url() },
      logs,
    });
  } catch (error) {
    emit(false, "login_error", String(error), { logs });
  } finally {
    await closeSessionSafely(session, logs);
  }
}

async function checkSessionCommand(headless = true) {
  await ensureDirectories();
  const logs = [];
  let session = null;

  try {
    session = await launchContext(headless);
    const page = await session.firstPage();
    await prepareBackgroundWindow(session, page, logs);
    await retryingGoto(page, "https://www.instagram.com/", { waitUntil: "domcontentloaded" }, logs, "session_goto");
    const loggedIn = await isLoggedIn(page);
    logs.push(`checked=${page.url()}`);

    if (loggedIn) {
      await persistSessionState(page.context(), logs);
      emit(true, "session_ready", "Сессия Instagram выглядит действительной.", {
        data: { loggedIn: "true", currentURL: page.url() },
        logs,
      });
    } else {
      emit(false, "session_missing", "Активная сессия Instagram не найдена. Сначала откройте браузер для входа.", {
        data: { loggedIn: "false", currentURL: page.url() },
        logs,
      });
    }
  } catch (error) {
    emit(false, "session_error", String(error), { logs });
  } finally {
    await closeSessionSafely(session, logs);
  }
}

function candidateDimensions(candidate, item = null) {
  const width = Number(candidate.width || 0);
  const height = Number(candidate.height || 0);
  if (width > 0 && height > 0) return [width, height];
  if (item) {
    const itemWidth = Number(item.original_width || item.width || 0);
    const itemHeight = Number(item.original_height || item.height || 0);
    if (itemWidth > 0 && itemHeight > 0) return [itemWidth, itemHeight];
    const dimensions = item.dimensions;
    if (dimensions && typeof dimensions === "object") {
      const dimensionWidth = Number(dimensions.width || 0);
      const dimensionHeight = Number(dimensions.height || 0);
      if (dimensionWidth > 0 && dimensionHeight > 0) return [dimensionWidth, dimensionHeight];
    }
  }
  return [width, height];
}

function candidateStoryRatio(width, height) {
  if (width <= 0 || height <= 0) return 0;
  return width / height;
}

function isStoryRatio(width, height, strict = true) {
  if (width <= 0 || height <= 0) return false;
  if (height <= width) return false;
  const ratio = candidateStoryRatio(width, height);
  const minRatio = strict ? 0.52 : 0.46;
  const maxRatio = strict ? 0.60 : 0.68;
  const minWidth = strict ? 320 : 180;
  const minHeight = strict ? 560 : 280;
  return ratio >= minRatio && ratio <= maxRatio && width >= minWidth && height >= minHeight;
}

function storyRatioBonus(width, height) {
  const ratio = candidateStoryRatio(width, height);
  if (ratio <= 0) return -300;
  const distance = Math.abs(ratio - 0.5625);
  if (distance <= 0.01) return 140;
  if (distance <= 0.025) return 90;
  if (distance <= 0.04) return 45;
  return -20;
}

function passesStoryShapeGate(url, width, height) {
  const tag = mediaVariantTag(url);
  if (width > 0 && height > 0) {
    return isStoryRatio(width, height, !tag.includes("story"));
  }
  return tag.includes("story");
}

function chooseBestImageUrl(item) {
  const candidates = [];
  if (item.image_versions2?.candidates && Array.isArray(item.image_versions2.candidates)) {
    candidates.push(...item.image_versions2.candidates.filter((entry) => typeof entry === "object"));
  }
  if (Array.isArray(item.display_resources)) {
    candidates.push(...item.display_resources.filter((entry) => typeof entry === "object"));
  }

  let bestUrl = null;
  let bestScore = -1e9;
  for (const candidate of candidates) {
    const url = candidate.url;
    if (typeof url !== "string" || !isStoryMediaUrl(url)) continue;
    const [width, height] = candidateDimensions(candidate, item);
    if (!passesStoryShapeGate(url, width, height)) continue;
    const score = mediaVariantScore(url, "image") + Math.floor((width * height) / 5000) + storyRatioBonus(width, height);
    if (score > bestScore) {
      bestScore = score;
      bestUrl = normalizeMediaUrl(url);
    }
  }
  return bestUrl;
}

function chooseBestVideoUrl(item) {
  const variants = Array.isArray(item.video_versions) ? item.video_versions : [];
  const preferredUrls = [];
  let bestUrl = null;
  let bestScore = -1e9;
  for (const candidate of variants) {
    const url = candidate.url;
    if (typeof url !== "string" || !isStoryMediaUrl(url) || shouldSkipMediaVariant(url)) continue;
    const [width, height] = candidateDimensions(candidate, item);
    if (!passesStoryShapeGate(url, width, height)) continue;
    const normalizedUrl = normalizeMediaUrl(url);
    let score = mediaVariantScore(url, "video") + Math.floor((width * height) / 5000) + storyRatioBonus(width, height);
    if (candidate.type === 101) score += 25;
    if (candidate.type === 102) score += 10;
    const tag = mediaVariantTag(url);
    const lowered = url.toLowerCase();
    if (tag.includes("xpv_progressive") || tag.includes("progressive") || tag.includes("avc") || tag.includes("h264")) {
      preferredUrls.push([score, normalizedUrl]);
    }
    if ((tag.includes("audio") || tag.includes("aac") || tag.includes("haac")) && !isAudioOnlyVariant(url)) {
      preferredUrls.push([score + 40, normalizedUrl]);
    }
    if ((lowered.includes("xpv_progressive") || lowered.includes("progressive")) && !lowered.includes("dash")) {
      preferredUrls.push([score + 20, normalizedUrl]);
    }
    if (score > bestScore) {
      bestScore = score;
      bestUrl = normalizedUrl;
    }
  }
  if (preferredUrls.length > 0) {
    preferredUrls.sort((a, b) => b[0] - a[0]);
    return preferredUrls[0][1];
  }
  return bestUrl;
}

function extractItemUsername(item) {
  for (const key of ["user", "owner"]) {
    const value = item[key];
    if (value && typeof value === "object" && typeof value.username === "string" && value.username) {
      return value.username;
    }
  }
  return "";
}

function resolveStoryItemFromDict(item, expectedUsername) {
  const hasMedia =
    Array.isArray(item.video_versions) ||
    (item.image_versions2 && typeof item.image_versions2 === "object") ||
    Array.isArray(item.display_resources);
  if (!hasMedia) return null;

  const username = extractItemUsername(item) || expectedUsername;
  if (expectedUsername && username && sanitizeFilename(username) !== sanitizeFilename(expectedUsername)) return null;
  const itemId = item.id ?? item.pk;
  if (itemId === undefined || itemId === null) return null;

  const itemIdString = String(itemId);
  const mediaType = Array.isArray(item.video_versions) ? "video" : "image";
  const sourceUrl = mediaType === "video" ? chooseBestVideoUrl(item) : chooseBestImageUrl(item);
  if (!sourceUrl) return null;

  const pageUsername = sanitizeFilename(username || expectedUsername);
  const pageUrl = `https://www.instagram.com/stories/${pageUsername}/${itemIdString}/`;
  const takenAt = Number(item.taken_at || 0);
  return { itemId: itemIdString, username: pageUsername, pageUrl, sourceUrl, mediaType, takenAt };
}

function walkStoryItems(node, expectedUsername, seenIds, out) {
  if (Array.isArray(node)) {
    for (const value of node) walkStoryItems(value, expectedUsername, seenIds, out);
    return;
  }
  if (!node || typeof node !== "object") return;

  const resolved = resolveStoryItemFromDict(node, expectedUsername);
  if (resolved && !seenIds.has(resolved.itemId)) {
    seenIds.add(resolved.itemId);
    out.push(resolved);
  }
  for (const value of Object.values(node)) {
    walkStoryItems(value, expectedUsername, seenIds, out);
  }
}

function responseUrlLikelyStory(url) {
  const lowered = url.toLowerCase();
  if (lowered.includes("/stories/highlights/") || lowered.includes("highlight")) return false;
  if (lowered.includes("story") || lowered.includes("/stories/")) return true;
  if (lowered.includes("feed")) return false;
  return false;
}

function resolveStoryItemsFromPayloads(payloads, expectedUsername, capturedAfter = null) {
  const filteredPayloads = [];
  const storyPayloads = [];
  for (const entry of payloads) {
    const capturedAt = entry.captured_at;
    if (capturedAfter !== null && typeof capturedAt === "number" && capturedAt < capturedAfter) continue;
    filteredPayloads.push(entry);
    if (typeof entry.url === "string" && responseUrlLikelyStory(entry.url)) {
      storyPayloads.push(entry);
    }
  }
  const preferred = storyPayloads.length > 0 ? storyPayloads : filteredPayloads;
  const seenIds = new Set();
  const resolved = [];
  for (const entry of preferred) {
    walkStoryItems(entry.payload, expectedUsername, seenIds, resolved);
  }
  resolved.sort((a, b) => (a.takenAt || 0) - (b.takenAt || 0));
  return resolved;
}

async function waitForMetadataStoryItems(page, payloads, expectedUsername, logs, timeoutSeconds = 12, capturedAfter = null) {
  const deadline = Date.now() + timeoutSeconds * 1000;
  let best = [];
  while (Date.now() < deadline) {
    const resolved = resolveStoryItemsFromPayloads(payloads, expectedUsername, capturedAfter);
    if (resolved.length > 0) {
      best = resolved;
      if (resolved.length > 1) break;
    }
    await page.waitForTimeout(600);
  }
  if (best.length > 0) logs.push(`metadata_story_items=${best.length}`);
  return best;
}

async function nextStoryIndex(destinationDir, username) {
  await fs.mkdir(destinationDir, { recursive: true });
  const prefix = `${sanitizeFilename(username)}-`;
  let highest = 0;
  for (const entry of await fs.readdir(destinationDir)) {
    const match = entry.match(new RegExp(`^${prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(\\d+)`));
    if (!match) continue;
    highest = Math.max(highest, Number(match[1]));
  }
  return highest + 1;
}

function installNetworkCapture(page, logs) {
  const captured = [];
  const seenUrls = new Set();
  page.on("response", async (response) => {
    try {
      const headers = await response.allHeaders();
      const contentType = headers["content-type"] || "";
      const url = response.url();
      if (seenUrls.has(url)) return;

      const lowered = url.toLowerCase();
      let mediaType = null;
      if (contentType.startsWith("video/") || lowered.endsWith(".mp4")) mediaType = "video";
      else if (contentType.startsWith("image/") || /\.(jpg|jpeg|png|webp)$/.test(lowered)) mediaType = "image";
      if (!mediaType) return;
      if (!isStoryMediaUrl(url) || shouldSkipMediaVariant(url)) return;
      seenUrls.add(url);
      captured.push({
        sourceUrl: normalizeMediaUrl(url),
        mediaType,
        pageUrl: page.url(),
        capturedAt: Date.now() / 1000,
      });
    } catch (error) {
      logs.push(`network_capture_error=${error}`);
    }
  });
  return captured;
}

function installJsonCapture(page, logs) {
  const payloads = [];
  page.on("response", async (response) => {
    try {
      const headers = await response.allHeaders();
      const contentType = (headers["content-type"] || "").toLowerCase();
      const url = response.url().toLowerCase();
      if (!contentType.includes("json")) return;
      if (!["story", "reel", "graphql", "feed", "api"].some((token) => url.includes(token))) return;
      const payload = await response.json();
      if (typeof payload !== "object") return;
      payloads.push({ url: response.url(), captured_at: Date.now() / 1000, payload });
    } catch (error) {
      logs.push(`json_capture_error=${error}`);
    }
  });
  return payloads;
}

async function storyViewerReady(page) {
  return await page.evaluate(() => {
    const hasDialog = Boolean(document.querySelector('[role="dialog"]'));
    const hasProgress = document.querySelectorAll('div[role="progressbar"]').length > 0;
    const hasCenteredMedia = [...document.querySelectorAll("video, img")].some((node) => {
      const rect = node.getBoundingClientRect();
      const centerX = window.innerWidth / 2;
      const centerY = window.innerHeight / 2;
      return rect.width > 180 && rect.height > 280 && rect.left <= centerX && rect.right >= centerX && rect.top <= centerY && rect.bottom >= centerY;
    });
    return hasDialog || hasProgress || hasCenteredMedia;
  });
}

async function extractMediaCandidate(page) {
  const candidate = await page.evaluate(() => {
    const viewportCenterX = window.innerWidth / 2;
    const viewportCenterY = window.innerHeight / 2;
    const hasDialog = Boolean(document.querySelector('[role="dialog"]'));
    const nodes = [...document.querySelectorAll("video, img")];
    const visible = nodes
      .map((node) => {
        const rect = node.getBoundingClientRect();
        const style = window.getComputedStyle(node);
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;
        const containsViewportCenter =
          rect.left <= viewportCenterX &&
          rect.right >= viewportCenterX &&
          rect.top <= viewportCenterY &&
          rect.bottom >= viewportCenterY;
        const distanceToCenter = Math.hypot(centerX - viewportCenterX, centerY - viewportCenterY);
        const inDialog = Boolean(node.closest('[role="dialog"]'));
        const inHeader = Boolean(node.closest("header"));
        const inLink = Boolean(node.closest("a"));
        return {
          tag: node.tagName.toLowerCase(),
          src: node.currentSrc || node.src || "",
          poster: node.poster || "",
          width: rect.width,
          height: rect.height,
          ratio: rect.height > 0 ? rect.width / rect.height : 0,
          area: rect.width * rect.height,
          hidden: style.display === "none" || style.visibility === "hidden" || style.opacity === "0",
          containsViewportCenter,
          distanceToCenter,
          inDialog,
          inHeader,
          inLink,
        };
      })
      .filter(
        (item) =>
          !item.hidden &&
          item.src &&
          item.width > 180 &&
          item.height > 280 &&
          item.height > item.width &&
          item.ratio >= 0.46 &&
          item.ratio <= 0.68 &&
          (!hasDialog || item.inDialog) &&
          !item.inHeader &&
          (item.containsViewportCenter || item.inDialog) &&
          !(item.inLink && !item.containsViewportCenter && !item.inDialog),
      )
      .sort((a, b) => {
        if (a.containsViewportCenter !== b.containsViewportCenter) return a.containsViewportCenter ? -1 : 1;
        if (a.inDialog !== b.inDialog) return a.inDialog ? -1 : 1;
        if (Math.abs(a.area - b.area) > 1000) return b.area - a.area;
        return a.distanceToCenter - b.distanceToCenter;
      });
    return visible[0] || null;
  });
  if (!candidate) return null;
  const sourceUrl = normalizeMediaUrl(candidate.src || "");
  if (!isStoryMediaUrl(sourceUrl)) return null;
  return {
    sourceUrl,
    mediaType: candidate.tag === "video" ? "video" : "image",
    pageUrl: page.url(),
    posterUrl: candidate.poster || null,
    capturedAt: Date.now() / 1000,
    width: Number(candidate.width || 0),
    height: Number(candidate.height || 0),
  };
}

function isHighlightStoryUrl(url) {
  const lowered = url.toLowerCase();
  return lowered.includes("/stories/highlights/") || lowered.includes("/highlights/");
}

function isActiveStoryPage(url, username = null) {
  const lowered = url.toLowerCase();
  if (isHighlightStoryUrl(lowered)) return false;
  if (!lowered.includes("/stories/")) return false;
  if (username) return lowered.includes(`/stories/${sanitizeFilename(username).toLowerCase()}/`);
  return true;
}

function latestNetworkCandidate(page, networkCandidates, seenSources) {
  const now = Date.now() / 1000;
  const viable = [];
  for (const candidate of [...networkCandidates].reverse()) {
    if (seenSources.has(candidate.sourceUrl)) continue;
    if (now - candidate.capturedAt > 20) continue;
    if (!isActiveStoryPage(candidate.pageUrl) && !isActiveStoryPage(page.url())) continue;
    if (shouldSkipMediaVariant(candidate.sourceUrl)) continue;
    const tag = mediaVariantTag(candidate.sourceUrl);
    if (!tag.includes("story")) continue;
    viable.push({ ...candidate, pageUrl: page.url() });
  }
  viable.sort((a, b) => {
    const scoreDelta = mediaVariantScore(b.sourceUrl, b.mediaType) - mediaVariantScore(a.sourceUrl, a.mediaType);
    if (scoreDelta !== 0) return scoreDelta;
    return b.capturedAt - a.capturedAt;
  });
  return viable[0] || null;
}

async function waitForStoryMedia(page, networkCandidates, seenSources, timeoutSeconds = 20) {
  const deadline = Date.now() + timeoutSeconds * 1000;
  const networkFallbackDeadline = Date.now() + Math.min(timeoutSeconds, 8) * 1000;
  while (Date.now() < deadline) {
    if (isHighlightStoryUrl(page.url())) return null;
    if (!isActiveStoryPage(page.url())) {
      await page.waitForTimeout(800);
      continue;
    }
    if (!(await storyViewerReady(page))) {
      await page.waitForTimeout(800);
      continue;
    }
    const candidate = await extractMediaCandidate(page);
    if (candidate) return candidate;
    if (Date.now() < networkFallbackDeadline) {
      await page.waitForTimeout(800);
      continue;
    }
    const networkCandidate = latestNetworkCandidate(page, networkCandidates, seenSources);
    if (networkCandidate) return networkCandidate;
    await page.waitForTimeout(800);
  }
  return null;
}

function storySignature(pageUrl, sourceUrl) {
  return `${pageUrl}|${normalizeMediaUrl(sourceUrl)}`;
}

async function clickNextStory(page) {
  const viewport = page.viewportSize() || { width: 1440, height: 900 };
  await page.mouse.click(viewport.width * 0.85, viewport.height * 0.5);
}

async function advanceToNextStory(page, networkCandidates, seenSources, previousSignature, logs) {
  const actions = [
    ["click", async () => clickNextStory(page)],
    ["arrow", async () => page.keyboard.press("ArrowRight")],
    ["space", async () => page.keyboard.press("Space")],
  ];
  for (const [actionName, action] of actions) {
    try {
      await action();
    } catch (error) {
      logs.push(`advance_action_error=${actionName}:${error}`);
      continue;
    }
    await page.waitForTimeout(1200);
    if (!page.url().includes("/stories/")) return false;
    const nextMedia = await waitForStoryMedia(page, networkCandidates, seenSources, 6);
    if (!nextMedia) continue;
    const nextSignature = storySignature(nextMedia.pageUrl, nextMedia.sourceUrl);
    if (nextSignature !== previousSignature) return true;
  }
  return false;
}

async function clickProfileStoryRing(page, username, logs) {
  const selectors = [`a[href="/stories/${username}/"]`, "header canvas", "header img"];
  for (const selector of selectors) {
    try {
      const locator = page.locator(selector).first();
      if ((await locator.count()) === 0) continue;
      await locator.click({ timeout: 2500 });
      await page.waitForTimeout(1500);
      if (isActiveStoryPage(page.url(), username)) {
        logs.push(`profile_story_opened_via=${selector}`);
        return true;
      }
      if (isHighlightStoryUrl(page.url())) {
        logs.push(`profile_story_rejected_highlight=${selector}`);
      }
    } catch {}
  }
  return false;
}

async function clickStoryGateIfNeeded(page, logs) {
  const buttonSelectors = [
    'button:has-text("Посмотреть историю")',
    'button:has-text("Посмотреть сторис")',
    'button:has-text("View story")',
    'button:has-text("Watch story")',
  ];
  for (const selector of buttonSelectors) {
    try {
      const locator = page.locator(selector).first();
      if ((await locator.count()) === 0) continue;
      await locator.click({ timeout: 2000 });
      await page.waitForTimeout(1500);
      logs.push(`story_gate_clicked=${selector}`);
      return;
    } catch {}
  }
}

async function fetchMediaBytes(sourceUrl, browserContext, refererUrl = null) {
  const headers = {
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
  };
  if (refererUrl) headers.Referer = refererUrl;
  const response = await withRetry(
    async () => await browserContext.request.get(sourceUrl, {
      headers,
      timeout: 60_000,
      failOnStatusCode: true,
      ignoreHTTPSErrors: true,
      maxRetries: 1,
    }),
    {
      attempts: 3,
      baseDelayMs: 700,
      onRetry: ({ attempt, delayMs, error }) => {
        void appendWorkerEvent({ type: "retry", operation: "fetch_media", url: sourceUrl, attempt, delayMs, error: errorMessage(error) });
      },
    },
  );
  return {
    body: await response.body(),
    contentType: response.headers()["content-type"] || null,
  };
}

async function loadManifestIndex(manifestsDirectory) {
  const sources = new Map();
  const hashes = new Map();
  try {
    await fs.mkdir(manifestsDirectory, { recursive: true });
    const entries = await fs.readdir(manifestsDirectory);
    for (const entry of entries) {
      if (!entry.endsWith(".json")) continue;
      try {
        const manifestPath = path.join(manifestsDirectory, entry);
        const payload = JSON.parse(await fs.readFile(manifestPath, "utf8"));
        const sourceURL = payload.sourceURL || payload.sourceUrl;
        const sha256 = payload.sha256;
        if (typeof sourceURL === "string" && sourceURL) {
          sources.set(normalizeMediaUrl(sourceURL), { ...payload, manifestPath });
        }
        if (typeof sha256 === "string" && sha256) {
          hashes.set(sha256.toLowerCase(), { ...payload, manifestPath });
        }
      } catch {
        // Ignore malformed legacy manifests.
      }
    }
  } catch {
    // Empty or unavailable manifest directory should not block downloads.
  }
  return { sources, hashes };
}

function extensionFor(contentType, url, mediaType) {
  try {
    const parsed = new URL(url);
    const suffix = path.extname(parsed.pathname);
    if (suffix) return suffix;
  } catch {}
  if (contentType) {
    const lowered = contentType.toLowerCase();
    if (lowered.startsWith("video/")) return ".mp4";
    if (lowered.includes("webp")) return ".webp";
    if (lowered.includes("png")) return ".png";
    if (lowered.includes("jpeg") || lowered.includes("jpg")) return ".jpg";
  }
  return mediaType === "video" ? ".mp4" : ".jpg";
}

function looksLikeFragmentedMp4(body) {
  const prefix = body.subarray(0, 64).toString("binary");
  return prefix.includes("moof") && !prefix.includes("ftyp");
}

async function downloadMedia(sourceUrl, destinationDir, mediaType, username, index, browserContext, refererUrl = null) {
  await fs.mkdir(destinationDir, { recursive: true });
  const normalizedUrl = normalizeMediaUrl(sourceUrl);
  const { body, contentType } = await withRetry(
    async () => {
      const fetched = await fetchMediaBytes(normalizedUrl, browserContext, refererUrl);
      validateDownloadedMedia(fetched.body, mediaType, fetched.contentType);
      return fetched;
    },
    { attempts: 2, baseDelayMs: 600 },
  );
  if (mediaType === "video" && looksLikeFragmentedMp4(body)) {
    throw new Error("Скачан только фрагмент видео вместо полного файла.");
  }
  const suffix = extensionFor(contentType, normalizedUrl, mediaType);
  const filename = `${sanitizeFilename(username)}-${String(index).padStart(3, "0")}${suffix}`;
  const localPath = path.join(destinationDir, filename);
  await fs.writeFile(localPath, body);
  return { localPath, finalSourceUrl: normalizedUrl, contentLength: body.length };
}

async function writeManifest({ itemId, pageUrl, sourceUrl, localPath, mediaType, createdAt, username, storyId = "", sourceKind = "story", contentLength = 0 }) {
  const fileHash = createHash("sha256").update(await fs.readFile(localPath)).digest("hex");
  const payload = {
    schemaVersion: 2,
    id: itemId,
    createdAt,
    downloadedAt: createdAt,
    command: "download_profile_stories",
    username,
    storyId,
    shortcode: "",
    sourceKind,
    pageURL: pageUrl,
    sourceURL: sourceUrl,
    localPath,
    mediaType,
    contentLength,
    diagnosticCategory: "ok",
    sha256: fileHash,
  };
  const manifestPath = path.join(MANIFESTS_DIRECTORY, `${itemId}.json`);
  await fs.writeFile(manifestPath, JSON.stringify(payload, null, 2), "utf8");
  return manifestPath;
}

function extractFoundCount(logs, fallback) {
  for (const line of [...logs].reverse()) {
    if (line.startsWith("metadata_story_items=")) {
      const raw = line.split("=", 2)[1];
      if (/^\d+$/.test(raw)) return Number(raw);
    }
  }
  return fallback;
}

function shouldPersistMedia(mediaType, mediaFilter = "all") {
  if (mediaFilter === "video_only") {
    return mediaType === "video";
  }
  return true;
}

async function persistStoryItems(resolvedItems, destinationDir, username, browserContext, mediaFilter = "all") {
  const logs = [];
  const items = [];
  const seenSources = new Set();
  const seenHashes = new Set();
  const manifestIndex = await loadManifestIndex(MANIFESTS_DIRECTORY);
  let nextIndexValue = await nextStoryIndex(destinationDir, username);

  for (const resolved of resolvedItems) {
    if (!shouldPersistMedia(resolved.mediaType, mediaFilter)) {
      logs.push(`skipped_by_media_filter=${resolved.mediaType}`);
      continue;
    }
    const normalizedSource = normalizeMediaUrl(resolved.sourceUrl);
    if (seenSources.has(normalizedSource)) {
      logs.push(`skipped_current_source=${normalizedSource}`);
      continue;
    }
    if (manifestIndex.sources.has(normalizedSource)) {
      seenSources.add(normalizedSource);
      logs.push(`skipped_existing_source=${normalizedSource}`);
      continue;
    }
    const { localPath, finalSourceUrl, contentLength } = await downloadMedia(
      normalizedSource,
      destinationDir,
      resolved.mediaType,
      username,
      nextIndexValue,
      browserContext,
      resolved.pageUrl,
    );
    const fileHash = createHash("sha256").update(await fs.readFile(localPath)).digest("hex");
    if (seenHashes.has(fileHash) || manifestIndex.hashes.has(fileHash)) {
      await fs.rm(localPath, { force: true });
      seenSources.add(finalSourceUrl);
      logs.push(`${seenHashes.has(fileHash) ? "skipped_current_hash" : "skipped_existing_hash"}=${fileHash}`);
      continue;
    }
    const itemId = randomUUID().replace(/-/g, "");
    const createdAt = new Date().toISOString();
    const manifestPath = await writeManifest({
      itemId,
      pageUrl: resolved.pageUrl,
      sourceUrl: finalSourceUrl,
      localPath,
      mediaType: resolved.mediaType,
      createdAt,
      username,
      storyId: resolved.itemId,
      contentLength,
    });
    items.push({
      id: itemId,
      sourceURL: finalSourceUrl,
      pageURL: resolved.pageUrl,
      localPath,
      metadataPath: manifestPath,
      mediaType: resolved.mediaType,
      createdAt,
    });
    seenSources.add(finalSourceUrl);
    seenHashes.add(fileHash);
    manifestIndex.sources.set(finalSourceUrl, { id: itemId, localPath, manifestPath });
    manifestIndex.hashes.set(fileHash, { id: itemId, localPath, manifestPath });
    nextIndexValue += 1;
    logs.push(`saved=${localPath}`);
    logs.push(`manifest=${manifestPath}`);
  }
  return { items, logs };
}

async function collectStorySequence(page, destinationDir, username, jsonPayloads, networkCandidates, metadataCapturedAfter = null, persistMetadataItems = true, mediaFilter = "all") {
  const logs = [];

  if (isHighlightStoryUrl(page.url())) {
    logs.push(`highlight_page_rejected=${page.url()}`);
    return { items: [], logs };
  }

  if (!isActiveStoryPage(page.url(), username)) {
    logs.push(`active_story_page_missing=${page.url()}`);
    return { items: [], logs };
  }

  const resolvedItems = await waitForMetadataStoryItems(page, jsonPayloads, username, logs, 12, metadataCapturedAfter);
  if (resolvedItems.length > 0 && persistMetadataItems) {
    const persisted = await persistStoryItems(resolvedItems, destinationDir, username, page.context(), mediaFilter);
    logs.push(...persisted.logs);
    if (persisted.items.length > 0) {
      return { items: persisted.items, logs };
    }
    logs.push("metadata_only_no_new_items");
  }

  const seenSources = new Set();
  const seenHashes = new Set();
  const seenSignatures = new Set();
  const items = [];
  const manifestIndex = await loadManifestIndex(MANIFESTS_DIRECTORY);
  let nextIndexValue = await nextStoryIndex(destinationDir, username);

  for (let i = 0; i < 50; i += 1) {
    const media = await waitForStoryMedia(page, networkCandidates, seenSources, 20);
    if (!media) {
      logs.push("На странице не найдено видимого media из story.");
      break;
    }
    const normalizedSource = normalizeMediaUrl(media.sourceUrl);
    const signature = storySignature(media.pageUrl, normalizedSource);
    if (seenSignatures.has(signature)) {
      if (!(await advanceToNextStory(page, networkCandidates, new Set([...seenSources, normalizedSource]), signature, logs))) {
        break;
      }
      continue;
    }

    if (seenSources.has(normalizedSource)) {
      seenSignatures.add(signature);
      logs.push(`skipped_current_source=${normalizedSource}`);
    } else if (manifestIndex.sources.has(normalizedSource)) {
      seenSignatures.add(signature);
      seenSources.add(normalizedSource);
      logs.push(`skipped_existing_source=${normalizedSource}`);
    } else {
      if (!shouldPersistMedia(media.mediaType, mediaFilter)) {
        seenSignatures.add(signature);
        seenSources.add(normalizedSource);
        logs.push(`skipped_by_media_filter=${media.mediaType}`);
        if (!(await advanceToNextStory(page, networkCandidates, new Set([...seenSources, normalizedSource]), signature, logs))) {
          break;
        }
        continue;
      }
      const { localPath, finalSourceUrl, contentLength } = await downloadMedia(
        normalizedSource,
        destinationDir,
        media.mediaType,
        username,
        nextIndexValue,
        page.context(),
        media.pageUrl,
      );
      const fileHash = createHash("sha256").update(await fs.readFile(localPath)).digest("hex");
      if (seenHashes.has(fileHash) || manifestIndex.hashes.has(fileHash)) {
        await fs.rm(localPath, { force: true });
        seenSignatures.add(signature);
        seenSources.add(finalSourceUrl);
        logs.push(`${seenHashes.has(fileHash) ? "skipped_current_hash" : "skipped_existing_hash"}=${fileHash}`);
      } else {
        const itemId = randomUUID().replace(/-/g, "");
        const createdAt = new Date().toISOString();
        const manifestPath = await writeManifest({
          itemId,
          pageUrl: media.pageUrl,
          sourceUrl: finalSourceUrl,
          localPath,
          mediaType: media.mediaType,
          createdAt,
          username,
          storyId: "",
          contentLength,
        });
        items.push({
          id: itemId,
          sourceURL: finalSourceUrl,
          pageURL: media.pageUrl,
          localPath,
          metadataPath: manifestPath,
          mediaType: media.mediaType,
          createdAt,
        });
        seenSignatures.add(signature);
        seenSources.add(finalSourceUrl);
        seenHashes.add(fileHash);
        manifestIndex.sources.set(finalSourceUrl, { id: itemId, localPath, manifestPath });
        manifestIndex.hashes.set(fileHash, { id: itemId, localPath, manifestPath });
        nextIndexValue += 1;
        logs.push(`saved=${localPath}`);
        logs.push(`manifest=${manifestPath}`);
      }
    }
    if (!(await advanceToNextStory(page, networkCandidates, new Set([...seenSources, normalizedSource]), signature, logs))) {
      break;
    }
  }
  return { items, logs };
}

async function ensureLoggedIn(page) {
  if (await isLoggedIn(page)) return;
  throw new Error("Требуется вход в Instagram. Сначала откройте браузер для входа.");
}

async function downloadProfileWithPage(page, profileUrl, outputDirectory, mediaFilter = "all") {
  const username = extractUsername(profileUrl);
  if (!username) {
    return {
      ok: false,
      status: "profile_error",
      message: "Не удалось извлечь имя пользователя из ссылки на профиль.",
      data: { foundCount: "0", savedCount: "0" },
      items: [],
      logs: [],
      username: "",
      profileUrl,
    };
  }

  const rootDestination = path.resolve(outputDirectory || DEFAULT_DOWNLOADS);
  const destination = path.join(rootDestination, sanitizeFilename(username));
  const logs = [];

  try {
    const jsonPayloads = installJsonCapture(page, logs);
    const networkCandidates = installNetworkCapture(page, logs);

    const profilePageUrl = `https://www.instagram.com/${username}/`;
    await retryingGoto(page, profilePageUrl, { waitUntil: "domcontentloaded" }, logs, "profile_goto");
    await ensureLoggedIn(page);
    await persistSessionState(page.context(), logs);
    await page.waitForTimeout(1500);
    logs.push(`profile_download_directory=${destination}`);

    const storyCaptureStartedAt = Date.now() / 1000;
    const opened = await clickProfileStoryRing(page, username, logs);
    if (!opened) {
      const fallback = `https://www.instagram.com/stories/${username}/`;
      await retryingGoto(page, fallback, { waitUntil: "domcontentloaded" }, logs, "story_fallback_goto");
      await ensureLoggedIn(page);
      logs.push(`profile_fallback=${fallback}`);
    }

    await clickStoryGateIfNeeded(page, logs);
    logs.push(`opened=${page.url()}`);

    const result = await collectStorySequence(
      page,
      destination,
      username,
      jsonPayloads,
      networkCandidates,
      storyCaptureStartedAt,
      true,
      mediaFilter,
    );
    logs.push(...result.logs);
    const foundCountAllStories = extractFoundCount(result.logs, result.items.length);
    const foundCount = foundCountAllStories;

    if (result.items.length === 0 && mediaFilter === "video_only" && foundCountAllStories > 0) {
      return {
        ok: true,
        status: "download_filtered",
        message: `Для профиля ${username} активные stories найдены, но видео для сохранения не обнаружены.`,
        data: { foundCount: String(foundCountAllStories), savedCount: "0" },
        items: [],
        logs,
        username,
        profileUrl,
      };
    }

    if (result.items.length === 0 && result.logs.some((entry) => entry.startsWith("skipped_existing_"))) {
      return {
        ok: true,
        status: "download_duplicate",
        message: `Для профиля ${username} все найденные stories уже были сохранены ранее.`,
        data: { foundCount: String(foundCount), savedCount: "0" },
        items: [],
        logs,
        username,
        profileUrl,
      };
    }

    if (result.items.length === 0) {
      return {
        ok: false,
        status: "download_empty",
        message: `Для профиля ${username} не удалось получить активные stories.`,
        data: { foundCount: String(foundCount), savedCount: "0" },
        items: [],
        logs,
        username,
        profileUrl,
      };
    }

    return {
      ok: true,
      status: "download_complete",
      message: `Для профиля ${username} сохранено файлов: ${result.items.length}.`,
      data: { foundCount: String(foundCount), savedCount: String(result.items.length) },
      items: result.items,
      logs,
      username,
      profileUrl,
    };
  } catch (error) {
    return {
      ok: false,
      status: "download_error",
      message: String(error),
      data: { foundCount: "0", savedCount: "0" },
      items: [],
      logs,
      username,
      profileUrl,
    };
  }
}

async function profileCommand(profileUrl, outputDirectory, headless = true, mediaFilter = "all") {
  await ensureDirectories();
  let session = null;

  try {
    session = await launchContext(headless);
    const page = await session.firstPage();
    await prepareBackgroundWindow(session, page, []);
    const result = await downloadProfileWithPage(page, profileUrl, outputDirectory, mediaFilter);
    emit(result.ok, result.status, result.message, {
      data: result.data,
      items: result.items,
      logs: result.logs,
    });
  } finally {
    await closeSessionSafely(session);
  }
}

async function profileBatchCommand(profileUrls, outputDirectory, headless = true, mediaFilter = "all") {
  await ensureDirectories();
  const normalizedUrls = profileUrls
    .map((entry) => String(entry || "").trim())
    .filter((entry) => entry.length > 0);

  if (normalizedUrls.length === 0) {
    emit(false, "request_error", "Для пакетной выгрузки нужен хотя бы один профиль.");
    return;
  }

  const logs = [];
  const items = [];
  const batchResults = new Array(normalizedUrls.length);
  let totalFound = 0;
  let totalSaved = 0;
  let processedCount = 0;
  let successCount = 0;
  let session = null;
  let batchAbortMessage = null;
  let contextClosed = false;

  try {
    session = await launchContext(headless);
    const windowPage = await session.firstPage();
    await prepareBackgroundWindow(session, windowPage, logs);
    session.context.on("close", () => {
      contextClosed = true;
      logs.push("batch_context_closed");
    });
    const concurrency = Math.min(headless ? 3 : 1, normalizedUrls.length);
    let cursor = 0;
    logs.push(`batch_concurrency=${concurrency}`);

    const attachPageLogger = (page, slot) => {
      page.on("close", () => {
        logs.push(`batch_page_closed_slot_${slot}`);
      });
    };

    const buildFailureResult = (url, message) => ({
      url,
      status: "failed",
      message,
      foundCount: 0,
      savedCount: 0,
    });

    const fillMissingBatchResults = (message) => {
      for (let index = 0; index < normalizedUrls.length; index += 1) {
        if (!batchResults[index]) {
          batchResults[index] = buildFailureResult(normalizedUrls[index], message);
        }
      }
    };

    const ensurePageForSlot = async (slot, page) => {
      if (!page.isClosed()) {
        return page;
      }
      if (contextClosed) {
        throw new Error("Окно браузера было закрыто во время пакетной выгрузки.");
      }
      const replacement = await session.context.newPage();
      attachPageLogger(replacement, slot);
      logs.push(`batch_page_recreated_slot_${slot}`);
      return replacement;
    };

    const nextJob = () => {
      if (batchAbortMessage) {
        return null;
      }
      if (cursor >= normalizedUrls.length) {
        return null;
      }
      const index = cursor;
      cursor += 1;
      return { index, normalizedUrl: normalizedUrls[index] };
    };

    const workerLoop = async (slot, initialPage) => {
      let page = initialPage;
      while (true) {
        if (batchAbortMessage) {
          return;
        }

        page = await ensurePageForSlot(slot, page);
        const job = nextJob();
        if (!job) {
          return;
        }

        logs.push(`batch_slot_${slot}_start=${job.normalizedUrl}`);
        emitProgress(`batch_slot_${slot}_start=${job.normalizedUrl}`);
        let result = null;
        try {
          result = await withTimeout(
            downloadProfileWithPage(page, job.normalizedUrl, outputDirectory, mediaFilter),
            BATCH_JOB_TIMEOUT_MS,
            `Выгрузка профиля ${job.normalizedUrl} превысила лимит ожидания.`,
          );
        } catch (error) {
          const message = errorMessage(error);
          batchResults[job.index] = buildFailureResult(job.normalizedUrl, message);
          processedCount += 1;
          logs.push(`batch_slot_${slot}_error=${job.normalizedUrl} :: ${message}`);
          await closePageAfterBatchTimeout(error, page, slot, job.normalizedUrl, logs);
          if (contextClosed || isClosedTargetError(error)) {
            batchAbortMessage ||= message;
            return;
          }
          continue;
        }

        if (!result) {
          const message = "Воркер не вернул результат пакетной выгрузки.";
          batchResults[job.index] = buildFailureResult(job.normalizedUrl, message);
          processedCount += 1;
          logs.push(`batch_slot_${slot}_error=${job.normalizedUrl} :: ${message}`);
          continue;
        }

        if (headless) {
          try {
            await page.goto("about:blank");
          } catch {}
        }

        const foundCount = Number(result.data.foundCount || "0");
        const savedCount = Number(result.data.savedCount || "0");
        totalFound += foundCount;
        totalSaved += savedCount;
        if (result.ok) successCount += 1;
        items.push(...result.items);
        logs.push(...result.logs.map((entry) => `[${result.username || job.normalizedUrl}] ${entry}`));
        const resultStatus = result.ok ? "completed" : "failed";
        batchResults[job.index] = {
          url: job.normalizedUrl,
          status: resultStatus,
          message: result.message,
          foundCount,
          savedCount,
        };
        processedCount += 1;
        if (contextClosed || isClosedTargetMessage(result.message)) {
          const message = contextClosed
            ? "Окно браузера было закрыто во время пакетной выгрузки."
            : result.message;
          logs.push(`batch_slot_${slot}_error=${job.normalizedUrl} :: ${message}`);
          batchAbortMessage ||= message;
          return;
        }
        logs.push(`batch_slot_${slot}_done=${job.normalizedUrl}`);
        emitProgress(`batch_slot_${slot}_done=${job.normalizedUrl}`);
      }
    };

    const pages = [windowPage];
    attachPageLogger(windowPage, 1);
    for (let i = 1; i < concurrency; i += 1) {
      const page = await session.context.newPage();
      attachPageLogger(page, i + 1);
      pages.push(page);
    }

    await Promise.all(
      pages.map((page, index) => workerLoop(index + 1, page))
    );

    for (const page of pages.slice(1)) {
      try {
        await page.close();
      } catch {}
    }

    if (batchAbortMessage) {
      fillMissingBatchResults(`Пакетная выгрузка прервана: ${batchAbortMessage}`);
    } else {
      fillMissingBatchResults("Для профиля нет результата пакетной выгрузки.");
    }

    const ok = successCount > 0;
    const status = batchAbortMessage
      ? (ok ? "batch_incomplete" : "batch_failed")
      : (ok ? "batch_complete" : "batch_failed");
    const message = batchAbortMessage
      ? `Пакетная выгрузка прервана: ${batchAbortMessage}`
      : ok
        ? `Пакетная выгрузка завершена. Обработано профилей: ${normalizedUrls.length}.`
        : "Не удалось получить активные stories ни для одного профиля из очереди.";

    emit(ok, status, message, {
      data: {
        foundCount: String(totalFound),
        savedCount: String(totalSaved),
        processedCount: String(processedCount),
        batchResults: JSON.stringify(batchResults),
      },
      items,
      logs,
    });
  } catch (error) {
    emit(false, "download_error", String(error), {
      data: {
        foundCount: String(totalFound),
        savedCount: String(totalSaved),
        processedCount: String(processedCount),
        batchResults: JSON.stringify(
          batchResults.map((entry, index) => entry || {
            url: normalizedUrls[index],
            status: "failed",
            message: `Пакетная выгрузка завершилась ошибкой: ${errorMessage(error)}`,
            foundCount: 0,
            savedCount: 0,
          })
        ),
      },
      items,
      logs,
    });
  } finally {
    await closeSessionSafely(session, logs);
  }
}

async function main() {
  try {
    const request = await readRequest();
    const command = request.command;
    const url = request.url;
    const urls = Array.isArray(request.urls) ? request.urls : [];
    const outputDirectory = request.outputDirectory;
    const headless = request.headless ?? true;
    const mediaFilter = request.mediaFilter ?? "all";

    if (command === "environment") {
      await environmentCommand();
    } else if (command === "health") {
      await healthCommand();
    } else if (command === "login") {
      await loginCommand();
    } else if (command === "check_session") {
      await checkSessionCommand(Boolean(headless));
    } else if (command === "download_profile_stories") {
      if (!url) {
        emit(false, "request_error", "Для download_profile_stories нужна ссылка на профиль или имя пользователя.");
        return;
      }
      await profileCommand(url, outputDirectory, Boolean(headless), mediaFilter);
    } else if (command === "download_profile_batch") {
      await profileBatchCommand(urls, outputDirectory, Boolean(headless), mediaFilter);
    } else if (command === "download_reels_urls") {
      const result = await downloadReelsCommand(urls.length > 0 ? urls : (url ? [url] : []), outputDirectory, Boolean(headless), {
        defaultDownloads: DEFAULT_DOWNLOADS,
        manifestsDirectory: MANIFESTS_DIRECTORY,
        launchContext,
        prepareBackgroundWindow,
        ensureLoggedIn,
        persistSessionState,
        installJsonCapture,
      });
      emit(result.ok, result.status, result.message, {
        data: result.data,
        items: result.items,
        logs: result.logs,
      });
    } else if (command === "download_story_url") {
      emit(false, "request_error", "download_story_url пока не перенесён в Node worker.");
    } else {
      emit(false, "request_error", `Неподдерживаемая команда: ${command}`);
    }
  } catch (error) {
    emit(false, "worker_exception", String(error));
  }
}

await main();
