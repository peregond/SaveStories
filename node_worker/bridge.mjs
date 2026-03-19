#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import process from "node:process";
import { createHash, randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";

const APP_NAME = "DimaSave";

function emit(ok, status, message, { data = {}, items = [], logs = [] } = {}) {
  process.stdout.write(
    JSON.stringify({
      ok,
      status,
      message,
      data,
      items,
      logs,
    }),
  );
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

const APP_SUPPORT = process.env.DIMASAVE_APP_SUPPORT || (await defaultAppSupport());
const WORKER_ROOT = path.join(APP_SUPPORT, "worker");
const BROWSER_PROFILE = process.env.DIMASAVE_BROWSER_PROFILE || path.join(WORKER_ROOT, "browser-profile");
const PLAYWRIGHT_BROWSERS =
  process.env.DIMASAVE_PLAYWRIGHT_BROWSERS || path.join(WORKER_ROOT, "ms-playwright");
const MANIFESTS_DIRECTORY = process.env.DIMASAVE_MANIFESTS || path.join(APP_SUPPORT, "manifests");
const SESSION_STATE = process.env.DIMASAVE_SESSION_STATE || path.join(WORKER_ROOT, "storage-state.json");
const DEFAULT_DOWNLOADS =
  process.env.DIMASAVE_DEFAULT_DOWNLOADS || (await defaultDownloads(APP_SUPPORT));

async function ensureDirectories() {
  await Promise.all(
    [APP_SUPPORT, WORKER_ROOT, BROWSER_PROFILE, PLAYWRIGHT_BROWSERS, MANIFESTS_DIRECTORY, DEFAULT_DOWNLOADS].map(
      (entry) => fs.mkdir(entry, { recursive: true }),
    ),
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
    headless: false,
    viewport: { width: 1440, height: 940 },
    acceptDownloads: true,
  };
  if (headless) {
    options.args = ["--window-position=-32000,-32000", "--window-size=1440,940"];
  }
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
    `node=${process.execPath}`,
  ];

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
      },
      logs,
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
      },
      logs,
    });
  }
}

async function loginCommand() {
  await ensureDirectories();
  const logs = [];
  let session = null;

  try {
    session = await launchContext(false);
    const page = await session.firstPage();
    await page.goto("https://www.instagram.com/accounts/login/", { waitUntil: "domcontentloaded" });
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
    if (session) {
      await session.close();
    }
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
    await page.goto("https://www.instagram.com/", { waitUntil: "domcontentloaded" });
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
    if (session) {
      await session.close();
    }
  }
}

function sanitizeFilename(value) {
  let cleaned = value.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").replace(/[ .]+$/g, "");
  const reserved = new Set([
    "CON", "PRN", "AUX", "NUL",
    "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
    "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
  ]);
  if (reserved.has(cleaned.toUpperCase())) {
    cleaned = `_${cleaned}`;
  }
  return cleaned || "story";
}

function extractUsername(value) {
  try {
    const parsed = new URL(value);
    const parts = parsed.pathname.split("/").filter(Boolean);
    if (parts[0] === "stories" && parts.length > 1) {
      return sanitizeFilename(parts[1]);
    }
    if (parts.length > 0) {
      return sanitizeFilename(parts[0]);
    }
  } catch {}
  return sanitizeFilename(value.trim().replace(/^@/, ""));
}

function normalizeMediaUrl(url) {
  const parsed = new URL(url);
  parsed.searchParams.delete("bytestart");
  parsed.searchParams.delete("byteend");
  return parsed.toString();
}

function isStoryMediaUrl(url) {
  const lowered = url.toLowerCase();
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  const host = parsed.hostname.toLowerCase();
  const pathName = parsed.pathname.toLowerCase();
  const query = parsed.search.toLowerCase();

  if (!lowered.startsWith("http")) return false;
  if (host.includes("static.cdninstagram.com")) return false;
  if (pathName.includes("rsrc.php")) return false;
  if (lowered.includes("profile_pic") || lowered.includes("profilepic")) return false;

  const excluded = ["s100x100", "s150x150", "s240x240", "s320x320", "dst-jpg_s", "ig_app_icon", "favicon", "avatar"];
  if (excluded.some((token) => lowered.includes(token) || query.includes(token))) return false;
  const allowedHosts = ["scontent", "fbcdn", "cdninstagram", "video"];
  if (!allowedHosts.some((token) => host.includes(token))) return false;
  return true;
}

function mediaVariantTag(url) {
  try {
    const parsed = new URL(url);
    const encoded = parsed.searchParams.get("efg");
    if (!encoded) return "";
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    return typeof payload.vencode_tag === "string" ? payload.vencode_tag.toLowerCase() : "";
  } catch {
    return "";
  }
}

