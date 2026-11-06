// Из запроса интерфейса («файлы + настройки») получаем список заданий FFmpeg: вариации, стили, плашка 18+, заставка,
// видео-слой, имена. Перенос логики apps/web/src/lib/job-submission.ts и App.tsx сервиса n1.unikalizator.
import fs from "node:fs";
import path from "node:path";

import {
  FORMAT_PRESETS,
  STYLE_PRESETS,
  ageMarkFiles,
  buildSizeToken,
  createRandomNameToken,
  safeFileStem,
  slugifyToken,
  stripExtension,
} from "./unik_catalog.mjs";
import { buildExecutionPlan } from "./unik_plan.mjs";

export const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp"]);
export const VIDEO_EXTENSIONS = new Set([".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi"]);

export class UnikRequestError extends Error {}

const pick = (list, random) => (list.length ? list[Math.floor(random() * list.length)] : null);

function imageContainerFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return ext === ".png" ? "png" : ext === ".webp" ? "webp" : "jpg";
}

/** Настройки с умолчаниями: недостающие поля заполняются как в онлайн-сервисе. */
export function normalizeOptions(raw = {}) {
  const preset = FORMAT_PRESETS.find((p) => p.id === raw.formatPresetId) ?? FORMAT_PRESETS[0];
  const resize = { ...preset.resize, ...(raw.resize ?? {}) };
  const variations = raw.variations ?? {};
  const count = Math.min(5, Math.max(1, Number(variations.count) || 1));
  const styleIds = Array.from({ length: count }, (_, i) => variations.styleIds?.[i] ?? variations.styleIds?.[0] ?? "clean");
  return {
    formatPresetId: preset.id,
    resize,
    fps: raw.fps === undefined ? preset.fps : raw.fps || undefined,
    bitrate: raw.bitrate ?? "2M",
    variations: { count, styleIds, mode: variations.mode === "preset-per-file" ? "preset-per-file" : "all-variations" },
    manual: { enabled: Boolean(raw.manual?.enabled), hueShift: raw.manual?.hueShift ?? 0, saturation: raw.manual?.saturation ?? 1, sharpness: raw.manual?.sharpness ?? 0, speedOffsetMs: raw.manual?.speedOffsetMs ?? 0 },
    ageMark: { enabled: Boolean(raw.ageMark?.enabled), geoId: raw.ageMark?.geoId ?? "", position: raw.ageMark?.position === "top" ? "top" : "bottom", custom: raw.ageMark?.custom ?? null },
    intro: { enabled: Boolean(raw.intro?.enabled), imagePath: raw.intro?.imagePath ?? "", durationMs: Math.min(10000, Math.max(100, Number(raw.intro?.durationMs) || 500)), random: Boolean(raw.intro?.random), library: raw.intro?.library ?? [] },
    overlay: { enabled: Boolean(raw.overlay?.enabled), videoPath: raw.overlay?.videoPath ?? "", opacity: Math.min(1, Math.max(0.05, Number(raw.overlay?.opacity) || 0.25)), random: Boolean(raw.overlay?.random), library: raw.overlay?.library ?? [] },
    audio: { normalize: raw.audio?.normalize !== false, replacePath: raw.audio?.replacePath ?? "" },
    metadata: { mode: ["strip", "export-date", "custom-date"].includes(raw.metadata?.mode) ? raw.metadata.mode : "strip", customDate: raw.metadata?.customDate ?? "" },
    naming: { mode: raw.naming?.mode === "source-random" ? "source-random" : "structured", geo: raw.naming?.geo ?? "", presetToken: raw.naming?.presetToken ?? "", versionToken: raw.naming?.versionToken || "v1", randomTail: raw.naming?.randomTail ?? "" },
  };
}

