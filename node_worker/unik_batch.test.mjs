import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { UnikRequestError, normalizeOptions, planBatch, validateOptions } from "./unik_batch.mjs";
import { AGE_MARK_GEOS, AGE_MARKS_DIRECTORY, STYLE_PRESETS, ageMarkFiles, buildSizeToken } from "./unik_catalog.mjs";
import fs from "node:fs";
import { execFileSync } from "node:child_process";

const everythingExists = () => true;
const out = path.join("/out");
const video = (name, durationSeconds = 10) => ({ path: `/in/${name}`, kind: "video", durationSeconds });
const plan = (request, extra = {}) => planBatch({ outputDirectory: out, ...request }, { exists: (p) => (p.startsWith("/out") ? false : true), random: () => 0, ...extra });

test("метки 18+ из каталога существуют для всех стран и положений", () => {
  for (const geo of AGE_MARK_GEOS) {
    for (const position of ["top", "bottom"]) {
      const files = ageMarkFiles(geo.id, position);
      for (const file of Object.values(files)) assert.ok(fs.existsSync(file), `нет файла ${file}`);
    }
  }
  assert.ok(AGE_MARKS_DIRECTORY.includes("unik_assets"));
});

test("один файл, один вариант, структурное имя: ГЕО_пресет_размер_версия", () => {
  const [job] = plan({ sources: [video("a.mp4")], options: { naming: { mode: "structured", geo: "au", presetToken: "instagram", versionToken: "v1" } } });
  assert.equal(path.basename(job.outputPath), "au_instagram_9x16_v1.mp4");
  assert.equal(job.job.transforms.hueShift, 0);
});

test("несколько вариаций: стили по слотам и сквозные версии", () => {
  const jobs = plan({ sources: [video("a.mp4")], options: { variations: { count: 3, styleIds: ["soft", "cinematic", "bright"] }, naming: { mode: "structured", geo: "DE", presetToken: "meta", versionToken: "v1" } } });
  assert.deepEqual(jobs.map((j) => path.basename(j.outputPath)), ["DE_meta_9x16_v1.mp4", "DE_meta_9x16_v2.mp4", "DE_meta_9x16_v3.mp4"]);
  assert.deepEqual(jobs.map((j) => j.style), ["soft", "cinematic", "bright"]);
  const soft = STYLE_PRESETS.find((s) => s.id === "soft");
  assert.equal(jobs[0].job.transforms.hueShift, soft.hueShift);
  assert.equal(jobs[0].job.transforms.speedFactor, undefined);
  // «Кино» замедляет на 900 мс: коэффициент = 10 / 10.9
  assert.equal(jobs[1].job.transforms.speedFactor, Number((10 / 10.9).toFixed(4)));
  assert.ok(jobs[2].job.transforms.speedFactor > 1);
});

test("режим «пресет на файл»: по одному результату на файл, стили по кругу", () => {
  const jobs = plan({ sources: [video("a.mp4"), video("b.mp4"), video("c.mp4")], options: { variations: { count: 2, styleIds: ["soft", "calm"], mode: "preset-per-file" } } });
  assert.equal(jobs.length, 3);
  assert.deepEqual(jobs.map((j) => j.style), ["soft", "calm", "soft"]);
});

test("имя «исходное + случайный хвост» и защита от перезаписи", () => {
  const taken = new Set([path.join("/out", "clip_AAAAAAAA.mp4")]);
  const jobs = plan({ sources: [video("clip.mp4")], options: { naming: { mode: "source-random" } } }, { exists: (p) => taken.has(p) || (!p.startsWith("/out")), random: () => 0 });
  assert.equal(path.basename(jobs[0].outputPath), "clip_AAAAAAAA_2.mp4");
});

test("картинки не получают скорость, заставку и видео-слой, а контейнер берётся из исходника", () => {
  const [job] = plan({ sources: [{ path: "/in/pic.PNG", kind: "image" }], options: { intro: { enabled: true, imagePath: "/m/i.png" }, overlay: { enabled: true, videoPath: "/m/o.mp4" }, variations: { count: 1, styleIds: ["cinematic"] } } });
  assert.equal(job.job.output.container, "png");
  assert.equal(job.job.transforms.speedFactor, undefined);
  assert.equal(job.job.transforms.introImage.enabled, false);
  assert.equal(job.job.transforms.videoOverlay.enabled, false);
  assert.ok(job.outputPath.endsWith(".png"));
});

test("плашка 18+ по стране и положению подставляет три файла, а в плане нужный файл", () => {
  const [job] = plan({ sources: [video("a.mp4")], options: { formatPresetId: "meta-feed-4x5", ageMark: { enabled: true, geoId: "gb-great-britain", position: "top" } } });
  assert.match(job.job.transforms.ageMark.fourByFiveFilePath, /gb_four_by_five_top\.png$/);
  assert.ok(job.plan.ffmpegArgs.some((a) => /gb_four_by_five_top\.png$/.test(a)));
});

