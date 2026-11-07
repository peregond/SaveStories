// FFmpeg для «Уникализатора»: поиск установленных ffmpeg/ffprobe, докачка при первом запуске раздела (как Chromium),
// проверка исходных файлов и запуск обработки с прогрессом.
import { execFile, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const exeName = (name, platform = process.platform) => (platform === "win32" ? `${name}.exe` : name);

export function ffmpegHome(supportDirectory) {
  return path.join(supportDirectory, "ffmpeg");
}

/** Где искать: SAVESTORIES_FFMPEG_DIR, папка приложения (докачанный FFmpeg), затем PATH. */
export function locateFfmpeg({ supportDirectory, env = process.env, platform = process.platform } = {}) {
  const directories = [];
  if (env.SAVESTORIES_FFMPEG_DIR) directories.push([env.SAVESTORIES_FFMPEG_DIR, "env"]);
  if (supportDirectory) directories.push([path.join(ffmpegHome(supportDirectory), "bin"), "app"]);
  for (const entry of String(env.PATH ?? env.Path ?? "").split(path.delimiter).filter(Boolean)) directories.push([entry, "path"]);
  // Приложение macOS запускается без путей Homebrew и MacPorts в PATH — проверяем привычные места.
  if (platform === "darwin") for (const entry of ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]) directories.push([entry, "path"]);
  for (const [directory, source] of directories) {
    const ffmpeg = path.join(directory, exeName("ffmpeg", platform));
    const ffprobe = path.join(directory, exeName("ffprobe", platform));
    if (fsSync.existsSync(ffmpeg) && fsSync.existsSync(ffprobe)) return { ffmpeg, ffprobe, source };
  }
  return null;
}

export async function ffmpegVersion(ffmpegPath) {
  try {
    const { stdout } = await execFileAsync(ffmpegPath, ["-version"], { timeout: 15_000, windowsHide: true });
    return /ffmpeg version (\S+)/.exec(stdout)?.[1] ?? "";
  } catch {
    return "";
  }
}

/** Нужные кодеки: без libx264 видео не собрать. */
export async function ffmpegCapabilities(ffmpegPath) {
  try {
    const { stdout } = await execFileAsync(ffmpegPath, ["-hide_banner", "-encoders"], { timeout: 15_000, windowsHide: true });
    return { libx264: /\blibx264\b/.test(stdout), libx265: /\blibx265\b/.test(stdout), libwebp: /\blibwebp\b/.test(stdout) };
  } catch {
    return { libx264: false, libx265: false, libwebp: false };
  }
}

// ---------------------------------------------------------------- докачка

const WINDOWS_RELEASES_API = "https://api.github.com/repos/GyanD/codexffmpeg/releases/latest";

/** Выбор архива Windows из ответа GitHub API: берётся «essentials» со встроенным digest SHA-256. */
export function pickWindowsAsset(release) {
  const asset = (release?.assets ?? []).find((a) => /^ffmpeg-.*-essentials_build\.zip$/.test(a.name ?? ""));
  if (!asset) throw new Error("В релизе FFmpeg нет архива essentials для Windows.");
  const digest = String(asset.digest ?? "");
  if (!/^sha256:[0-9a-f]{64}$/i.test(digest)) throw new Error("У архива FFmpeg нет SHA-256 digest: установка остановлена.");
  return { name: asset.name, url: asset.browser_download_url, size: asset.size ?? 0, sha256: digest.slice(7).toLowerCase() };
}