function isAudioOnlyVariant(url) {
  const tag = mediaVariantTag(url);
  return tag.includes("_audio") || tag.endsWith("audio");
}

function shouldSkipMediaVariant(url) {
  const tag = mediaVariantTag(url);
  const lowered = url.toLowerCase();
  if (!tag) {
    return lowered.includes("clips") || lowered.includes("reel");
  }
  if (isAudioOnlyVariant(url)) return true;
  return tag.includes("clips") || tag.includes("reel");
}

function mediaVariantScore(url, mediaType) {
  const tag = mediaVariantTag(url);
  const lowered = url.toLowerCase();
  let score = 0;
  if (mediaType === "image") {
    if (tag.includes("story")) score += 50;
    if (tag.includes("profile_pic")) score -= 100;
    return score;
  }
  if (tag.includes("story")) score += 100;
  if (tag.includes("xpv_progressive") || tag.includes("progressive")) score += 180;
  if (isAudioOnlyVariant(url)) score -= 500;
  if (tag.includes("clips") || tag.includes("reel")) score -= 200;
  if (tag.includes("audio") || tag.includes("aac") || tag.includes("haac")) score -= 30;
  if (tag.includes("avc") || tag.includes("h264")) score += 120;
  if (tag.includes("hevc") || tag.includes("h265")) score += 60;
  if (tag.includes("vp9-basic")) score -= 180;
  if (tag.includes("vp9")) score -= 120;
  if (tag.includes("dash_ln")) score -= 30;
  if (tag.includes("dash") && !tag.includes("audio")) score -= 20;
  if (lowered.includes("dashinit") || lowered.includes("video_dashinit")) score -= 240;
  if (lowered.includes("_nc_vs=") || lowered.includes("vs=")) score += 70;
  return score;
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
  let bestUrl = null;
  let bestScore = -1e9;
  for (const candidate of variants) {
    const url = candidate.url;
    if (typeof url !== "string" || !isStoryMediaUrl(url) || shouldSkipMediaVariant(url)) continue;
    const [width, height] = candidateDimensions(candidate, item);
    if (!passesStoryShapeGate(url, width, height)) continue;
    let score = mediaVariantScore(url, "video") + Math.floor((width * height) / 5000) + storyRatioBonus(width, height);
    if (candidate.type === 101) score += 25;
    if (candidate.type === 102) score += 10;
    if (score > bestScore) {
      bestScore = score;
      bestUrl = normalizeMediaUrl(url);
    }
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
  const response = await browserContext.request.get(sourceUrl, {
    headers,
    timeout: 60_000,
    failOnStatusCode: true,
    ignoreHTTPSErrors: true,
    maxRetries: 1,
  });
  return {
    body: await response.body(),
    contentType: response.headers()["content-type"] || null,
  };
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
  const { body, contentType } = await fetchMediaBytes(normalizedUrl, browserContext, refererUrl);
  if (mediaType === "video" && looksLikeFragmentedMp4(body)) {
    throw new Error("Скачан только фрагмент видео вместо полного файла.");
  }
  const suffix = extensionFor(contentType, normalizedUrl, mediaType);
  const filename = `${sanitizeFilename(username)}-${String(index).padStart(3, "0")}${suffix}`;
  const localPath = path.join(destinationDir, filename);
  await fs.writeFile(localPath, body);
  return { localPath, finalSourceUrl: normalizedUrl };
}

async function writeManifest(itemId, pageUrl, sourceUrl, localPath, mediaType, createdAt) {
  const fileHash = createHash("sha256").update(await fs.readFile(localPath)).digest("hex");
  const payload = {
    id: itemId,
    createdAt,
    pageURL: pageUrl,
    sourceURL: sourceUrl,
    localPath,
    mediaType,
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

async function persistStoryItems(resolvedItems, destinationDir, username, browserContext) {
  const logs = [];
  const items = [];
  const seenSources = new Set();
  const seenHashes = new Set();
  let nextIndexValue = await nextStoryIndex(destinationDir, username);

  for (const resolved of resolvedItems) {
    const normalizedSource = normalizeMediaUrl(resolved.sourceUrl);
    if (seenSources.has(normalizedSource)) {
      logs.push(`skipped_current_source=${normalizedSource}`);
      continue;
    }
    const { localPath, finalSourceUrl } = await downloadMedia(
      normalizedSource,
      destinationDir,
      resolved.mediaType,
      username,
      nextIndexValue,
      browserContext,
      resolved.pageUrl,
    );
    const fileHash = createHash("sha256").update(await fs.readFile(localPath)).digest("hex");
    if (seenHashes.has(fileHash)) {
      await fs.rm(localPath, { force: true });
      seenSources.add(finalSourceUrl);
      logs.push(`skipped_current_hash=${fileHash}`);
      continue;
    }
    const itemId = randomUUID().replace(/-/g, "");
    const createdAt = new Date().toISOString();
    const manifestPath = await writeManifest(itemId, resolved.pageUrl, finalSourceUrl, localPath, resolved.mediaType, createdAt);
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
    nextIndexValue += 1;
    logs.push(`saved=${localPath}`);
    logs.push(`manifest=${manifestPath}`);
  }
  return { items, logs };
}

async function collectStorySequence(page, destinationDir, username, jsonPayloads, networkCandidates, metadataCapturedAfter = null, persistMetadataItems = true) {
  const logs = [];
  const resolvedItems = await waitForMetadataStoryItems(page, jsonPayloads, username, logs, 12, metadataCapturedAfter);
  if (resolvedItems.length > 0 && persistMetadataItems) {
    const persisted = await persistStoryItems(resolvedItems, destinationDir, username, page.context());
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
    } else {
      const { localPath, finalSourceUrl } = await downloadMedia(
        normalizedSource,
        destinationDir,
        media.mediaType,
        username,
        nextIndexValue,
        page.context(),
        media.pageUrl,
      );
      const fileHash = createHash("sha256").update(await fs.readFile(localPath)).digest("hex");
      if (seenHashes.has(fileHash)) {
        await fs.rm(localPath, { force: true });
        seenSignatures.add(signature);
        seenSources.add(finalSourceUrl);
        logs.push(`skipped_current_hash=${fileHash}`);
      } else {
        const itemId = randomUUID().replace(/-/g, "");
        const createdAt = new Date().toISOString();
        const manifestPath = await writeManifest(itemId, media.pageUrl, finalSourceUrl, localPath, media.mediaType, createdAt);
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

async function profileCommand(profileUrl, outputDirectory, headless = true) {
  const username = extractUsername(profileUrl);
  if (!username) {
    emit(false, "profile_error", "Не удалось извлечь имя пользователя из ссылки на профиль.");
    return;
  }

  await ensureDirectories();
  const rootDestination = path.resolve(outputDirectory || DEFAULT_DOWNLOADS);
  const destination = path.join(rootDestination, sanitizeFilename(username));
  const logs = [];
  let session = null;

  try {
    session = await launchContext(headless);
    const page = await session.firstPage();
    await prepareBackgroundWindow(session, page, logs);
    const jsonPayloads = installJsonCapture(page, logs);
    const networkCandidates = installNetworkCapture(page, logs);

    const profilePageUrl = `https://www.instagram.com/${username}/`;
    await page.goto(profilePageUrl, { waitUntil: "domcontentloaded" });
    await ensureLoggedIn(page);
    await persistSessionState(page.context(), logs);
    await page.waitForTimeout(1500);
    logs.push(`profile_download_directory=${destination}`);

    const storyCaptureStartedAt = Date.now() / 1000;
    const opened = await clickProfileStoryRing(page, username, logs);
    if (!opened) {
      const fallback = `https://www.instagram.com/stories/${username}/`;
      await page.goto(fallback, { waitUntil: "domcontentloaded" });
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
    );
    logs.push(...result.logs);
    const foundCount = extractFoundCount(result.logs, result.items.length);

    if (result.items.length === 0) {
      emit(false, "download_empty", `Для профиля ${username} не удалось получить активные stories.`, {
        data: { foundCount: String(foundCount), savedCount: "0" },
        logs,
      });
      return;
    }

    emit(true, "download_complete", `Для профиля ${username} сохранено файлов: ${result.items.length}.`, {
      data: { foundCount: String(foundCount), savedCount: String(result.items.length) },
      items: result.items,
      logs,
    });
  } catch (error) {
    emit(false, "download_error", String(error), { logs });
  } finally {
    if (session) await session.close();
  }
}

async function main() {
  try {
    const request = await readRequest();
    const command = request.command;
    const url = request.url;
    const outputDirectory = request.outputDirectory;
    const headless = request.headless ?? true;

    if (command === "environment") {
      await environmentCommand();
    } else if (command === "login") {
      await loginCommand();
    } else if (command === "check_session") {
      await checkSessionCommand(Boolean(headless));
    } else if (command === "download_profile_stories") {
      if (!url) {
        emit(false, "request_error", "Для download_profile_stories нужна ссылка на профиль или имя пользователя.");
        return;
      }
      await profileCommand(url, outputDirectory, Boolean(headless));
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
