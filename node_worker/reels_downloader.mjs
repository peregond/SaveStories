import fs from "node:fs/promises";
import path from "node:path";
import { createHash, randomUUID } from "node:crypto";

import {
  isAudioOnlyVariant,
  mediaVariantTag,
  normalizeMediaUrl,
  sanitizeFilename,
} from "./media_utils.mjs";

function splitReelInputs(rawUrls) {
  const values = [];
  for (const entry of rawUrls) {
    for (const line of String(entry || "").split(/\r?\n/)) {
      for (const part of line.split(",")) {
        const value = part.trim();
        if (value) values.push(value);
      }
    }
  }
  return values;
}

function normalizeReelUrl(raw) {
  const trimmed = String(raw || "").trim();
  if (!trimmed) return "";
  let parsed;
  try {
    parsed = new URL(trimmed);
  } catch {
    return "";
  }
  parsed.hash = "";
  const parts = parsed.pathname.split("/").filter(Boolean);
  if (parts.length >= 2 && ["reel", "reels", "p"].includes(parts[0].toLowerCase())) {
    parsed.pathname = `/${parts[0].toLowerCase()}/${parts[1]}/`;
  }
  return parsed.toString();
}

function extractReelShortcode(value) {
  try {
    const parsed = new URL(value);
    const parts = parsed.pathname.split("/").filter(Boolean);
    if (parts.length >= 2 && ["reel", "reels", "p"].includes(parts[0].toLowerCase())) {
      return sanitizeFilename(parts[1]);
    }
  } catch {}
  return "";
}

function isInstagramMediaUrl(url) {
  const lowered = String(url || "").toLowerCase();
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
  if (lowered.includes("avatar") || lowered.includes("favicon")) return false;
  const excluded = ["s100x100", "s150x150", "s240x240", "s320x320", "dst-jpg_s", "ig_app_icon"];
  if (excluded.some((token) => lowered.includes(token) || query.includes(token))) return false;
  const allowedHosts = ["scontent", "fbcdn", "cdninstagram", "video"];
  return allowedHosts.some((token) => host.includes(token));
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

function reelVariantScore(url, mediaType, width, height) {
  const tag = mediaVariantTag(url);
  const lowered = url.toLowerCase();
  let score = 0;
  if (mediaType === "image") {
    if (tag.includes("clips") || tag.includes("reel")) score += 120;
    if (tag.includes("story")) score -= 220;
    return score + Math.floor((Math.max(width, 1) * Math.max(height, 1)) / 6000);
  }

  if (tag.includes("clips") || tag.includes("reel")) score += 180;
  if (tag.includes("story")) score -= 260;
  if (tag.includes("xpv_progressive") || tag.includes("progressive")) score += 180;
  if (tag.includes("avc") || tag.includes("h264")) score += 120;
  if (tag.includes("hevc") || tag.includes("h265")) score += 40;
  if (tag.includes("dash_vp9-basic") || tag.includes("vp9-basic")) score -= 220;
  if (tag.includes("vp9")) score -= 110;
  if (lowered.includes("dashinit") || lowered.includes("video_dashinit")) score -= 240;
  if (lowered.includes("_nc_vs=") || lowered.includes("vs=")) score += 50;
  return score + Math.floor((Math.max(width, 1) * Math.max(height, 1)) / 6000);
}

function shouldSkipReelVariant(url) {
  const tag = mediaVariantTag(url);
  if (isAudioOnlyVariant(url)) return true;
  if (tag.includes("story")) return true;
  return tag.includes("dash_vp9-basic") || tag.includes("vp9-basic");
}

function chooseBestReelImageUrl(item) {
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
    if (typeof url !== "string" || !isInstagramMediaUrl(url)) continue;
    const [width, height] = candidateDimensions(candidate, item);
    const score = reelVariantScore(url, "image", width, height);
    if (score > bestScore) {
      bestScore = score;
      bestUrl = normalizeMediaUrl(url);
    }
  }
  return bestUrl;
}

function chooseBestReelVideoUrl(item) {
  const variants = Array.isArray(item.video_versions) ? item.video_versions : [];
  const preferredUrls = [];
  let bestUrl = null;
  let bestScore = -1e9;

  for (const candidate of variants) {
    if (!candidate || typeof candidate !== "object") continue;
    const url = candidate.url;
    if (typeof url !== "string" || !isInstagramMediaUrl(url) || shouldSkipReelVariant(url)) continue;
    const [width, height] = candidateDimensions(candidate, item);
    const normalizedUrl = normalizeMediaUrl(url);
    let score = reelVariantScore(url, "video", width, height);
    if (candidate.type === 101) score += 25;
    if (candidate.type === 102) score += 10;
    const tag = mediaVariantTag(url);
    const lowered = url.toLowerCase();
    if (tag.includes("xpv_progressive") || tag.includes("progressive") || tag.includes("avc") || tag.includes("h264")) {
      preferredUrls.push([score + 30, normalizedUrl]);
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
      return sanitizeFilename(value.username);
    }
  }
  return "";
}