async function downloadWithProgress(url, destination, expectedSize, onProgress, fetchImpl) {
  const response = await fetchImpl(url, { headers: { "User-Agent": "SaveMe-FFmpeg" } });
  if (!response.ok || !response.body) throw new Error(`Не удалось скачать FFmpeg: HTTP ${response.status}.`);
  const total = Number(response.headers.get("content-length")) || expectedSize || 0;
  const hash = createHash("sha256");
  const out = fsSync.createWriteStream(destination);
  let done = 0;
  let last = -1;
  try {
    for await (const chunk of response.body) {
      hash.update(chunk);
      if (!out.write(chunk)) await new Promise((resolve) => out.once("drain", resolve));
      done += chunk.length;
      const percent = total ? Math.min(99, Math.floor((done / total) * 100)) : 0;
      if (percent !== last) { last = percent; onProgress?.(percent); }
    }
  } finally {
    await new Promise((resolve) => out.end(resolve));
  }
  return hash.digest("hex");
}

async function extractZip(zipPath, directory) {
  await fs.mkdir(directory, { recursive: true });
  // bsdtar есть в Windows 10 (1803+) и в macOS.
  await execFileAsync("tar", ["-xf", zipPath, "-C", directory], { timeout: 600_000, windowsHide: true, maxBuffer: 16 * 1024 * 1024 });
}

async function findFile(root, fileName) {
  for (const entry of await fs.readdir(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) {
      const found = await findFile(full, fileName);
      if (found) return found;
    } else if (entry.name.toLowerCase() === fileName.toLowerCase()) {
      return full;
    }
  }
  return null;
}

// macOS: статические сборки (arm64 и Intel) с контрольными суммами рядом; ffmpeg и ffprobe — отдельными архивами.
const MAC_BASE = "https://ffmpeg.martin-riedl.de/redirect/latest/macos";

export function macDownloads(arch = process.arch) {
  const folder = arch === "arm64" ? "arm64" : "amd64";
  // «redirect/latest» отдаёт 307 на конкретную версию (…/download/macos/arm64/<время>_<версия>/ffmpeg.zip);
  // файл контрольной суммы лежит только рядом с конкретной версией, поэтому адрес суммы берётся после перехода.
  return ["ffmpeg", "ffprobe"].map((tool) => ({ tool, url: `${MAC_BASE}/${folder}/release/${tool}.zip` }));
}

/** Конкретный адрес архива после перехода по «latest». */
export async function resolveMacDownload(item, fetchImpl = fetch) {
  // Обычный GET с переходом по адресам: HEAD сервер на части путей не принимает. Сам архив тут не читаем — поток закрывается сразу.
  const response = await fetchImpl(item.url, { redirect: "follow", headers: { "User-Agent": "SaveMe-FFmpeg" } });
  try { await response.body?.cancel?.(); } catch { /* поток уже закрыт */ }
  if (!response.ok) throw new Error(`Не удалось найти актуальную сборку ${item.tool}: HTTP ${response.status} (${item.url}).`);
  const url = response.url || item.url;
  return { ...item, url, shaUrl: `${url}.sha256` };
}

/** SHA-256 из текста вида «<hash>  имя» или просто «<hash>». */
export function parseSha256(text) {
  const match = /\b([0-9a-fA-F]{64})\b/.exec(String(text ?? ""));
  if (!match) throw new Error("Не удалось прочитать контрольную сумму FFmpeg.");
  return match[1].toLowerCase();
}

async function extractMacZip(zipPath, directory) {
  await fs.mkdir(directory, { recursive: true });
  await execFileAsync("ditto", ["-x", "-k", zipPath, directory], { timeout: 600_000, maxBuffer: 16 * 1024 * 1024 });
}

