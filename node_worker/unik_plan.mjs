// План обработки и аргументы FFmpeg для «Уникализатора». Перенос packages/processing-core из сервиса n1.unikalizator:
// фильтры и порядок слоёв сохранены, чтобы результат совпадал с онлайн-сервисом.
import os from "node:os";
import path from "node:path";

function parseBitrateKbps(value) {
  if (!value) return null;
  const normalized = String(value).trim().toLowerCase();
  if (normalized.endsWith("k")) {
    const numeric = Number(normalized.slice(0, -1));
    return Number.isFinite(numeric) ? numeric : null;
  }
  if (normalized.endsWith("m")) {
    const numeric = Number(normalized.slice(0, -1));
    return Number.isFinite(numeric) ? Math.round(numeric * 1000) : null;
  }
  const numeric = Number(normalized);
  return Number.isFinite(numeric) ? numeric : null;
}

const formatBitrateKbps = (value) => `${Math.max(300, Math.round(value))}k`;

function resolveVideoQuality(requestedBitrate) {
  const targetKbps = parseBitrateKbps(requestedBitrate) ?? 2000;
  const crf = targetKbps >= 6000 ? "17" : targetKbps >= 4000 ? "20" : targetKbps >= 3000 ? "23" : targetKbps >= 2000 ? "25" : "27";
  return {
    crf,
    maxrate: formatBitrateKbps(Math.round(targetKbps * 1.15)),
    bufsize: formatBitrateKbps(Math.round(targetKbps * 2.3)),
  };
}

const isImageJob = (job) => job.input.mediaKind === "image";

function shouldUseBlurBackground(job) {
  const resize = job.transforms.resize;
  return Boolean(resize && resize.fit === "contain" && resize.backgroundStyle === "blur");
}

function buildResizeFilter(job) {
  const resize = job.transforms.resize;
  if (!resize) return null;
  const { width, height, fit } = resize;
  if (fit === "contain") {
    if (resize.backgroundStyle === "blur") return null;
    const padColor = resize.backgroundStyle === "solid" ? resize.backgroundColor ?? "#111111" : "#111111";
    return [
      `scale=${width}:${height}:force_original_aspect_ratio=decrease:flags=lanczos`,
      `pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:${padColor}`,
    ].join(",");
  }
  return [`scale=${width}:${height}:force_original_aspect_ratio=increase:flags=lanczos`, `crop=${width}:${height}`].join(",");
}

function buildAdjustmentFilter(job) {
  const parts = [];
  const t = job.transforms;
  // Порядок как в онлайн-сервисе: отражение, яркость и контраст, затем стиль.
  if (t.horizontalFlip) parts.push("hflip");
  if ((t.brightness !== undefined && t.brightness !== 0) || (t.contrast !== undefined && t.contrast !== 1)) {
    parts.push(`eq=brightness=${t.brightness ?? 0}:contrast=${t.contrast ?? 1}`);
  }
  if (t.hueShift && t.hueShift !== 0) parts.push(`hue=h=${t.hueShift}`);
  if (t.saturation !== undefined && t.saturation !== 1) parts.push(`eq=saturation=${t.saturation}`);
  if (t.sharpness && t.sharpness > 0) parts.push(`unsharp=5:5:${t.sharpness}:5:5:0.0`);
  return parts.length ? parts.join(",") : null;
}

/** Файл плашки 18+ под соотношение сторон результата. */
export function resolveAgeMarkPath(job) {
  const ageMark = job.transforms.ageMark;
  if (!ageMark?.enabled) return null;
  const resize = job.transforms.resize;
  if (!resize) return ageMark.squareFilePath ?? ageMark.portraitFilePath ?? null;
  const ratio = resize.width / resize.height;
  if (Math.abs(ratio - 4 / 5) < 0.02) return ageMark.fourByFiveFilePath ?? ageMark.squareFilePath ?? ageMark.portraitFilePath ?? null;
  if (resize.height > resize.width) return ageMark.portraitFilePath ?? ageMark.squareFilePath ?? null;
  return ageMark.squareFilePath ?? ageMark.portraitFilePath ?? null;
}