test("случайная заставка и видео-слой берутся из набора", () => {
  const [job] = plan({ sources: [video("a.mp4")], options: { intro: { enabled: true, random: true, library: ["/m/1.png", "/m/2.png"] }, overlay: { enabled: true, random: true, library: ["/m/a.mp4", "/m/b.mp4"], opacity: 0.4 } } }, { random: () => 0.9 });
  assert.equal(job.job.transforms.introImage.imageFilePath, "/m/2.png");
  assert.equal(job.job.transforms.videoOverlay.videoFilePath, "/m/b.mp4");
  assert.equal(job.job.transforms.videoOverlay.opacity, 0.4);
});

test("ручные настройки применяются только к одиночному результату", () => {
  const manual = { enabled: true, hueShift: 20, saturation: 1.4, sharpness: 0.5, speedOffsetMs: 500 };
  const [single] = plan({ sources: [video("a.mp4")], options: { manual } });
  assert.equal(single.job.transforms.hueShift, 20);
  const several = plan({ sources: [video("a.mp4")], options: { manual, variations: { count: 2, styleIds: ["soft", "warm"] } } });
  assert.equal(several[0].job.transforms.hueShift, STYLE_PRESETS.find((s) => s.id === "soft").hueShift);
});

test("яркость, контраст и отражение применяются ко всем вариациям и ограничены диапазоном", () => {
  const adjust = { brightness: 0.1, contrast: 1.2, horizontalFlip: true };
  const several = plan({ sources: [video("a.mp4")], options: { adjust, variations: { count: 2, styleIds: ["soft", "warm"] } } });
  for (const item of several) {
    assert.equal(item.job.transforms.brightness, 0.1);
    assert.equal(item.job.transforms.contrast, 1.2);
    assert.equal(item.job.transforms.horizontalFlip, true);
  }
  const [plain] = plan({ sources: [video("a.mp4")], options: {} });
  assert.equal("brightness" in plain.job.transforms, false);
  assert.equal("horizontalFlip" in plain.job.transforms, false);
  assert.deepEqual(normalizeOptions({ adjust: { brightness: 9, contrast: 0.1 } }).adjust, { brightness: 0.25, contrast: 0.5, horizontalFlip: false });
});

test("проверка настроек возвращает понятные ошибки", () => {
  const bad = normalizeOptions({ resize: { width: 1081, height: 1920, fit: "cover" }, ageMark: { enabled: true }, metadata: { mode: "custom-date", customDate: "2026-02-31" }, intro: { enabled: true, random: true, library: [] } });
  const errors = validateOptions(bad, { exists: everythingExists });
  assert.ok(errors.some((e) => e.includes("чётными")));
  assert.ok(errors.some((e) => e.includes("плашки 18+")));
  assert.ok(errors.some((e) => e.includes("существующую дату")));
  assert.ok(errors.some((e) => e.includes("наборе заставок")));
  assert.throws(() => plan({ sources: [], options: {} }), UnikRequestError);
  assert.throws(() => plan({ sources: [video("a.mp4")], options: { ageMark: { enabled: true } } }), /плашки 18\+/);
});

test("токен размера для типичных форматов", () => {
  assert.equal(buildSizeToken(1080, 1920), "9x16");
  assert.equal(buildSizeToken(1080, 1080), "1x1");
  assert.equal(buildSizeToken(1080, 1350), "4x5");
  assert.equal(buildSizeToken(1200, 628), "191x1");
  assert.equal(buildSizeToken(1920, 1080), "16x9");
  assert.equal(buildSizeToken(800, 700), "800x700");
});

test("плашка стоит там, где выбрано: проверка пикселей всех шаблонов", { skip: (() => { try { execFileSync("ffmpeg", ["-version"], { stdio: "ignore" }); return false; } catch { return "ffmpeg не найден"; } })() }, () => {
  const W = 54;
  const H = 96;
  const placement = (file) => {
    const raw = execFileSync("ffmpeg", ["-v", "error", "-i", file, "-vf", `format=rgba,scale=${W}:${H}`, "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { maxBuffer: 1 << 24 });
    let top = 0;
    let bottom = 0;
    for (let y = 0; y < H; y += 1) {
      let opaque = 0;
      for (let x = 0; x < W; x += 1) if (raw[(y * W + x) * 4 + 3] > 40) opaque += 1;
      if (y < H / 2) top += opaque; else bottom += opaque;
    }
    return top > bottom ? "top" : "bottom";
  };
  for (const geo of AGE_MARK_GEOS) {
    for (const position of ["top", "bottom"]) {
      const files = ageMarkFiles(geo.id, position);
      for (const [shape, file] of Object.entries(files)) assert.equal(placement(file), position, `${geo.id} ${shape} ${position}`);
    }
  }
});
