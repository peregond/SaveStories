import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";

import { inspectMp4, inspectMp4Buffer, muxMp4Tracks } from "./mp4_muxer.mjs";

const UNSUPPORTED_HARD_LINK_CODES = new Set([
  "EOPNOTSUPP",
  "ENOTSUP",
  "EPERM",
  "ENOSYS",
  "EXDEV",
]);

function temporaryPathFor(localPath, label) {
  return path.join(
    path.dirname(localPath),
    `.${path.basename(localPath)}.${process.pid}.${randomUUID()}.${label}.mp4`,
  );
}

async function publishTemporaryFile(temporaryPath, localPath, operations = fs) {
  try {
    // Both paths are siblings, so a hard-link publish is atomic and refuses an
    // existing destination on APFS and NTFS instead of racing access+rename.
    await operations.link(temporaryPath, localPath);
  } catch (error) {
    if (error?.code === "EEXIST") {
      throw new Error(`Файл назначения уже существует: ${localPath}`);
    }
    if (!UNSUPPORTED_HARD_LINK_CODES.has(error?.code)) throw error;
    try {
      // exFAT, network shares and some File Provider volumes do not support
      // hard links. COPYFILE_EXCL preserves the no-overwrite guarantee there.
      await operations.copyFile(temporaryPath, localPath, fs.constants.COPYFILE_EXCL);
    } catch (copyError) {
      if (copyError?.code === "EEXIST") {
        throw new Error(`Файл назначения уже существует: ${localPath}`);
      }
      throw copyError;
    }
  }
  try {
    await operations.unlink(temporaryPath);
  } catch {
    // The final file is already complete and exclusively published. Cleanup is
    // best-effort here; the pipeline's outer finally removes its temp path too.
  }
}

async function runExternalMuxer(executablePath, videoPath, audioPath, outputPath) {
  await fs.access(executablePath, fs.constants.X_OK);
  await new Promise((resolve, reject) => {
    const child = spawn(executablePath, [videoPath, audioPath, outputPath], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      reject(error);
    };

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      if (stderr.length < 32_000) stderr += chunk;
    });
    child.once("error", (error) => {
      fail(new Error(`Не удалось запустить объединение видео и звука: ${error.message}`));
    });
    child.once("close", (code, signal) => {
      if (settled) return;
      if (code === 0) {
        settled = true;
        resolve();
        return;
      }
      const detail = stderr.trim() || (signal ? `signal ${signal}` : `exit ${code}`);
      fail(new Error(`Не удалось объединить видео и звук: ${detail}`));
    });
  });
}

async function muxWithFallback({
  videoPath,
  audioPath,
  outputPath,
  externalMuxerPath,
  emitProgress,
  runExternal = runExternalMuxer,
}) {
  if (externalMuxerPath) {
    try {
      await runExternal(externalMuxerPath, videoPath, audioPath, outputPath);
      const nativeInspection = await inspectMp4(outputPath);
      if (
        !nativeInspection.hasVideo
        || !nativeInspection.hasAudio
        || !nativeInspection.mediaDataComplete
      ) {
        throw new Error("Нативное объединение вернуло неполный MP4 без видео или звука.");
      }
      return "native";
    } catch (error) {
      await fs.rm(outputPath, { force: true });
      emitProgress?.(`native_audio_muxer_fallback=${error.message}`);
    }
  }

  await muxMp4Tracks({ videoPath, audioPath, outputPath });
  return "javascript";
}

async function saveVideoWithAudio({
  videoBody,
  localPath,
  audioSourceUrl = null,
  expectsAudio = null,
  fetchAudio,
  validateAudio,
  externalMuxerPath = null,
  emitProgress = null,
}) {
  if (!videoBody || videoBody.length === 0) {
    throw new Error("Получен пустой видеофайл.");
  }
  if (typeof localPath !== "string" || localPath.trim() === "") {
    throw new TypeError("localPath is required");
  }

  await fs.mkdir(path.dirname(localPath), { recursive: true });
  const videoPath = temporaryPathFor(localPath, "video");
  const audioPath = temporaryPathFor(localPath, "audio");
  const muxedPath = temporaryPathFor(localPath, "muxed");

  try {
    const sourceInspection = inspectMp4Buffer(videoBody);
    if (!sourceInspection.hasVideo) {
      throw new Error("Скачанный MP4 не содержит видеодорожку.");
    }
    if (!sourceInspection.mediaDataComplete) {
      throw new Error("Скачанный MP4 неполный: не все видео- или аудиосэмплы получены.");
    }
    await fs.writeFile(videoPath, videoBody, { flag: "wx" });

    if (sourceInspection.hasAudio) {
      await publishTemporaryFile(videoPath, localPath);
      emitProgress?.(`embedded_audio_verified=${path.basename(localPath)}`);
      return {
        contentLength: videoBody.length,
        audioMuxed: false,
        audioPresent: true,
        muxer: "embedded",
      };
    }

    if (!audioSourceUrl) {
      if (expectsAudio !== false) {
        throw new Error("Instagram отдал видео без звука, а отдельную аудиодорожку получить не удалось.");
      }
      await publishTemporaryFile(videoPath, localPath);
      return {
        contentLength: videoBody.length,
        audioMuxed: false,
        audioPresent: false,
        muxer: null,
      };
    }

    if (typeof fetchAudio !== "function") {
      throw new TypeError("fetchAudio is required when audioSourceUrl is present");
    }
    const audio = await fetchAudio(audioSourceUrl);
    validateAudio?.(audio.body, audio.contentType);
    const audioInspection = inspectMp4Buffer(audio.body);
    if (!audioInspection.hasAudio || !audioInspection.mediaDataComplete) {
      throw new Error("Отдельный MP4 не содержит аудиодорожку.");
    }
    await fs.writeFile(audioPath, audio.body, { flag: "wx" });

    const muxer = await muxWithFallback({
      videoPath,
      audioPath,
      outputPath: muxedPath,
      externalMuxerPath,
      emitProgress,
    });
    const outputInspection = await inspectMp4(muxedPath);
    if (!outputInspection.hasVideo || !outputInspection.hasAudio || !outputInspection.mediaDataComplete) {
      throw new Error("Объединённый MP4 не содержит одновременно видео и звук.");
    }

    const muxedStat = await fs.stat(muxedPath);
    if (!muxedStat.isFile() || muxedStat.size < 512) {
      throw new Error("Объединённый видеофайл не прошёл проверку целостности.");
    }
    await publishTemporaryFile(muxedPath, localPath);
    emitProgress?.(`dash_audio_muxed=${path.basename(localPath)}:${muxer}`);
    return {
      contentLength: muxedStat.size,
      audioMuxed: true,
      audioPresent: true,
      muxer,
    };
  } finally {
    await Promise.allSettled([
      fs.rm(videoPath, { force: true }),
      fs.rm(audioPath, { force: true }),
      fs.rm(muxedPath, { force: true }),
    ]);
  }
}

export {
  muxWithFallback,
  publishTemporaryFile,
  saveVideoWithAudio,
};