const getIntroImage = (job) => {
  const intro = job.transforms.introImage;
  return intro?.enabled && intro.imageFilePath ? intro : null;
};
const getVideoOverlay = (job) => {
  const overlay = job.transforms.videoOverlay;
  return overlay?.enabled && overlay.videoFilePath ? overlay : null;
};

/** Ускорение звука цепочкой atempo (один фильтр принимает 0.5–2). */
export function buildAtempoFilter(speedFactor) {
  const filters = [];
  let remaining = speedFactor;
  while (remaining > 2) { filters.push("atempo=2"); remaining /= 2; }
  while (remaining < 0.5) { filters.push("atempo=0.5"); remaining /= 0.5; }
  filters.push(`atempo=${remaining.toFixed(4)}`);
  return filters.join(",");
}

const toMetadataTimestamp = (customDate) => (customDate ? `${customDate}T12:00:00Z` : null);

export function buildOutputPath(inputFilePath, container = "mp4", outputSuffix, outputName) {
  const suffix = outputSuffix ? `_${outputSuffix}` : "";
  if (outputName) {
    return inputFilePath ? path.join(path.dirname(inputFilePath), `${outputName}${suffix}.${container}`) : `output/${outputName}${suffix}.${container}`;
  }
  if (!inputFilePath) return `output/result${suffix}.${container}`;
  const extension = path.extname(inputFilePath);
  const stem = extension ? inputFilePath.slice(0, -extension.length) : inputFilePath;
  return `${stem}.processed${suffix}.${container}`;
}

/**
 * @param {object} job  задание в формате MediaJob сервиса
 * @param {string} [destinationPath]
 * @param {{threads?: number}} [options]
 */
