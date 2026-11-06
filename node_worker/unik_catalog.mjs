// Каталог раздела «Уникализатор»: пресеты формата, стили вариаций, метки 18+ по странам и правила именования.
// Перенесено из сервиса n1.unikalizator (packages/presets, apps/web/src/lib/app-config.ts и app-helpers.ts).
// Один источник данных для интерфейсов Windows и macOS: они получают каталог командой unik_status.
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const AGE_MARKS_DIRECTORY = path.join(HERE, "unik_assets", "age-marks");

const defaultOutput = { container: "mp4", videoCodec: "h264", audioCodec: "aac" };
const bars = (width, height, fit = "cover") => ({ width, height, fit, backgroundStyle: "bars", backgroundColor: "#111111" });

export const FORMAT_PRESETS = [
  { id: "meta-story", name: "Instagram Stories 9x16", description: "Вертикальный формат для Stories и Reels.", output: defaultOutput, resize: bars(1080, 1920), fps: 30, bitrate: "4M" },
  { id: "meta-square", name: "Instagram/Facebook Post 1x1", description: "Квадрат для ленты Meta.", output: defaultOutput, resize: bars(1080, 1080), fps: 30, bitrate: "5M" },
  { id: "meta-feed-4x5", name: "Meta 4x5 1080x1350", description: "Вертикальная лента Meta.", output: defaultOutput, resize: bars(1080, 1350), fps: 30, bitrate: "6M" },
  { id: "facebook-feed-4x5", name: "Facebook 4x5 1080x1350", description: "Лента Facebook для мобильных.", output: defaultOutput, resize: bars(1080, 1350), fps: 30, bitrate: "6M" },
  { id: "google-ads-landscape", name: "Google Ads 1.91:1 1200x628", description: "Горизонтальный формат для Google Ads.", output: defaultOutput, resize: bars(1200, 628, "contain"), fps: 30, bitrate: "5M" },
];

export const STYLE_PRESETS = [
  { id: "clean", label: "Чистый", hint: "Без доп. стиля", hueShift: 0, saturation: 1, sharpness: 0, speedOffsetMs: 0 },
  { id: "soft", label: "Мягкий", hint: "Теплее и мягче", hueShift: 8, saturation: 1.18, sharpness: 0.28, speedOffsetMs: 0 },
  { id: "cinematic", label: "Кино", hint: "Глубже, темнее, спокойнее", hueShift: -14, saturation: 0.82, sharpness: 0.48, speedOffsetMs: 900 },
  { id: "bright", label: "Яркий", hint: "Сочнее и быстрее", hueShift: 16, saturation: 1.35, sharpness: 0.3, speedOffsetMs: -500 },
  { id: "warm", label: "Тёплый", hint: "Выраженные тёплые тона", hueShift: 14, saturation: 1.22, sharpness: 0.22, speedOffsetMs: 0 },
  { id: "cold", label: "Холодный", hint: "Холоднее и строже", hueShift: -18, saturation: 0.84, sharpness: 0.32, speedOffsetMs: 250 },
  { id: "crisp", label: "Чёткий", hint: "Резче и контрастнее", hueShift: 3, saturation: 1.14, sharpness: 0.82, speedOffsetMs: -250 },
  { id: "calm", label: "Спокойный", hint: "Приглушённый и медленный", hueShift: -8, saturation: 0.76, sharpness: 0.12, speedOffsetMs: 1200 },
];

export const FPS_OPTIONS = [25, 30, 50, 60];
export const VARIATION_OPTIONS = [1, 2, 3, 5];
export const BITRATE_OPTIONS = [
  { value: "1.5M", label: "Низкое", hint: "Легче файл" },
  { value: "2M", label: "Стандарт", hint: "По умолчанию" },
  { value: "3M", label: "Высокое", hint: "Лучше качество" },
  { value: "4M", label: "Очень высокое", hint: "Больше деталей" },
  { value: "6M", label: "Максимум", hint: "Мастер-режим" },
];

