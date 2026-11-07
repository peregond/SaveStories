import { t } from "./i18n";
// Разбор ссылок. Правила повторяют ProfileInputParser.cs из выпускаемого WinUI-клиента.

const TOKEN_TRIM = /^[<>"'`()[\]{},;]+|[<>"'`()[\]{},;]+$/g;
const NOT_USERNAME = /[^A-Za-z0-9._]/g;
const SKIPPED_FIRST_SEGMENTS = new Set(["reel", "reels", "p", "tv", "explore", "accounts", "direct"]);

function cleanToken(raw: string | null | undefined): string {
  return (raw ?? "").trim().replace(TOKEN_TRIM, "");
}

function cleanUsername(raw: string): string {
  return cleanToken(raw)
    .replace(/^@+/, "")
    .replace(/^[*,;:!?/\\]+|[*,;:!?/\\]+$/g, "")
    .replace(NOT_USERNAME, "");
}

function normalizeInstagramUrl(value: string): string | null {
  const candidate = /^https?:\/\//i.test(value) ? value : `https://${value}`;
  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    return null;
  }
  const host = url.hostname.toLowerCase();
  if (!(url.protocol === "http:" || url.protocol === "https:") || !(host === "instagram.com" || host.endsWith(".instagram.com"))) {
    return null;
  }
  const segments = url.pathname.split("/").map((s) => s.trim()).filter(Boolean);
  if (segments.length === 0) return null;
  let first = segments[0];
  if (first.toLowerCase() === "stories") {
    if (segments.length < 2 || segments[1].toLowerCase() === "highlights") return null;
    first = segments[1];
  } else if (SKIPPED_FIRST_SEGMENTS.has(first.toLowerCase())) {
    return null;
  }
  const username = cleanUsername(first);
  return username ? `https://www.instagram.com/${username}/` : null;
}

export function normalizeProfile(raw: string | null | undefined): string | null {
  const value = cleanToken(raw);
  if (!value) return null;
  if (value.toLowerCase().includes("instagram.com")) return normalizeInstagramUrl(value);
  const username = cleanUsername(value);
  return username ? `https://www.instagram.com/${username}/` : null;
}

/** Профили из произвольного текста: пробелы, запятые и `;` разделяют, дубликаты (без учёта регистра) убираются. */
export function parseProfiles(input: string | null | undefined): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const token of (input ?? "").split(/[\s,;]+/)) {
    const normalized = normalizeProfile(token);
    if (!normalized || seen.has(normalized.toLowerCase())) continue;
    seen.add(normalized.toLowerCase());
    out.push(normalized);
  }
  return out;
}

/** Ссылки Reels: по одной на строку, как в WinUI (без проверки формата), без дубликатов. */
export function parseReelLines(input: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const line of input.split("\n")) {
    const value = line.trim();
    if (value && !seen.has(value.toLowerCase())) {
      seen.add(value.toLowerCase());
      out.push(value);
    }
  }
  return out;
}

/** Имя профиля для показа: «https://www.instagram.com/dian.vegas1/» → «dian.vegas1». */
export function profileName(url: string): string {
  const parts = url.replace(/[?#].*$/, "").split("/").filter(Boolean);
  return parts[parts.length - 1] || url;
}

/** Имя профиля из строки прогресса воркера: `batch_slot_1_done=https://…/name/ :: подробности`. */
export function profileFromProgress(line: string): string {
  const eq = line.indexOf("=");
  if (eq < 0 || eq >= line.length - 1) return line;
  const value = line.slice(eq + 1).split(" :: ")[0].trim();
  try {
    const first = new URL(value).pathname.split("/").filter(Boolean)[0];
    if (first) return first;
  } catch { /* не URL — вернём как есть */ }
  return value;
}

/** Итоги профиля из строки `batch_slot_N_profile=имя status=… found=X saved=Y …`; для остальных строк — null. */
export function profileCounts(line: string): { found: number; saved: number } | null {
  if (!/^batch_slot_\d+_profile=/.test(line)) return null;
  const num = (key: string) => Number(new RegExp(`(?:^|\\s)${key}=(\\d+)`).exec(line)?.[1] ?? 0);
  return { found: num("found"), saved: num("saved") };
}

export function progressDetail(line: string): string {
  const i = line.indexOf(" :: ");
  return i < 0 ? "" : line.slice(i + 4).trim();
}

export function pluralProfiles(n: number): string {
  const m = n % 100;
  const d = n % 10;
  if (m > 10 && m < 15) return t("профилей");
  if (d === 1) return t("профиль");
  if (d >= 2 && d <= 4) return t("профиля");
  return t("профилей");
}

/** Рабочие часы темы по времени суток: день 7–19 — светлая, иначе тёмная (TimeOfDayThemeService). */
export function themeForHour(hour: number): "light" | "dark" {
  return hour >= 7 && hour < 19 ? "light" : "dark";
}

/** Таймаут воркера в секундах (StoriesPage.BuildWorkerTimeout): пакет — 20 мин + 1,5/3 мин на профиль, 30…720. */
export function workerTimeoutSecs(command: string, profileCount: number, headless: boolean): number {
  if (command !== "download_profile_batch") return 20 * 60;
  const minutes = Math.min(720, Math.max(30, 20 + Math.max(1, profileCount) * (headless ? 1.5 : 3)));
  return Math.round(minutes * 60);
}

/** Сегодняшняя ли это дата (локальная) — для «Notion обновляется не чаще раза в день». */
export function isToday(iso: string, now = new Date()): boolean {
  if (!iso) return false;
  const d = new Date(iso);
  return !Number.isNaN(d.getTime()) && d.toDateString() === now.toDateString();
}
