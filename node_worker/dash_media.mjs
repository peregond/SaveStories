function decodeXmlEntities(value) {
  return String(value ?? "").replace(
    /&(?:#(\d+)|#x([0-9a-f]+)|amp|quot|apos|lt|gt);/gi,
    (entity, decimal, hexadecimal) => {
      if (decimal !== undefined) {
        const codePoint = Number.parseInt(decimal, 10);
        return Number.isSafeInteger(codePoint) && codePoint <= 0x10ffff
          ? String.fromCodePoint(codePoint)
          : entity;
      }
      if (hexadecimal !== undefined) {
        const codePoint = Number.parseInt(hexadecimal, 16);
        return Number.isSafeInteger(codePoint) && codePoint <= 0x10ffff
          ? String.fromCodePoint(codePoint)
          : entity;
      }
      switch (entity.toLowerCase()) {
        case "&amp;": return "&";
        case "&quot;": return '"';
        case "&apos;": return "'";
        case "&lt;": return "<";
        case "&gt;": return ">";
        default: return entity;
      }
    },
  );
}

function parseXmlAttributes(source) {
  const attributes = {};
  const pattern = /([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
  for (const match of String(source ?? "").matchAll(pattern)) {
    const name = match[1].split(":").at(-1).toLowerCase();
    attributes[name] = decodeXmlEntities(match[2] ?? match[3] ?? "");
  }
  return attributes;
}

function extractBaseUrls(source) {
  const urls = [];
  const pattern = /<(?:[\w.-]+:)?BaseURL\b[^>]*>([\s\S]*?)<\/(?:[\w.-]+:)?BaseURL\s*>/gi;
  for (const match of String(source ?? "").matchAll(pattern)) {
    const rawValue = match[1].trim();
    const cdata = rawValue.match(/^<!\[CDATA\[([\s\S]*?)\]\]>$/i);
    const value = (cdata ? cdata[1] : decodeXmlEntities(rawValue)).trim();
    if (value) urls.push(value);
  }
  return urls;
}

function normalizedBandwidth(value) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 0;
}

function audioCandidate(attributes, adaptationAttributes, url, order) {
  const representationMimeType = (attributes.mimetype || "").toLowerCase();
  const adaptationMimeType = (adaptationAttributes.mimetype || "").toLowerCase();
  const mimeType = representationMimeType || adaptationMimeType;
  const codecs = (attributes.codecs || adaptationAttributes.codecs || "").toLowerCase();
  const adaptationContentType = (adaptationAttributes.contenttype || "").toLowerCase();
  const isAudio =
    adaptationContentType === "audio" ||
    adaptationMimeType.startsWith("audio/") ||
    representationMimeType.startsWith("audio/");
  if (!isAudio) return null;

  const isMp4 = mimeType === "audio/mp4";
  const isAac = /(?:^|[,\s])(?:mp4a(?:\.[\w.-]+)?|aac)(?:[\s,]|$)/i.test(codecs);
  return {
    url,
    bandwidth: normalizedBandwidth(attributes.bandwidth ?? adaptationAttributes.bandwidth),
    preferredFormat: isMp4 && isAac ? 2 : (isAac || isMp4 ? 1 : 0),
    isAac: isAac ? 1 : 0,
    isMp4: isMp4 ? 1 : 0,
    order,
  };
}

function chooseDashAudioUrl(manifest) {
  if (typeof manifest !== "string" || manifest.trim() === "") return null;

  const candidates = [];
  let order = 0;
  const adaptationPattern = /<(?:[\w.-]+:)?AdaptationSet\b([^>]*)>([\s\S]*?)<\/(?:[\w.-]+:)?AdaptationSet\s*>/gi;
  for (const adaptationMatch of manifest.matchAll(adaptationPattern)) {
    const adaptationAttributes = parseXmlAttributes(adaptationMatch[1]);
    const adaptationBody = adaptationMatch[2];
    const candidateCountBeforeRepresentations = candidates.length;
    const representationPattern = /<(?:[\w.-]+:)?Representation\b([^>]*)>([\s\S]*?)<\/(?:[\w.-]+:)?Representation\s*>/gi;
    for (const representationMatch of adaptationBody.matchAll(representationPattern)) {
      const attributes = parseXmlAttributes(representationMatch[1]);
      for (const url of extractBaseUrls(representationMatch[2])) {
        const candidate = audioCandidate(attributes, adaptationAttributes, url, order++);
        if (candidate) candidates.push(candidate);
      }
    }

    if (candidates.length === candidateCountBeforeRepresentations) {
      const adaptationLevelBody = adaptationBody.replace(representationPattern, "");
      for (const url of extractBaseUrls(adaptationLevelBody)) {
        const candidate = audioCandidate({}, adaptationAttributes, url, order++);
        if (candidate) candidates.push(candidate);
      }
    }
  }

  candidates.sort((left, right) =>
    right.preferredFormat - left.preferredFormat ||
    right.isAac - left.isAac ||
    right.isMp4 - left.isMp4 ||
    right.bandwidth - left.bandwidth ||
    left.order - right.order,
  );
  return candidates[0]?.url ?? null;
}

function expectedAudioState(declaredValue, audioSourceUrl = null) {
  if (typeof audioSourceUrl === "string" && audioSourceUrl.trim() !== "") return true;
  if (declaredValue === true || declaredValue === 1 || declaredValue === "1" || declaredValue === "true") return true;
  if (declaredValue === false || declaredValue === 0 || declaredValue === "0" || declaredValue === "false") return false;
  return null;
}

function mediaAudioConfidence(candidate) {
  if (candidate?.audioSourceUrl) return 3;
  if (candidate?.expectsAudio === true) return 2;
  if (candidate?.expectsAudio === false) return 1;
  return 0;
}

function mergeResolvedMediaCandidate(existing, candidate) {
  if (!existing) return candidate;
  if (!candidate) return existing;
  const candidateIsPreferred = mediaAudioConfidence(candidate) >= mediaAudioConfidence(existing);
  const preferred = candidateIsPreferred ? candidate : existing;
  const fallback = candidateIsPreferred ? existing : candidate;
  const audioSourceUrl = preferred.audioSourceUrl || fallback.audioSourceUrl || null;
  const expectsAudio = audioSourceUrl
    ? true
    : preferred.expectsAudio ?? fallback.expectsAudio ?? null;
  return { ...fallback, ...preferred, audioSourceUrl, expectsAudio };
}

function storyIdFromUrl(value) {
  if (typeof value !== "string" || value.trim() === "") return null;
  let parsed;
  try {
    parsed = new URL(value, "https://www.instagram.com/");
  } catch {
    return null;
  }

  const parts = parsed.pathname.split("/").filter(Boolean);
  if (parts.length < 3 || parts[0].toLowerCase() !== "stories") return null;
  if (parts[1].toLowerCase() === "highlights") return null;
  return /^\d+$/.test(parts[2]) ? parts[2] : null;
}

function isTrustedInstagramMediaUrl(value) {
  if (typeof value !== "string" || value.trim() === "") return false;
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "https:") return false;
    const hostname = parsed.hostname.toLowerCase();
    return (
      hostname === "instagram.com" ||
      hostname.endsWith(".instagram.com") ||
      hostname === "cdninstagram.com" ||
      hostname.endsWith(".cdninstagram.com") ||
      hostname === "fbcdn.net" ||
      hostname.endsWith(".fbcdn.net")
    );
  } catch {
    return false;
  }
}

export {
  chooseDashAudioUrl,
  decodeXmlEntities,
  expectedAudioState,
  isTrustedInstagramMediaUrl,
  mergeResolvedMediaCandidate,
  storyIdFromUrl,
};