async function installOnMac({ home, work, onProgress, onMessage, fetchImpl, arch }) {
  const bin = path.join(home, "bin");
  await fs.mkdir(bin, { recursive: true });
  const downloads = macDownloads(arch);
  for (const [index, entry] of downloads.entries()) {
    onMessage?.(`Скачиваю ${entry.tool}…`);
    const item = await resolveMacDownload(entry, fetchImpl);
    const shaResponse = await fetchImpl(item.shaUrl, { headers: { "User-Agent": "SaveMe-FFmpeg" } });
    if (!shaResponse.ok) throw new Error(`Не удалось получить контрольную сумму ${item.tool}: HTTP ${shaResponse.status}.`);
    const expected = parseSha256(await shaResponse.text());
    const zipPath = path.join(work, `${item.tool}.zip`);
    const actual = await downloadWithProgress(item.url, zipPath, 0, (p) => onProgress?.(Math.floor((index * 100 + p) / downloads.length)), fetchImpl);
    if (actual !== expected) throw new Error(`SHA-256 архива ${item.tool} не совпал с указанным на сайте. Установка остановлена.`);
    const unpacked = path.join(work, `${item.tool}-unpacked`);
    await extractMacZip(zipPath, unpacked);
    const binary = await findFile(unpacked, item.tool);
    if (!binary) throw new Error(`В архиве нет ${item.tool}.`);
    const destination = path.join(bin, item.tool);
    await fs.copyFile(binary, destination);
    await fs.chmod(destination, 0o755);
  }
  return { ffmpeg: path.join(bin, "ffmpeg"), ffprobe: path.join(bin, "ffprobe") };
}

async function installOnWindows({ home, work, onProgress, onMessage, fetchImpl }) {
  onMessage?.("Ищу актуальную сборку FFmpeg…");
  const response = await fetchImpl(WINDOWS_RELEASES_API, { headers: { Accept: "application/vnd.github+json", "User-Agent": "SaveMe-FFmpeg" } });
  if (!response.ok) throw new Error(`GitHub не ответил: HTTP ${response.status}.`);
  const asset = pickWindowsAsset(await response.json());

  onMessage?.(`Скачиваю ${asset.name} (${Math.round(asset.size / 1048576)} МБ)…`);
  const zipPath = path.join(work, asset.name);
  const actual = await downloadWithProgress(asset.url, zipPath, asset.size, onProgress, fetchImpl);
  if (actual !== asset.sha256) throw new Error("SHA-256 архива FFmpeg не совпал с указанным в релизе. Установка остановлена.");

  onMessage?.("Распаковываю…");
  const unpacked = path.join(work, "unpacked");
  await extractZip(zipPath, unpacked);
  const ffmpegSource = await findFile(unpacked, "ffmpeg.exe");
  const ffprobeSource = await findFile(unpacked, "ffprobe.exe");
  if (!ffmpegSource || !ffprobeSource) throw new Error("В архиве FFmpeg нет ffmpeg.exe или ffprobe.exe.");

  const bin = path.join(home, "bin");
  await fs.mkdir(bin, { recursive: true });
  const ffmpeg = path.join(bin, "ffmpeg.exe");
  const ffprobe = path.join(bin, "ffprobe.exe");
  await fs.copyFile(ffmpegSource, ffmpeg);
  await fs.copyFile(ffprobeSource, ffprobe);
  return { ffmpeg, ffprobe, label: asset.name };
}

/**
 * Докачивает FFmpeg в <support>/ffmpeg/bin и проверяет контрольные суммы.
 * @returns {Promise<{ffmpeg:string, ffprobe:string, version:string}>}
 */
