// Команды раздела «Уникализатор» для воркера: unik_status, unik_install_ffmpeg, unik_inspect, unik_process.
// Прогресс идёт строками в stderr: unik_job_<N>_start= / _progress= / _done= / _error=, unik_ffmpeg_progress= / _message=.
import fs from "node:fs/promises";
import path from "node:path";

import { catalog } from "./unik_catalog.mjs";
import { UnikRequestError, planBatch } from "./unik_batch.mjs";
import {
  defaultSupportDirectory,
  ffmpegCapabilities,
  ffmpegVersion,
  inspectMedia,
  installFfmpeg,
  locateFfmpeg,
  runFfmpeg,
} from "./unik_ffmpeg.mjs";

async function requireFfmpeg(supportDirectory) {
  const located = locateFfmpeg({ supportDirectory });
  if (!located) return { error: ["unik_ffmpeg_missing", "FFmpeg не установлен. Откройте раздел «Уникализатор» и нажмите «Установить FFmpeg»."] };
  const capabilities = await ffmpegCapabilities(located.ffmpeg);
  if (!capabilities.libx264) return { error: ["unik_ffmpeg_unsupported", "Этот FFmpeg собран без libx264 и не умеет делать видео H.264. Установите FFmpeg из приложения."] };
  return { located, capabilities };
}

async function statusCommand({ emit, supportDirectory }) {
  const located = locateFfmpeg({ supportDirectory });
  const capabilities = located ? await ffmpegCapabilities(located.ffmpeg) : { libx264: false, libx265: false, libwebp: false };
  emit(true, "unik_status", "Состояние раздела «Уникализатор».", {
    data: {
      ffmpegInstalled: String(Boolean(located && capabilities.libx264)),
      ffmpegSource: located?.source ?? "",
      ffmpegPath: located?.ffmpeg ?? "",
      ffmpegVersion: located ? await ffmpegVersion(located.ffmpeg) : "",
      libx264: String(capabilities.libx264),
      libwebp: String(capabilities.libwebp),
      catalog: JSON.stringify(catalog()),
    },
  });
}

async function installCommand({ emit, emitProgress, supportDirectory }) {
  try {
    const result = await installFfmpeg({
      supportDirectory,
      onProgress: (percent) => emitProgress(`unik_ffmpeg_progress=${percent}`),
      onMessage: (message) => emitProgress(`unik_ffmpeg_message=${message}`),
    });
    emit(true, "unik_ffmpeg_ready", `FFmpeg ${result.version} установлен.`, { data: { ffmpegPath: result.ffmpeg, ffmpegVersion: result.version } });
  } catch (error) {
    emit(false, "unik_ffmpeg_install_error", String(error?.message ?? error));
  }
}

async function inspectCommand({ emit, request, supportDirectory }) {
  const ready = await requireFfmpeg(supportDirectory);
  if (ready.error) { emit(false, ...ready.error); return; }
  const files = (Array.isArray(request.files) ? request.files : []).filter((f) => typeof f === "string" && f);
  const results = [];
  for (const file of files) {
    try {
      results.push({ ok: true, ...(await inspectMedia(ready.located.ffprobe, file)) });
    } catch (error) {
      results.push({ ok: false, filePath: file, message: String(error?.message ?? error).split("\n")[0] });
    }
  }
  emit(true, "unik_inspected", `Проверено файлов: ${results.length}.`, { data: { inspections: JSON.stringify(results) } });
}

async function processCommand({ emit, emitProgress, request, supportDirectory }) {
  const ready = await requireFfmpeg(supportDirectory);
  if (ready.error) { emit(false, ...ready.error); return; }
  const { ffmpeg, ffprobe } = ready.located;

  const paths = (Array.isArray(request.sources) ? request.sources : []).map((s) => (typeof s === "string" ? s : s?.path)).filter(Boolean);
  const sources = [];
  const skipped = [];
  for (const file of paths) {
    try {
      const info = await inspectMedia(ffprobe, file);
      sources.push({ path: file, kind: info.kind, durationSeconds: info.durationSeconds });
    } catch (error) {
      skipped.push({ source: file, message: String(error?.message ?? error).split("\n")[0] });
    }
  }
  if (!sources.length) { emit(false, "unik_request_error", skipped.length ? `Файлы не удалось прочитать: ${skipped[0].message}` : "Добавьте хотя бы один файл."); return; }

  let planned;
  try {
    planned = planBatch({ sources, outputDirectory: request.outputDirectory, options: request.options });
  } catch (error) {
    if (error instanceof UnikRequestError) { emit(false, "unik_request_error", error.message); return; }
    throw error;
  }
  await fs.mkdir(request.outputDirectory, { recursive: true });
  emitProgress(`unik_total=${planned.length}`);

  const results = skipped.map((s) => ({ index: -1, source: s.source, outputPath: "", status: "failed", message: s.message }));
  let done = 0;
  let failed = skipped.length;
  for (const item of planned) {
    emitProgress(`unik_job_${item.index}_start=${item.label}`);
    let lastPercent = -1;
    try {
      await runFfmpeg(ffmpeg, item.plan.ffmpegArgs, {
        durationSeconds: (item.durationSeconds ?? 0) / (item.job.transforms.speedFactor ?? 1),
        onProgress: (percent) => {
          if (percent === lastPercent || (percent < 100 && percent - lastPercent < 2)) return;
          lastPercent = percent;
          emitProgress(`unik_job_${item.index}_progress=${percent}`);
        },
      });
      done += 1;
      results.push({ index: item.index, source: item.source, outputPath: item.outputPath, status: "completed", message: "", style: item.style });
      emitProgress(`unik_job_${item.index}_done=${item.outputPath}`);
    } catch (error) {
      failed += 1;
      const message = String(error?.message ?? error);
      await fs.rm(item.outputPath, { force: true }).catch(() => {});
      results.push({ index: item.index, source: item.source, outputPath: item.outputPath, status: "failed", message });
      emitProgress(`unik_job_${item.index}_error=${message.split("\n")[0]}`);
    }
  }

  const summary = `Готово: ${done} из ${planned.length + skipped.length}${failed ? `, ошибок: ${failed}` : ""}.`;
  emit(done > 0, done > 0 ? "unik_complete" : "unik_failed", summary, {
    data: { total: String(planned.length + skipped.length), done: String(done), failed: String(failed), results: JSON.stringify(results), outputDirectory: path.resolve(request.outputDirectory) },
    items: results.filter((r) => r.status === "completed").map((r) => ({ localPath: r.outputPath, sourceUrl: r.source, mediaType: r.outputPath.endsWith(".mp4") ? "video" : "image" })),
  });
}

const COMMANDS = {
  unik_status: statusCommand,
  unik_install_ffmpeg: installCommand,
  unik_inspect: inspectCommand,
  unik_process: processCommand,
};

export const isUnikCommand = (command) => Object.hasOwn(COMMANDS, command);

export async function runUnikCommand(request, { emit, emitProgress, supportDirectory = defaultSupportDirectory() }) {
  await COMMANDS[request.command]({ emit, emitProgress, request, supportDirectory });
}
