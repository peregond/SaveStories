import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { inspectMedia, locateFfmpeg, pickWindowsAsset } from "./unik_ffmpeg.mjs";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "bridge.mjs");
const located = locateFfmpeg({ supportDirectory: path.join(os.tmpdir(), "no-such-support") });
const realFfmpeg = { skip: located ? false : "ffmpeg не найден в PATH" };

test("поиск ffmpeg: переменная окружения важнее PATH, без пары ffmpeg+ffprobe не считается найденным", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "unik-locate-"));
  try {
    assert.equal(locateFfmpeg({ supportDirectory: dir, env: { PATH: "" }, platform: "linux" }), null);
    const envDir = path.join(dir, "from-env");
    fs.mkdirSync(envDir);
    fs.writeFileSync(path.join(envDir, "ffmpeg"), "");
    assert.equal(locateFfmpeg({ env: { SAVESTORIES_FFMPEG_DIR: envDir, PATH: "" }, platform: "linux" }), null, "нужен и ffprobe");
    fs.writeFileSync(path.join(envDir, "ffprobe"), "");
    const found = locateFfmpeg({ env: { SAVESTORIES_FFMPEG_DIR: envDir, PATH: "" }, platform: "linux" });
    assert.equal(found.source, "env");
    assert.equal(found.ffmpeg, path.join(envDir, "ffmpeg"));
    const app = path.join(dir, "ffmpeg", "bin");
    fs.mkdirSync(app, { recursive: true });
    fs.writeFileSync(path.join(app, "ffmpeg.exe"), "");
    fs.writeFileSync(path.join(app, "ffprobe.exe"), "");
    assert.equal(locateFfmpeg({ supportDirectory: dir, env: { PATH: "" }, platform: "win32" }).source, "app");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("архив Windows выбирается из релиза и обязан иметь SHA-256", () => {
  const release = { assets: [
    { name: "ffmpeg-7.1-full_build.zip", browser_download_url: "u1", size: 1, digest: "sha256:" + "a".repeat(64) },
    { name: "ffmpeg-7.1-essentials_build.zip", browser_download_url: "u2", size: 90_000_000, digest: "sha256:" + "B".repeat(64) },
  ] };
  const asset = pickWindowsAsset(release);
  assert.equal(asset.url, "u2");
  assert.equal(asset.sha256, "b".repeat(64));
  assert.throws(() => pickWindowsAsset({ assets: [{ name: "ffmpeg-7.1-essentials_build.zip", browser_download_url: "u", digest: "" }] }), /SHA-256/);
  assert.throws(() => pickWindowsAsset({ assets: [] }), /essentials/);
});

function worker(request, support) {
  const run = spawnSync(process.execPath, [BRIDGE], { input: JSON.stringify(request), encoding: "utf8", env: { ...process.env, SAVESTORIES_APP_SUPPORT: support }, timeout: 180_000 });
  const lines = (run.stderr ?? "").split("\n").filter((l) => l.startsWith("unik_"));
  return { response: JSON.parse(run.stdout), progress: lines };
}

test("команда unik_status отдаёт состояние FFmpeg и каталог", realFfmpeg, () => {
  const support = fs.mkdtempSync(path.join(os.tmpdir(), "unik-support-"));
  try {
    const { response } = worker({ command: "unik_status" }, support);
    assert.equal(response.ok, true);
    assert.equal(response.data.ffmpegInstalled, "true");
    const catalog = JSON.parse(response.data.catalog);
    assert.equal(catalog.formatPresets.length, 5);
    assert.equal(catalog.stylePresets.length, 8);
    assert.equal(catalog.ageMarkGeos.length, 9);
  } finally {
    fs.rmSync(support, { recursive: true, force: true });
  }
});

test("настоящая обработка: 3 вариации с плашкой 18+, проверка результата ffprobe", realFfmpeg, async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "unik-e2e-"));
  try {
    const source = path.join(dir, "clip.mp4");
    execFileSync(located.ffmpeg, ["-y", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=25:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", source], { stdio: "ignore" });
    const outDir = path.join(dir, "out");
    const { response, progress } = worker({
      command: "unik_process", sources: [source], outputDirectory: outDir,
      options: {
        formatPresetId: "meta-story",
        variations: { count: 3, styleIds: ["soft", "cinematic", "bright"] },
        ageMark: { enabled: true, geoId: "de-germany", position: "bottom" },
        naming: { mode: "structured", geo: "DE", presetToken: "meta", versionToken: "v1" },
        bitrate: "1.5M",
      },
    }, dir);
    assert.equal(response.ok, true, response.message);
    assert.equal(response.status, "unik_complete");
    assert.equal(response.data.done, "3");
    const results = JSON.parse(response.data.results);
    assert.deepEqual(results.map((r) => path.basename(r.outputPath)), ["DE_meta_9x16_v1.mp4", "DE_meta_9x16_v2.mp4", "DE_meta_9x16_v3.mp4"]);
    for (const result of results) {
      const info = await inspectMedia(located.ffprobe, result.outputPath);
      assert.equal(info.width, 1080);
      assert.equal(info.height, 1920);
      assert.equal(info.videoCodec, "h264");
      assert.equal(info.hasAudio, true);
      assert.ok(info.durationSeconds > 1.5 && info.durationSeconds < 3.5, `длительность ${info.durationSeconds}`);
    }
    assert.ok(progress.includes("unik_total=3"));
    assert.ok(progress.some((l) => /^unik_job_2_done=/.test(l)));
    // «Кино» замедляет (+900 мс), «Яркий» ускоряет (−500 мс) относительно «Мягкого»
    const durations = await Promise.all(results.map((r) => inspectMedia(located.ffprobe, r.outputPath).then((i) => i.durationSeconds)));
    assert.ok(durations[1] > durations[0] && durations[2] < durations[0], `длительности ${durations}`);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("обработка картинки и файл с ошибкой не мешают остальным", realFfmpeg, async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "unik-e2e-img-"));
  try {
    const picture = path.join(dir, "pic.png");
    execFileSync(located.ffmpeg, ["-y", "-f", "lavfi", "-i", "testsrc=size=400x400:rate=1:duration=1", "-frames:v", "1", picture], { stdio: "ignore" });
    const broken = path.join(dir, "broken.mp4");
    fs.writeFileSync(broken, "это не видео");
    const { response } = worker({ command: "unik_process", sources: [picture, broken], outputDirectory: path.join(dir, "out"), options: { formatPresetId: "meta-square", naming: { mode: "source-random" } } }, dir);
    assert.equal(response.ok, true, response.message);
    assert.equal(response.data.done, "1");
    assert.equal(response.data.failed, "1");
    const results = JSON.parse(response.data.results);
    const good = results.find((r) => r.status === "completed");
    assert.ok(good.outputPath.endsWith(".png"));
    const info = await inspectMedia(located.ffprobe, good.outputPath);
    assert.equal(info.width, 1080);
    assert.equal(info.kind, "image");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("без FFmpeg команды отвечают понятной ошибкой", () => {
  const support = fs.mkdtempSync(path.join(os.tmpdir(), "unik-nof-"));
  try {
    const run = spawnSync(process.execPath, [BRIDGE], { input: JSON.stringify({ command: "unik_process", sources: ["x"], outputDirectory: support }), encoding: "utf8", env: { ...process.env, PATH: "", Path: "", SAVESTORIES_APP_SUPPORT: support }, timeout: 60_000 });
    const response = JSON.parse(run.stdout);
    assert.equal(response.ok, false);
    assert.equal(response.status, "unik_ffmpeg_missing");
    assert.match(response.message, /Установить FFmpeg/);
  } finally {
    fs.rmSync(support, { recursive: true, force: true });
  }
});