export async function installFfmpeg({ supportDirectory, onProgress, onMessage, fetchImpl = fetch, platform = process.platform, arch = process.arch } = {}) {
  if (platform !== "win32" && platform !== "darwin") throw new Error("Автоматическая установка FFmpeg доступна на Windows и macOS.");
  const home = ffmpegHome(supportDirectory);
  const work = path.join(home, "download");
  await fs.rm(work, { recursive: true, force: true });
  await fs.mkdir(work, { recursive: true });
  try {
    const installed = platform === "win32"
      ? await installOnWindows({ home, work, onProgress, onMessage, fetchImpl })
      : await installOnMac({ home, work, onProgress, onMessage, fetchImpl, arch });
    const version = await ffmpegVersion(installed.ffmpeg);
    if (!version) throw new Error("Скачанный ffmpeg не запускается.");
    await fs.writeFile(path.join(home, "version.txt"), `${version}\n${installed.label ?? ""}\n`);
    onProgress?.(100);
    return { ffmpeg: installed.ffmpeg, ffprobe: installed.ffprobe, version };
  } finally {
    await fs.rm(work, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------- проверка и запуск

/** Сводка по файлу: вид, длительность, размер кадра и звук. */
export async function inspectMedia(ffprobePath, filePath) {
  const { stdout } = await execFileAsync(ffprobePath, ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", filePath], {
    timeout: 30_000, maxBuffer: 4 * 1024 * 1024, windowsHide: true,
  });
  const parsed = JSON.parse(stdout);
  const video = parsed.streams?.find((s) => s.codec_type === "video");
  const audio = parsed.streams?.find((s) => s.codec_type === "audio");
  if (!video) throw new Error("Файл не содержит изображения или видеодорожки.");
  const duration = Number(parsed.format?.duration);
  const extension = path.extname(filePath).toLowerCase();
  return {
    filePath,
    kind: [".png", ".jpg", ".jpeg", ".webp"].includes(extension) ? "image" : "video",
    durationSeconds: Number.isFinite(duration) && duration > 0 ? duration : null,
    sizeBytes: parsed.format?.size ? Number(parsed.format.size) : null,
    width: video.width ?? null,
    height: video.height ?? null,
    videoCodec: video.codec_name ?? null,
    audioCodec: audio?.codec_name ?? null,
    hasAudio: Boolean(audio),
  };
}

function errorTail(stderr) {
  const lines = stderr.split("\n").map((l) => l.trim()).filter(Boolean);
  return lines.slice(-6).join("\n");
}

/**
 * Запускает ffmpeg с прогрессом (0–100). Результат — промис; при ошибке в тексте последние строки stderr.
 */
// Запущенные ffmpeg: при остановке воркера (кнопка «Стоп» посылает SIGTERM только процессу Node) их нужно завершить,
// иначе обработка продолжится в фоне.
const activeChildren = new Set();
let exitHooksInstalled = false;

export function killActiveFfmpeg() {
  for (const child of activeChildren) {
    try { child.kill("SIGKILL"); } catch { /* уже завершён */ }
  }
  activeChildren.clear();
}

function installExitHooks() {
  if (exitHooksInstalled) return;
  exitHooksInstalled = true;
  process.once("exit", killActiveFfmpeg);
  for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) {
    process.once(signal, () => {
      killActiveFfmpeg();
      process.exit(signal === "SIGINT" ? 130 : 143);
    });
  }
}

export function runFfmpeg(ffmpegPath, args, { durationSeconds = 0, onProgress } = {}) {
  return new Promise((resolve, reject) => {
    installExitHooks();
    const child = spawn(ffmpegPath, ["-hide_banner", "-progress", "pipe:1", "-nostats", ...args], { stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
    activeChildren.add(child);
    child.once("close", () => activeChildren.delete(child));
    let buffer = "";
    let stderr = "";
    let outTimeMs = null;
    child.stdout.on("data", (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const raw of lines) {
        const [key, value] = raw.trim().split("=");
        if (key === "out_time_ms") outTimeMs = Number(value);
        if (key === "progress" && durationSeconds > 0 && outTimeMs !== null && Number.isFinite(outTimeMs)) {
          onProgress?.(Math.max(0, Math.min(99, Math.round((outTimeMs / 1_000_000 / durationSeconds) * 100))));
        }
      }
    });
    child.stderr.on("data", (chunk) => { stderr = (stderr + chunk.toString()).slice(-64 * 1024); });
    child.on("error", reject);
    child.on("close", (code, signal) => {
      if (code === 0) { onProgress?.(100); resolve(); return; }
      const reason = signal ? `FFmpeg прерван сигналом ${signal}.` : `FFmpeg завершился с кодом ${code}.`;
      const tail = errorTail(stderr);
      reject(new Error(tail ? `${reason}\n${tail}` : reason));
    });
  });
}

export const defaultSupportDirectory = () => process.env.SAVESTORIES_APP_SUPPORT || path.join(os.homedir(), ".savestories");