function extractItemShortcode(item) {
  for (const key of ["code", "shortcode"]) {
    const value = item[key];
    if (typeof value === "string" && value.trim()) {
      return sanitizeFilename(value.trim());
    }
  }
  return "";
}

function resolveReelItemFromDict(item, expectedShortcode) {
  const hasMedia =
    Array.isArray(item.video_versions) ||
    (item.image_versions2 && typeof item.image_versions2 === "object") ||
    Array.isArray(item.display_resources);
  if (!hasMedia) return null;

  const shortcode = extractItemShortcode(item) || expectedShortcode;
  if (!shortcode) return null;
  if (expectedShortcode && shortcode !== sanitizeFilename(expectedShortcode)) return null;

  const username = extractItemUsername(item) || shortcode;
  const itemId = item.id ?? item.pk ?? shortcode;
  const itemIdString = String(itemId);
  const mediaType = Array.isArray(item.video_versions) ? "video" : "image";
  const sourceUrl = mediaType === "video" ? chooseBestReelVideoUrl(item) : chooseBestReelImageUrl(item);
  if (!sourceUrl) return null;

  const pageUrl = `https://www.instagram.com/reel/${shortcode}/`;
  const takenAt = Number(item.taken_at || 0);
  return {
    itemId: itemIdString,
    username: sanitizeFilename(username || shortcode),
    shortcode,
    pageUrl,
    sourceUrl,
    mediaType,
    takenAt,
  };
}

function walkReelItems(node, expectedShortcode, seenIds, out) {
  if (Array.isArray(node)) {
    for (const value of node) walkReelItems(value, expectedShortcode, seenIds, out);
    return;
  }
  if (!node || typeof node !== "object") return;

  const resolved = resolveReelItemFromDict(node, expectedShortcode);
  if (resolved && !seenIds.has(resolved.itemId)) {
    seenIds.add(resolved.itemId);
    out.push(resolved);
  }

  for (const value of Object.values(node)) {
    walkReelItems(value, expectedShortcode, seenIds, out);
  }
}

function responseUrlLikelyReel(url) {
  const lowered = String(url || "").toLowerCase();
  return lowered.includes("/reel/") || lowered.includes("/clips/") || lowered.includes("clips") || lowered.includes("reel");
}

function resolveReelItemsFromPayloads(payloads, expectedShortcode, capturedAfter = null) {
  const filteredPayloads = [];
  const preferredPayloads = [];
  for (const entry of payloads) {
    const capturedAt = entry.captured_at;
    if (capturedAfter !== null && typeof capturedAt === "number" && capturedAt < capturedAfter) continue;
    filteredPayloads.push(entry);
    if (typeof entry.url === "string" && responseUrlLikelyReel(entry.url)) {
      preferredPayloads.push(entry);
    }
  }

  const source = preferredPayloads.length > 0 ? preferredPayloads : filteredPayloads;
  const seenIds = new Set();
  const resolved = [];
  for (const entry of source) {
    walkReelItems(entry.payload, expectedShortcode, seenIds, resolved);
  }
  resolved.sort((a, b) => (b.takenAt || 0) - (a.takenAt || 0));
  return resolved;
}

async function waitForMetadataReelItems(page, payloads, expectedShortcode, logs, timeoutSeconds = 10, capturedAfter = null) {
  const deadline = Date.now() + timeoutSeconds * 1000;
  let best = [];
  while (Date.now() < deadline) {
    const resolved = resolveReelItemsFromPayloads(payloads, expectedShortcode, capturedAfter);
    if (resolved.length > 0) {
      best = resolved;
      break;
    }
    await page.waitForTimeout(500);
  }
  if (best.length > 0) logs.push(`metadata_reel_items=${best.length}`);
  return best;
}

function extractUsernameFromTitle(title, fallback) {
  const value = String(title || "").trim();
  if (!value) return fallback;
  const byMatch = value.match(/by\s+([A-Za-z0-9._]+)/i);
  if (byMatch?.[1]) return sanitizeFilename(byMatch[1]);
  const ownerMatch = value.match(/^([A-Za-z0-9._]+)\s+on Instagram/i);
  if (ownerMatch?.[1]) return sanitizeFilename(ownerMatch[1]);
  return fallback;
}

