import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { buildAtempoFilter, buildExecutionPlan, buildOutputPath, resolveAgeMarkPath } from "./unik_plan.mjs";

// Эталон получен прогоном исходного кода сервиса n1.unikalizator (packages/processing-core) на тех же заданиях.
const parity = JSON.parse(fs.readFileSync(new URL("./test_fixtures/unik_plan_parity.json", import.meta.url), "utf8"));

for (const [name, { job, ffmpegArgs }] of Object.entries(parity)) {
  test(`аргументы FFmpeg совпадают с онлайн-сервисом: ${name}`, () => {
    const plan = buildExecutionPlan(job, `/out/${name}.${job.output.container}`, { threads: 2 });
    assert.deepEqual(plan.ffmpegArgs, ffmpegArgs);
  });
}

test("шаги плана описывают включённые преобразования", () => {
  const plan = buildExecutionPlan({
    input: { filePath: "/in/a.mp4", mediaKind: "video" },
    output: { container: "mp4", videoCodec: "h264", audioCodec: "aac" },
    transforms: { resize: { width: 1080, height: 1920, fit: "contain", backgroundStyle: "blur" }, hueShift: 8, speedFactor: 0.8, audioNormalize: true, stripMetadata: true, fps: 30 },
  }, "/out/a.mp4");
  const text = plan.steps.map((s) => s.description).join("\n");
  assert.match(text, /размытая копия/);
  assert.match(text, /Сдвиг оттенка/);
  assert.match(text, /Скорость/);
  assert.match(text, /Метаданные удалены/);
});

test("плашка 18+ выбирается по соотношению сторон", () => {
  const files = { enabled: true, portraitFilePath: "p", squareFilePath: "s", fourByFiveFilePath: "f" };
  const job = (width, height) => ({ transforms: { ageMark: files, resize: { width, height } } });
  assert.equal(resolveAgeMarkPath(job(1080, 1920)), "p");
  assert.equal(resolveAgeMarkPath(job(1080, 1350)), "f");
  assert.equal(resolveAgeMarkPath(job(1080, 1080)), "s");
  assert.equal(resolveAgeMarkPath(job(1200, 628)), "s");
  assert.equal(resolveAgeMarkPath({ transforms: { ageMark: { ...files, enabled: false } } }), null);
});

test("ускорение звука разбивается на допустимые atempo", () => {
  assert.equal(buildAtempoFilter(1.5), "atempo=1.5000");
  assert.equal(buildAtempoFilter(4), "atempo=2,atempo=2.0000");
  assert.equal(buildAtempoFilter(0.25), "atempo=0.5,atempo=0.5000");
});

test("путь результата по умолчанию", () => {
  assert.equal(buildOutputPath("/a/b/clip.mov", "mp4", "x"), "/a/b/clip.processed_x.mp4");
});