/** Проверка настроек до запуска: возвращает список понятных ошибок. */
export function validateOptions(options, { exists = fs.existsSync } = {}) {
  const errors = [];
  const { resize } = options;
  if (!(resize.width > 0 && resize.height > 0) || resize.width > 8192 || resize.height > 8192) errors.push("Размер кадра должен быть от 1 до 8192 пикселей.");
  if (resize.width % 2 || resize.height % 2) errors.push("Ширина и высота видео должны быть чётными.");
  if (resize.backgroundColor && !/^#[0-9A-Fa-f]{6}$/.test(resize.backgroundColor)) errors.push("Цвет фона — шестизначный код вида #111111.");
  if (options.ageMark.enabled && !options.ageMark.geoId && !options.ageMark.custom) errors.push("Для плашки 18+ выберите страну или свой шаблон.");
  if (options.ageMark.enabled && options.ageMark.geoId && !ageMarkFiles(options.ageMark.geoId)) errors.push("Неизвестная страна плашки 18+.");
  if (options.intro.enabled && !options.intro.random && !options.intro.imagePath) errors.push("Для заставки выберите картинку или включите случайную из набора.");
  if (options.intro.enabled && options.intro.random && !options.intro.library.length) errors.push("В наборе заставок нет файлов.");
  if (options.overlay.enabled && !options.overlay.random && !options.overlay.videoPath) errors.push("Для видео-слоя выберите файл или включите случайный из набора.");
  if (options.overlay.enabled && options.overlay.random && !options.overlay.library.length) errors.push("В наборе видео-слоёв нет файлов.");
  if (options.metadata.mode === "custom-date") {
    const date = options.metadata.customDate;
    const parsed = date ? new Date(`${date}T12:00:00Z`) : null;
    if (!date || !parsed || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== date) errors.push("Укажите существующую дату в метаданных (ГГГГ-ММ-ДД).");
  }
  for (const [label, file] of [["Заставка", options.intro.imagePath], ["Видео-слой", options.overlay.videoPath], ["Новый звук", options.audio.replacePath]]) {
    if (file && !exists(file)) errors.push(`${label}: файл не найден (${file}).`);
  }
  return errors;
}

/**
 * @param {object} request  { sources: [{path, kind, durationSeconds}], outputDirectory, options }
 * @returns {Array<{index:number, source:string, outputPath:string, label:string, job:object, plan:object}>}
 */
export function planBatch(request, { random = Math.random, exists = fs.existsSync, assetsDirectory } = {}) {
  const sources = Array.isArray(request.sources) ? request.sources : [];
  if (!sources.length) throw new UnikRequestError("Добавьте хотя бы один файл.");
  if (!request.outputDirectory) throw new UnikRequestError("Не выбрана папка для результата.");
  const options = normalizeOptions(request.options);
  const errors = validateOptions(options, { exists });
  if (errors.length) throw new UnikRequestError(errors.join("\n"));

  const slots = options.variations.count;
  const perFile = options.variations.mode === "preset-per-file" && sources.length > 1;
  const variationsPerSource = perFile ? 1 : slots;
  const totalOutputs = sources.length * variationsPerSource;
  const versionStart = Number(/(\d+)$/.exec(options.naming.versionToken)?.[1] ?? 1) || 1;
  const sizeToken = buildSizeToken(options.resize.width, options.resize.height);
  const ageFiles = options.ageMark.enabled
    ? options.ageMark.custom ?? ageMarkFiles(options.ageMark.geoId, options.ageMark.position, assetsDirectory)
    : null;

  const usedPaths = new Set();
  const planned = [];
  let outputIndex = 0;

  sources.forEach((source, sourceIndex) => {
    const sourcePath = source.path;
    if (!sourcePath || !exists(sourcePath)) throw new UnikRequestError(`Файл не найден: ${sourcePath}`);
    const kind = source.kind === "image" || IMAGE_EXTENSIONS.has(path.extname(sourcePath).toLowerCase()) ? "image" : "video";
    for (let v = 0; v < variationsPerSource; v += 1) {
      const slot = perFile ? sourceIndex % slots : v;
      const style = STYLE_PRESETS.find((s) => s.id === options.variations.styleIds[slot]) ?? STYLE_PRESETS[0];
      const manual = options.manual.enabled && slots === 1 && !perFile;
      const adjust = manual ? options.manual : style;
      const durationMs = (source.durationSeconds ?? 0) * 1000;
      const speedOffsetMs = kind === "video" ? (manual ? options.manual.speedOffsetMs : style.speedOffsetMs) : 0;
      const speedFactor =
        kind === "video" && durationMs > 0 && speedOffsetMs !== 0
          ? Math.min(4, Math.max(0.05, Number((durationMs / Math.max(100, durationMs + speedOffsetMs)).toFixed(4))))
          : undefined;

      const introFile = kind === "video" && options.intro.enabled ? (options.intro.random ? pick(options.intro.library, random) : options.intro.imagePath) : null;
      const overlayFile = kind === "video" && options.overlay.enabled ? (options.overlay.random ? pick(options.overlay.library, random) : options.overlay.videoPath) : null;

      const sequence = outputIndex;
      const version = totalOutputs > 1 ? `v${versionStart + sequence}` : options.naming.versionToken;
      let stem;
      if (options.naming.mode === "structured") {
        stem = [options.naming.geo, options.naming.presetToken, sizeToken, version].map(slugifyToken).filter(Boolean).join("_");
      } else {
        const tail = totalOutputs === 1 && options.naming.randomTail ? slugifyToken(options.naming.randomTail) : createRandomNameToken(8, random);
        stem = `${stripExtension(path.basename(sourcePath))}_${tail}`;
      }
      stem = safeFileStem(stem, "result");
      const container = kind === "image" ? imageContainerFor(sourcePath) : "mp4";
      let outputPath = path.join(request.outputDirectory, `${stem}.${container}`);
      for (let n = 2; usedPaths.has(outputPath.toLowerCase()) || exists(outputPath); n += 1) outputPath = path.join(request.outputDirectory, `${stem}_${n}.${container}`);
      usedPaths.add(outputPath.toLowerCase());

      const job = {
        input: { filePath: sourcePath, mediaKind: kind },
        output: { container, videoCodec: "h264", audioCodec: "aac" },
        transforms: {
          resize: { ...options.resize },
          fps: options.fps,
          bitrate: options.bitrate,
          ageMark: ageFiles ? { enabled: true, ...ageFiles } : { enabled: false },
          introImage: introFile ? { enabled: true, imageFilePath: introFile, durationMs: options.intro.durationMs } : { enabled: false, durationMs: options.intro.durationMs },
          videoOverlay: overlayFile ? { enabled: true, videoFilePath: overlayFile, opacity: options.overlay.opacity } : { enabled: false, opacity: options.overlay.opacity },
          metadata: options.metadata.mode === "custom-date" ? { mode: "custom-date", customDate: options.metadata.customDate } : { mode: options.metadata.mode },
          hueShift: adjust.hueShift,
          saturation: adjust.saturation,
          sharpness: adjust.sharpness,
          speedFactor,
          audioNormalize: options.audio.normalize,
          audioReplacePath: options.audio.replacePath || undefined,
          stripMetadata: options.metadata.mode === "strip",
        },
      };
      planned.push({
        index: outputIndex,
        source: sourcePath,
        outputPath,
        label: `${path.basename(sourcePath)} → ${path.basename(outputPath)}`,
        style: style.id,
        kind,
        durationSeconds: source.durationSeconds ?? null,
        job,
        plan: buildExecutionPlan(job, outputPath),
      });
      outputIndex += 1;
    }
  });
  return planned;
}
