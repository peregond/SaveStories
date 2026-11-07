// Сквозная проверка «Уникализатора» с настоящей докачкой FFmpeg (используется на macOS-раннере CI; на Windows — unik_e2e.ps1).
// Запуск: node node_worker/unik_e2e.mjs [папка для результатов]
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(process.argv[2] ?? "unik-e2e");
fs.rmSync(outDir, { recursive: true, force: true });
const support = path.join(outDir, "support");
fs.mkdirSync(support, { recursive: true });

const failures = [];
const ok = (message) => console.log(`OK   ${message}`);
const fail = (message) => { console.log(`FAIL ${message}`); failures.push(message); };

function worker(request, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(here, "bridge.mjs")], {
      env: { ...process.env, SAVESTORIES_APP_SUPPORT: support, ...env },
    });
    let stdout = "";
    const progress = [];
    let stderrTail = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => {
      stderrTail += chunk;
      const lines = stderrTail.split("\n");
      stderrTail = lines.pop();
      for (const line of lines) if (line.startsWith("unik_")) progress.push(line);
    });
    child.on("error", reject);
    child.on("close", () => {
      try {
        resolve({ response: JSON.parse(stdout.trim().split("\n").pop()), progress });
      } catch (error) {
        reject(new Error(`Ответ воркера не разобрать: ${stdout.slice(0, 400)}`));
      }
    });
    child.stdin.end(JSON.stringify(request));
  });
}

// 1. Каталог и состояние до установки
let { response } = await worker({ command: "unik_status" });
const catalog = JSON.parse(response.data.catalog);
if (catalog.formatPresets.length === 5 && catalog.stylePresets.length === 8 && catalog.ageMarkGeos.length === 9) ok("каталог на месте (5 форматов, 8 стилей, 9 стран)");
else fail("каталог неполный");
console.log(`     до установки: ffmpegInstalled=${response.data.ffmpegInstalled}, path=${response.data.ffmpegPath ?? "-"}`);

// 2. Докачка FFmpeg из интернета (как при первом открытии раздела)
let installed = [];
if (process.env.UNIK_E2E_LOCAL_FFMPEG) {
  // Только для локальной отладки на Linux: берём системный ffmpeg вместо докачки.
  const target = path.join(support, "ffmpeg", "bin");
  fs.mkdirSync(target, { recursive: true });
  for (const name of ["ffmpeg", "ffprobe"]) fs.symlinkSync(execFileSync("which", [name], { encoding: "utf8" }).trim(), path.join(target, name));
  response = { ok: true, data: { ffmpegVersion: "локальный" } };
} else {
  ({ response, progress: installed } = await worker({ command: "unik_install_ffmpeg" }));
}
installed.slice(0, 3).forEach((line) => console.log(`     ${line}`));
if (!response.ok) { fail(`установка FFmpeg: ${response.message}`); process.exit(1); }
ok(`FFmpeg установлен: ${response.data.ffmpegVersion}`);
const bin = path.join(support, "ffmpeg", "bin");
const ffmpeg = path.join(bin, "ffmpeg");
const ffprobe = path.join(bin, "ffprobe");
if (fs.existsSync(ffmpeg) && fs.existsSync(ffprobe)) ok("ffmpeg и ffprobe лежат в папке приложения");
else { fail(`нет ffmpeg/ffprobe в ${bin}`); process.exit(1); }
try { execFileSync(ffmpeg, ["-version"], { stdio: "pipe" }); ok("ffmpeg запускается (подпись/карантин macOS не мешают)"); }
catch (error) { fail(`ffmpeg не запускается: ${error.message}`); process.exit(1); }
({ response } = await worker({ command: "unik_status" }, { SAVESTORIES_FFMPEG_DIR: bin }));
if (response.data.ffmpegInstalled === "true" && response.data.libx264 === "true") ok("статус: FFmpeg готов, libx264 есть");
else fail(`статус после установки: installed=${response.data.ffmpegInstalled}, libx264=${response.data.libx264}`);

// 3. Тестовые файлы
const src = path.join(outDir, "clip.mp4");
execFileSync(ffmpeg, ["-y", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=720x1280:rate=30:duration=3", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", src]);
const pic = path.join(outDir, "pic.png");
execFileSync(ffmpeg, ["-y", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=500x500:rate=1:duration=1", "-frames:v", "1", pic]);

// 4. Обработка: 3 вариации, плашка 18+, структурные имена
const result = path.join(outDir, "result");
const run = await worker({
  command: "unik_process",
  sources: [src, pic],
  outputDirectory: result,
  options: {
    formatPresetId: "meta-story",
    bitrate: "1.5M",
    variations: { count: 3, styleIds: ["soft", "cinematic", "bright"], mode: "all-variations" },
    ageMark: { enabled: true, geoId: "de-germany", position: "bottom" },
    naming: { mode: "structured", geo: "DE", presetToken: "meta", versionToken: "v1" },
  },
}, { SAVESTORIES_FFMPEG_DIR: bin });
console.log(`     ${run.response.message}`);
const results = JSON.parse(run.response.data.results ?? "[]");
const done = results.filter((item) => item.status === "completed");
if (done.length === 6) ok("создано 6 файлов (2 исходника × 3 вариации)"); else fail(`создано ${done.length} из 6: ${run.response.message}`);
if (run.progress.includes("unik_total=6")) ok("прогресс воркера дошёл до интерфейса (unik_total=6)"); else fail("нет строки unik_total=6");

// 5. Проверка результатов ffprobe
const probe = (file, ...args) => execFileSync(ffprobe, ["-v", "error", ...args, file], { encoding: "utf8" }).trim();
for (const item of done) {
  const [width, height] = probe(item.outputPath, "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0").split(",").map(Number);
  const name = path.basename(item.outputPath);
  if (width === 1080 && height === 1920) ok(`${name} — 1080x1920`); else fail(`${name} — ${width}x${height}, ожидалось 1080x1920`);
}
const videos = done.filter((item) => item.outputPath.endsWith(".mp4"));
if (videos.length === 3) {
  const durations = videos.map((item) => Number(probe(item.outputPath, "-show_entries", "format=duration", "-of", "csv=p=0")));
  if (durations[1] > durations[0] && durations[2] < durations[0]) ok(`стили меняют длительность (${durations.map((d) => d.toFixed(2)).join(" / ")})`);
  else fail(`длительности не отличаются как ожидалось: ${durations.join(" / ")}`);
  const audio = probe(videos[0].outputPath, "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0");
  if (audio === "aac") ok("звук сохранён (aac)"); else fail(`звук: ${audio || "нет"}`);
}
const names = done.map((item) => path.basename(item.outputPath)).sort();
console.log(`     имена: ${names.join(", ")}`);
if (names.every((name) => /^DE_meta_/.test(name))) ok("имена в формате ГЕО_формат_… "); else fail("имена не по шаблону");

console.log(failures.length ? `\nПровалено проверок: ${failures.length}` : "\nВсе проверки пройдены");
process.exit(failures.length ? 1 : 0);