async function extractReelFallbackFromDom(page, expectedShortcode, logs) {
  const candidate = await page.evaluate(() => {
    const video = document.querySelector("video");
    const imageMeta = document.querySelector('meta[property="og:image"]')?.getAttribute("content") || "";
    const videoMeta = document.querySelector('meta[property="og:video"]')?.getAttribute("content") || "";
    const canonical = document.querySelector('link[rel="canonical"]')?.getAttribute("href") || window.location.href;
    const title =
      document.querySelector('meta[property="og:title"]')?.getAttribute("content") ||
      document.querySelector("title")?.textContent ||
      "";
    return {
      videoSrc: video?.currentSrc || video?.src || "",
      imageSrc: imageMeta,
      videoMeta,
      canonical,
      title,
    };
  });

  const sourceUrl = candidate.videoSrc || candidate.videoMeta || candidate.imageSrc;
  if (!sourceUrl) return null;

  const shortcode = extractReelShortcode(candidate.canonical || page.url()) || expectedShortcode;
  if (!shortcode) return null;

  const username = extractUsernameFromTitle(candidate.title, shortcode);
  const mediaType = candidate.videoSrc || candidate.videoMeta ? "video" : "image";
  logs.push("reel_fallback=dom");

  return {
    itemId: shortcode,
    username,
    shortcode,
    pageUrl: candidate.canonical || page.url(),
    sourceUrl: normalizeMediaUrl(sourceUrl),
    mediaType,
    takenAt: 0,
  };
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

async function nextReelIndex(destinationDir, username) {
  await fs.mkdir(destinationDir, { recursive: true });
  const prefix = `${sanitizeFilename(username)}-reels-`;
  let highest = 0;
  const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  for (const entry of await fs.readdir(destinationDir)) {
    const match = entry.match(new RegExp(`^${escaped}(\\d+)`));
    if (!match) continue;
    highest = Math.max(highest, Number(match[1]));
  }
  return highest + 1;
}

async function downloadReelMedia(sourceUrl, destinationDir, mediaType, username, index, browserContext, refererUrl = null) {
  await fs.mkdir(destinationDir, { recursive: true });
  const normalizedUrl = normalizeMediaUrl(sourceUrl);
  const { body, contentType } = await fetchMediaBytes(normalizedUrl, browserContext, refererUrl);
  if (mediaType === "video" && looksLikeFragmentedMp4(body)) {
    throw new Error("Скачан только фрагмент видео из Reels вместо полного файла.");
  }
  const suffix = extensionFor(contentType, normalizedUrl, mediaType);
  const filename = `${sanitizeFilename(username)}-reels-${String(index).padStart(3, "0")}${suffix}`;
  const localPath = path.join(destinationDir, filename);
  await fs.writeFile(localPath, body);
  return { localPath, finalSourceUrl: normalizedUrl };
}

async function writeManifest(manifestsDirectory, itemId, pageUrl, sourceUrl, localPath, mediaType, createdAt) {
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
  const manifestPath = path.join(manifestsDirectory, `${itemId}.json`);
  await fs.writeFile(manifestPath, JSON.stringify(payload, null, 2), "utf8");
  return manifestPath;
}

async function persistResolvedReel(resolved, destinationDir, browserContext, manifestsDirectory, logs) {
  const nextIndexValue = await nextReelIndex(destinationDir, resolved.username);
  const { localPath, finalSourceUrl } = await downloadReelMedia(
    resolved.sourceUrl,
    destinationDir,
    resolved.mediaType,
    resolved.username,
    nextIndexValue,
    browserContext,
    resolved.pageUrl,
  );
  const itemId = randomUUID().replace(/-/g, "");
  const createdAt = new Date().toISOString();
  const manifestPath = await writeManifest(
    manifestsDirectory,
    itemId,
    resolved.pageUrl,
    finalSourceUrl,
    localPath,
    resolved.mediaType,
    createdAt,
  );
  logs.push(`saved=${localPath}`);
  logs.push(`manifest=${manifestPath}`);
  return {
    id: itemId,
    sourceURL: finalSourceUrl,
    pageURL: resolved.pageUrl,
    localPath,
    metadataPath: manifestPath,
    mediaType: resolved.mediaType,
    createdAt,
  };
}

async function downloadSingleReelWithPage(page, reelUrl, outputDirectory, deps) {
  const normalizedUrl = normalizeReelUrl(reelUrl);
  const shortcode = extractReelShortcode(normalizedUrl);
  if (!normalizedUrl || !shortcode) {
    return {
      ok: false,
      status: "download_error",
      message: `Некорректная ссылка на Reels: ${reelUrl}`,
      data: { foundCount: "0", savedCount: "0" },
      items: [],
      logs: [],
    };
  }

  const logs = [];
  const rootDestination = path.resolve(outputDirectory || deps.defaultDownloads);

  try {
    const jsonPayloads = deps.installJsonCapture(page, logs);
    const capturedAfter = Date.now() / 1000;
    await page.goto(normalizedUrl, { waitUntil: "domcontentloaded" });
    await deps.ensureLoggedIn(page);
    await deps.persistSessionState(page.context(), logs);
    await page.waitForTimeout(1400);
    logs.push(`opened=${page.url()}`);

    const resolvedItems = await waitForMetadataReelItems(page, jsonPayloads, shortcode, logs, 10, capturedAfter);
    const resolved = resolvedItems[0] || (await extractReelFallbackFromDom(page, shortcode, logs));
    if (!resolved) {
      return {
        ok: false,
        status: "download_empty",
        message: `По ссылке ${normalizedUrl} не удалось получить media из Reels.`,
        data: { foundCount: "0", savedCount: "0" },
        items: [],
        logs,
      };
    }

    const destinationDir = path.join(rootDestination, sanitizeFilename(resolved.username || shortcode));
    logs.push(`reel_download_directory=${destinationDir}`);
    const item = await persistResolvedReel(resolved, destinationDir, page.context(), deps.manifestsDirectory, logs);
    return {
      ok: true,
      status: "download_complete",
      message: `Reels ${resolved.username} сохранён.`,
      data: { foundCount: "1", savedCount: "1" },
      items: [item],
      logs,
    };
  } catch (error) {
    return {
      ok: false,
      status: "download_error",
      message: String(error),
      data: { foundCount: "0", savedCount: "0" },
      items: [],
      logs,
    };
  }
}

async function downloadReelsCommand(reelUrls, outputDirectory, headless, deps) {
  const normalizedUrls = splitReelInputs(reelUrls)
    .map(normalizeReelUrl)
    .filter(Boolean);

  if (normalizedUrls.length === 0) {
    return {
      ok: false,
      status: "request_error",
      message: "Для download_reels_urls нужна хотя бы одна ссылка на Reels.",
      data: { foundCount: "0", savedCount: "0", processedCount: "0", failedCount: "0" },
      items: [],
      logs: [],
    };
  }

  let session = null;
  const allItems = [];
  const allLogs = [];
  let failures = 0;

  try {
    session = await deps.launchContext(headless);

    for (const reelUrl of normalizedUrls) {
      const page = await session.context.newPage();
      try {
        await deps.prepareBackgroundWindow(session, page, []);
        const result = await downloadSingleReelWithPage(page, reelUrl, outputDirectory, deps);
        allLogs.push(`reel_request=${reelUrl}`);
        allLogs.push(...result.logs);
        allItems.push(...result.items);
        if (!result.ok) {
          failures += 1;
          allLogs.push(`reel_failed=${reelUrl} :: ${result.message}`);
        }
      } finally {
        await page.close().catch(() => {});
      }
    }
  } finally {
    if (session) {
      await session.close();
    }
  }

  const processedCount = normalizedUrls.length;
  const savedCount = allItems.length;
  if (savedCount === 0) {
    return {
      ok: false,
      status: "download_empty",
      message: failures === processedCount
        ? "Ни одну ссылку на Reels не удалось выгрузить."
        : "Для указанных ссылок на Reels не найдено данных для скачивания.",
      data: {
        foundCount: "0",
        savedCount: "0",
        processedCount: String(processedCount),
        failedCount: String(failures),
      },
      items: [],
      logs: allLogs,
    };
  }

  return {
    ok: true,
    status: "download_complete",
    message:
      failures > 0
        ? `Обработано ${processedCount} ссылок на Reels. Сохранено файлов: ${savedCount}. Ошибок: ${failures}.`
        : `Обработано ${processedCount} ссылок на Reels. Сохранено файлов: ${savedCount}.`,
    data: {
      foundCount: String(savedCount),
      savedCount: String(savedCount),
      processedCount: String(processedCount),
      failedCount: String(failures),
    },
    items: allItems,
    logs: allLogs,
  };
}

export {
  downloadReelsCommand,
  extractReelShortcode,
  normalizeReelUrl,
  splitReelInputs,
};
