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
  if (tag.includes("dash_vp9-basic") || tag.includes("vp9-basic")) return true;
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
  if (tag.includes("audio") || tag.includes("aac") || tag.includes("haac")) score += 150;
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

export {
  extractUsername,
  isAudioOnlyVariant,
  isStoryMediaUrl,
  mediaVariantScore,
  normalizeMediaUrl,
  sanitizeFilename,
  shouldSkipMediaVariant,
};