export const AGE_MARK_GEOS = [
  { id: "au-australia", name: "AU - Australia", code: "au" },
  { id: "de-germany", name: "DE - Germany", code: "de" },
  { id: "nl-netherlands", name: "NL - Netherlands", code: "nl" },
  { id: "nda-amonbet", name: "NDA - AmonBet", code: "nda" },
  { id: "da-luckyhunter", name: "DA - LuckyHunter", code: "da" },
  { id: "gb-great-britain", name: "GB - Great Britain", code: "gb" },
  { id: "ca-canada", name: "CA - Canada", code: "ca" },
  { id: "fr-france", name: "FR - France", code: "fr" },
  { id: "es-spain", name: "ES - Spain", code: "es" },
];

// В шаблонах сервиса у двух пар файлов названия «top» и «bottom» перепутаны с тем, где реально нарисована плашка:
// de_portrait_* и gb_portrait_* (9:16). Здесь положение считается по тому, где плашка видна на кадре.
const SWAPPED_TEMPLATES = new Set(["de_portrait", "gb_portrait"]);

function templateFile(directory, code, shape, position) {
  const swapped = SWAPPED_TEMPLATES.has(`${code}_${shape}`);
  const side = (position === "top") !== swapped ? "top" : "bottom";
  return path.join(directory, `${code}_${shape}_${side}.png`);
}

/** Файлы плашки 18+ для страны и расположения плашки на кадре («top» — сверху, «bottom» — снизу). */
export function ageMarkFiles(geoId, position = "bottom", directory = AGE_MARKS_DIRECTORY) {
  const geo = AGE_MARK_GEOS.find((g) => g.id === geoId);
  if (!geo) return null;
  const where = position === "top" ? "top" : "bottom";
  return {
    portraitFilePath: templateFile(directory, geo.code, "portrait", where),
    squareFilePath: templateFile(directory, geo.code, "square", where),
    fourByFiveFilePath: templateFile(directory, geo.code, "four_by_five", where),
  };
}

export function catalog() {
  return {
    formatPresets: FORMAT_PRESETS,
    stylePresets: STYLE_PRESETS,
    fpsOptions: FPS_OPTIONS,
    variationOptions: VARIATION_OPTIONS,
    bitrateOptions: BITRATE_OPTIONS,
    ageMarkGeos: AGE_MARK_GEOS.map(({ id, name }) => ({ id, name })),
  };
}

// ---------------------------------------------------------------- имена

export function slugifyToken(value) {
  return String(value ?? "").trim().replace(/[^a-zA-Z0-9]+/g, "").replace(/^_+|_+$/g, "");
}

export function stripExtension(fileName) {
  const dot = fileName.lastIndexOf(".");
  return dot <= 0 ? fileName : fileName.slice(0, dot);
}

export function createRandomNameToken(length = 8, random = Math.random) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  return Array.from({ length }, () => alphabet[Math.floor(random() * alphabet.length)]).join("");
}

export function buildSizeToken(width, height) {
  if (!width || !height) return "custom";
  const ratio = width / height;
  if (Math.abs(ratio - 9 / 16) < 0.02) return "9x16";
  if (Math.abs(ratio - 1) < 0.02) return "1x1";
  if (Math.abs(ratio - 4 / 5) < 0.02) return "4x5";
  if (Math.abs(ratio - 1.91) < 0.03) return "191x1";
  if (Math.abs(ratio - 16 / 9) < 0.02) return "16x9";
  return `${width}x${height}`;
}

/** Запрещённые в именах Windows/macOS символы заменяются, длина ограничивается. */
export function safeFileStem(value, fallback = "result") {
  const cleaned = String(value ?? "").replace(/[\\/:*?"<>|\x00-\x1f]+/g, "_").replace(/^[ .]+|[ .]+$/g, "").slice(0, 150);
  return cleaned || fallback;
}