export function buildExecutionPlan(job, destinationPath, options = {}) {
  const imageJob = isImageJob(job);
  const steps = [{ kind: "inspect", description: "Проверка исходного файла." }];
  const resize = job.transforms.resize;
  const resizeFilter = buildResizeFilter(job);
  const adjustmentFilter = buildAdjustmentFilter(job);
  const useBlurBackground = shouldUseBlurBackground(job);
  const speedFactor = !imageJob ? job.transforms.speedFactor ?? 1 : 1;
  const ffmpegArgs = ["-y", "-i", job.input.filePath ?? "input.mp4"];
  let nextInputIndex = 1;
  const introImage = !imageJob ? getIntroImage(job) : null;
  const videoOverlay = !imageJob ? getVideoOverlay(job) : null;
  let introImageInputIndex = null;
  let videoOverlayInputIndex = null;
  const resolvedAgeMarkPath = resolveAgeMarkPath(job);
  let ageMarkInputIndex = null;
  let audioReplaceInputIndex = null;

  if (introImage) {
    introImageInputIndex = nextInputIndex++;
    ffmpegArgs.push("-loop", "1", "-i", introImage.imageFilePath);
  }
  if (videoOverlay) {
    videoOverlayInputIndex = nextInputIndex++;
    ffmpegArgs.push("-stream_loop", "-1", "-i", videoOverlay.videoFilePath);
  }
  if (resolvedAgeMarkPath) {
    ageMarkInputIndex = nextInputIndex++;
    if (!imageJob) ffmpegArgs.push("-loop", "1");
    ffmpegArgs.push("-i", resolvedAgeMarkPath);
  }
  if (!imageJob && job.transforms.audioReplacePath) {
    audioReplaceInputIndex = nextInputIndex++;
    ffmpegArgs.push("-i", job.transforms.audioReplacePath);
  }

  if (resize && (resizeFilter || useBlurBackground)) {
    steps.push({ kind: "video", description: resize.fit === "contain" && resize.backgroundStyle === "blur" ? `Размер ${resize.width}x${resize.height}, фон — размытая копия.` : `Размер ${resize.width}x${resize.height} (${resize.fit === "cover" ? "с обрезкой" : "с полями"}).` });
  }
  if (job.transforms.horizontalFlip) steps.push({ kind: "video", description: "Исходник отражён по горизонтали." });
  if ((job.transforms.brightness !== undefined && job.transforms.brightness !== 0) || (job.transforms.contrast !== undefined && job.transforms.contrast !== 1)) {
    steps.push({ kind: "video", description: `Яркость: ${job.transforms.brightness ?? 0}, контраст: ${job.transforms.contrast ?? 1}.` });
  }
  if (!imageJob && job.transforms.hueShift) steps.push({ kind: "video", description: `Сдвиг оттенка: ${job.transforms.hueShift}°.` });
  if (!imageJob && job.transforms.saturation !== undefined && job.transforms.saturation !== 1) steps.push({ kind: "video", description: `Насыщенность: ${job.transforms.saturation}.` });
  if (!imageJob && job.transforms.sharpness > 0) steps.push({ kind: "video", description: `Резкость: ${job.transforms.sharpness}.` });
  if (!imageJob && speedFactor !== 1) steps.push({ kind: "video", description: `Скорость: ${(speedFactor * 100).toFixed(1)}% от исходной.` });
  if (introImage) steps.push({ kind: "video", description: `Заставка на ${introImage.durationMs} мс в начале.` });
  if (videoOverlay) steps.push({ kind: "video", description: `Видео-слой поверх с прозрачностью ${videoOverlay.opacity}.` });
  if (resolvedAgeMarkPath) steps.push({ kind: "video", description: "Плашка 18+ поверх кадра." });

  if (introImageInputIndex !== null || videoOverlayInputIndex !== null || ageMarkInputIndex !== null || useBlurBackground) {
    const filterParts = [];
    let current = "[0:v]";

    if (useBlurBackground && resize) {
      filterParts.push("[0:v]split=2[bgsrc][fgsrc]");
      filterParts.push(`[bgsrc]scale=${resize.width}:${resize.height}:flags=lanczos,gblur=sigma=42,eq=brightness=-0.03:saturation=1.08[bgv]`);
      filterParts.push(`[fgsrc]scale=${resize.width}:${resize.height}:force_original_aspect_ratio=decrease:flags=lanczos[fgv]`);
      filterParts.push("[bgv][fgv]overlay=(W-w)/2:(H-h)/2[resizeout]");
      current = "[resizeout]";
    } else if (resizeFilter) {
      filterParts.push(`[0:v]${resizeFilter}[basev]`);
      current = "[basev]";
    }

    if (adjustmentFilter) {
      filterParts.push(`${current}${adjustmentFilter}[adjustedv]`);
      current = "[adjustedv]";
    }

    if (introImageInputIndex !== null) {
      const introSeconds = (introImage?.durationMs ?? 0) / 1000;
      const introScale = resize
        ? `scale=${resize.width}:${resize.height}:force_original_aspect_ratio=decrease:flags=lanczos,pad=${resize.width}:${resize.height}:(ow-iw)/2:(oh-ih)/2`
        : "scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos";
      filterParts.push(`[${introImageInputIndex}:v]${introScale},trim=duration=${introSeconds},setpts=PTS-STARTPTS[introv]`);
      filterParts.push(`${current}[introv]overlay=0:0:enable='between(t,0,${introSeconds})'[introout]`);
      current = "[introout]";
    }

    if (ageMarkInputIndex !== null) {
      const overlayLabel = resize ? "[overlayv]" : `[${ageMarkInputIndex}:v]`;
      if (resize) filterParts.push(`[${ageMarkInputIndex}:v]scale=${resize.width}:${resize.height}:flags=lanczos${overlayLabel}`);
      filterParts.push(`${current}${overlayLabel}overlay=0:0:shortest=1[vout]`);
      current = "[vout]";
    }

    if (videoOverlayInputIndex !== null) {
      const opacity = videoOverlay?.opacity ?? 0.25;
      if (resize) {
        filterParts.push(`[${videoOverlayInputIndex}:v]scale=${resize.width}:${resize.height}:force_original_aspect_ratio=increase:flags=lanczos,crop=${resize.width}:${resize.height},format=rgba,colorchannelmixer=aa=${opacity}[vidoverlay]`);
      } else {
        filterParts.push(`[${videoOverlayInputIndex}:v]format=rgba,colorchannelmixer=aa=${opacity}[vidoverlay]`);
      }
      filterParts.push(`${current}[vidoverlay]overlay=0:0:shortest=1[voverlay]`);
      current = "[voverlay]";
    }

    if (speedFactor !== 1) {
      filterParts.push(`${current}setpts=${(1 / speedFactor).toFixed(6)}*PTS[vspeed]`);
      current = "[vspeed]";
    }

    filterParts.push(`${current}setsar=1[vfinal]`);
    ffmpegArgs.push("-filter_complex", filterParts.join(";"), "-map", "[vfinal]");
  } else {
    const simple = [resizeFilter, adjustmentFilter].filter(Boolean).join(",");
    const speed = speedFactor !== 1 ? `setpts=${(1 / speedFactor).toFixed(6)}*PTS,` : "";
    ffmpegArgs.push("-vf", `${simple ? `${simple},` : ""}${speed}setsar=1`, "-map", "0:v:0");
  }

  if (!imageJob && job.transforms.fps) {
    steps.push({ kind: "video", description: `Частота кадров: ${job.transforms.fps} fps.` });
    ffmpegArgs.push("-r", String(job.transforms.fps));
  }
  if (!imageJob && job.transforms.bitrate) steps.push({ kind: "video", description: `Целевой битрейт ${job.transforms.bitrate}.` });
  if (!imageJob && job.transforms.audioReplacePath) steps.push({ kind: "audio", description: "Звук заменён." });
  if (!imageJob) ffmpegArgs.push("-map", audioReplaceInputIndex !== null ? `${audioReplaceInputIndex}:a:0` : "0:a?");

  const audioFilters = [];
  if (!imageJob && speedFactor !== 1) audioFilters.push(buildAtempoFilter(speedFactor));
  if (!imageJob && job.transforms.audioNormalize) {
    steps.push({ kind: "audio", description: "Выравнивание громкости." });
    audioFilters.push("loudnorm=I=-16:TP=-1.5:LRA=11");
  }
  if (!imageJob) {
    audioFilters.push("apad");
    ffmpegArgs.push("-shortest");
    ffmpegArgs.push("-af", audioFilters.join(","));
  }

  if (job.transforms.stripMetadata || job.transforms.metadata?.mode === "strip") {
    steps.push({ kind: "metadata", description: "Метаданные удалены." });
    ffmpegArgs.push("-map_metadata", "-1");
  } else if (job.transforms.metadata?.mode === "export-date") {
    const stamp = new Date().toISOString();
    steps.push({ kind: "metadata", description: `Дата создания в метаданных: ${stamp}.` });
    ffmpegArgs.push("-metadata", `creation_time=${stamp}`);
  } else if (job.transforms.metadata?.mode === "custom-date") {
    const stamp = toMetadataTimestamp(job.transforms.metadata.customDate);
    if (stamp) {
      steps.push({ kind: "metadata", description: `Дата создания в метаданных: ${job.transforms.metadata.customDate}.` });
      ffmpegArgs.push("-metadata", `creation_time=${stamp}`);
    }
  }

  const outputPath = destinationPath ?? buildOutputPath(job.input.filePath, job.output.container, job.outputSuffix, job.outputName);
  steps.push({ kind: "output", description: `Результат: ${outputPath}.` });

  if (imageJob) {
    ffmpegArgs.push("-frames:v", "1");
    if (job.output.container === "png") ffmpegArgs.push("-c:v", "png");
    else if (job.output.container === "jpg") ffmpegArgs.push("-c:v", "mjpeg", "-q:v", "2");
    else if (job.output.container === "webp") ffmpegArgs.push("-c:v", "libwebp", "-quality", "90");
    ffmpegArgs.push(outputPath);
  } else {
    const quality = resolveVideoQuality(job.transforms.bitrate);
    const targetKbps = parseBitrateKbps(job.transforms.bitrate) ?? 2000;
    const encoderPreset = targetKbps >= 6000 ? "medium" : "veryfast";
    // Половина ядер: компьютер остаётся отзывчивым, пока идёт обработка.
    const threads = String(options.threads ?? Math.max(2, Math.floor(os.cpus().length / 2)));
    ffmpegArgs.push(
      "-threads", threads,
      "-c:v", job.output.videoCodec === "h264" ? "libx264" : "libx265",
      "-preset", encoderPreset,
      "-crf", quality.crf,
      "-pix_fmt", "yuv420p",
      "-movflags", "+faststart",
      "-maxrate", quality.maxrate, "-bufsize", quality.bufsize,
      "-c:a", job.output.audioCodec,
      "-b:a", "128k",
      outputPath,
    );
  }

  return { outputPath, steps, ffmpegArgs };
}
