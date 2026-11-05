// Разбор ссылок. Правила повторяют windows_app/savestories_windows/common_utils.py.

export function normalizeProfileLink(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return trimmed;
  if (trimmed.includes("instagram.com")) return trimmed;
  const username = trimmed
    .replace(/^[@/\s]+|[@/\s]+$/g, "")
    .replace(/^[*,;:!?/\\]+|[*,;:!?/\\]+$/g, "")
    .replace(/[^A-Za-z0-9._]/g, "");
  return `https://www.instagram.com/${username}/`;
}

export function parseBatchLinks(raw: string): string[] {
  return raw
    .split(/[\s,;]+/)
    .map((part) => part.trim())
    .filter(Boolean)
    .map(normalizeProfileLink);
}

export function normalizeReelLink(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed || !trimmed.includes("instagram.com")) return "";
  let url: URL;
  try {
    url = new URL(trimmed.startsWith("http") ? trimmed : `https://${trimmed}`);
  } catch {
    return "";
  }
  const parts = url.pathname.split("/").filter(Boolean);
  if (parts.length < 2) return "";
  const kind = parts[0].toLowerCase();
  if (!["reel", "reels", "p"].includes(kind)) return "";
  return `${url.protocol}//${url.host}/${kind}/${parts[1]}/${url.search}`;
}

export function parseReelLinks(raw: string): string[] {
  const links: string[] = [];
  for (const line of raw.split(/\r?\n/)) {
    for (const part of line.split(",")) {
      const value = normalizeReelLink(part);
      if (value) links.push(value);
    }
  }
  return links;
}

/** Имя профиля для показа: «https://www.instagram.com/dian.vegas1/» → «dian.vegas1». */
export function profileName(url: string): string {
  const parts = url.replace(/[?#].*$/, "").split("/").filter(Boolean);
  return parts[parts.length - 1] || url;
}

export function pluralProfiles(n: number): string {
  const m = n % 100;
  const d = n % 10;
  if (m > 10 && m < 15) return "профилей";
  if (d === 1) return "профиль";
  if (d >= 2 && d <= 4) return "профиля";
  return "профилей";
}
