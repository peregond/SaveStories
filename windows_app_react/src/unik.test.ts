import { describe, expect, it } from "vitest";
import { MAX_PRESETS, applyUnikLine, defaultOptions, describeInspection, isMedia, loadOptions, loadPresets, optionProblems, parseUnikLine, plannedOutputs, previewName, removePreset, sizeToken, toWorkerOptions, upsertPreset } from "./unik";

describe("настройки", () => {
  it("читаются поверх значений по умолчанию, лишнее и испорченное отбрасывается", () => {
    const saved = JSON.stringify({ bitrate: "4M", fps: null, resize: { width: 1080, height: 1350 }, variations: { count: 3, styleIds: ["soft"] }, ageMark: { enabled: true, geoId: "de-germany" }, junk: 1, audio: "не объект" });
    const o = loadOptions(saved, "2026-11-06");
    expect(o.bitrate).toBe("4M");
    expect(o.fps).toBeNull();
    expect(o.resize).toMatchObject({ width: 1080, height: 1350, fit: "cover" });
    expect(o.variations.styleIds).toEqual(["soft", "soft", "soft"]);
    expect(o.ageMark).toMatchObject({ enabled: true, geoId: "de-germany", position: "bottom" });
    expect(o.audio.normalize).toBe(true);
    expect(loadOptions("не json").formatPresetId).toBe("meta-story");
    expect(loadOptions("[]").variations.count).toBe(1);
  });
  it("число вариаций ограничено 1–5", () => {
    expect(loadOptions(JSON.stringify({ variations: { count: 99, styleIds: [] } })).variations.count).toBe(5);
    expect(loadOptions(JSON.stringify({ variations: { count: 0, styleIds: [] } })).variations.count).toBe(1);
  });
  it("fps «как есть» уходит воркеру нулём", () => {
    expect(toWorkerOptions({ ...defaultOptions(), fps: null }).fps).toBe(0);
    expect(toWorkerOptions(defaultOptions()).fps).toBe(30);
  });
});

describe("подсчёт и имена", () => {
  it("сколько файлов получится", () => {
    const o = defaultOptions();
    expect(plannedOutputs(0, o)).toBe(0);
    expect(plannedOutputs(3, { ...o, variations: { ...o.variations, count: 2 } })).toBe(6);
    expect(plannedOutputs(3, { ...o, variations: { count: 2, styleIds: ["clean", "soft"], mode: "preset-per-file" } })).toBe(3);
    expect(plannedOutputs(1, { ...o, variations: { count: 2, styleIds: ["clean", "soft"], mode: "preset-per-file" } })).toBe(2);
  });
  it("пример имени совпадает со схемой воркера", () => {
    const o = { ...defaultOptions(), naming: { mode: "structured" as const, geo: "au", presetToken: "insta gram", versionToken: "v3", randomTail: "" } };
    expect(previewName(o, "a.mp4", 1)).toBe("au_instagram_9x16_v3.mp4");
    expect(previewName(o, "a.mp4", 3, 2)).toBe("au_instagram_9x16_v5.mp4");
    expect(previewName({ ...o, naming: { ...o.naming, mode: "source-random", randomTail: "Qwe 12" } }, "C:\\x\\clip.mov", 1)).toBe("clip_Qwe12.mp4");
    expect(previewName(o, "pic.jpeg", 1)).toBe("au_instagram_9x16_v3.jpg");
    expect(sizeToken(1200, 628)).toBe("191x1");
    expect(sizeToken(800, 700)).toBe("800x700");
  });
});

describe("проверка до запуска", () => {
  it("называет причины", () => {
    const o = defaultOptions("2026-11-06");
    expect(optionProblems(o, 0)).toEqual(["Добавьте хотя бы один файл."]);
    expect(optionProblems(o, 2)).toEqual([]);
    const bad = { ...o, resize: { ...o.resize, width: 1081 }, ageMark: { ...o.ageMark, enabled: true }, intro: { ...o.intro, enabled: true }, overlay: { ...o.overlay, enabled: true, random: true }, metadata: { mode: "custom-date" as const, customDate: "" } };
    const text = optionProblems(bad, 1).join("|");
    for (const part of ["чётными", "страну", "заставки", "видео-слоёв", "дату"]) expect(text).toContain(part);
  });
  it("распознаёт поддерживаемые файлы", () => {
    expect(isMedia("C:\\a\\b.MP4")).toBe(true);
    expect(isMedia("x.webp")).toBe(true);
    expect(isMedia("doc.pdf")).toBe(false);
  });
});

describe("строки прогресса воркера", () => {
  it("разбираются", () => {
    expect(parseUnikLine("unik_total=4")).toEqual({ kind: "total", total: 4 });
    expect(parseUnikLine("unik_job_2_start=a.mp4 → b.mp4")).toEqual({ kind: "job", index: 2, phase: "start", value: "a.mp4 → b.mp4" });
    expect(parseUnikLine("unik_job_0_error=FFmpeg завершился с кодом 1.")).toMatchObject({ phase: "error" });
    expect(parseUnikLine("unik_ffmpeg_progress=42")).toEqual({ kind: "ffmpeg-progress", percent: 42 });
    expect(parseUnikLine("unik_ffmpeg_message=Распаковываю…")).toEqual({ kind: "ffmpeg-message", text: "Распаковываю…" });
    expect(parseUnikLine("batch_slot_1_start=x")).toBeNull();
  });
  it("обновляют список заданий", () => {
    let jobs = applyUnikLine([], { kind: "total", total: 2 });
    expect(jobs.map((j) => j.status)).toEqual(["queued", "queued"]);
    jobs = applyUnikLine(jobs, { kind: "job", index: 0, phase: "start", value: "a → b" });
    jobs = applyUnikLine(jobs, { kind: "job", index: 0, phase: "progress", value: "55" });
    expect(jobs[0]).toMatchObject({ status: "running", percent: 55, label: "a → b" });
    jobs = applyUnikLine(jobs, { kind: "job", index: 0, phase: "done", value: "C:\\out\\b.mp4" });
    jobs = applyUnikLine(jobs, { kind: "job", index: 1, phase: "error", value: "сбой" });
    expect(jobs[0]).toMatchObject({ status: "done", percent: 100, outputPath: "C:\\out\\b.mp4" });
    expect(jobs[1]).toMatchObject({ status: "error", message: "сбой" });
  });
  it("описание проверенного файла", () => {
    expect(describeInspection({ ok: true, filePath: "a", kind: "video", width: 720, height: 1280, durationSeconds: 75, hasAudio: false })).toBe("720×1280 · 1:15 · без звука");
    expect(describeInspection({ ok: false, filePath: "a", message: "битый" })).toBe("битый");
  });
});

describe("свои пресеты", () => {
  const base = defaultOptions("2026-01-01");

  it("сохраняет, заменяет одноимённый без учёта регистра и убирает лишние пробелы", () => {
    let list = upsertPreset([], "  Reels   DE  ", { ...base, fps: 60 });
    expect(list.map((p) => p.name)).toEqual(["Reels DE"]);
    list = upsertPreset(list, "reels de", { ...base, fps: 25 });
    expect(list).toHaveLength(1);
    expect(list[0].name).toBe("reels de");
    expect(list[0].options.fps).toBe(25);
    expect(upsertPreset(list, "   ", base)).toBe(list);
  });

  it("копирует настройки: дальнейшие правки не меняют сохранённое", () => {
    const options = defaultOptions("2026-01-01");
    const list = upsertPreset([], "A", options);
    options.fps = 24;
    expect(list[0].options.fps).toBe(30);
  });

  it("удаляет по имени и ограничивает число наборов", () => {
    let list = upsertPreset(upsertPreset([], "A", base), "B", base);
    expect(removePreset(list, "a").map((p) => p.name)).toEqual(["B"]);
    list = [];
    for (let i = 0; i < MAX_PRESETS + 5; i += 1) list = upsertPreset(list, `P${i}`, base);
    expect(list).toHaveLength(MAX_PRESETS);
  });

  it("читает сохранённый JSON и отбрасывает мусор, включая «как есть» для FPS", () => {
    const saved = JSON.stringify([
      { name: "Good", options: { fps: null, bitrate: "4M" } },
      { name: "good", options: {} },
      { name: "", options: {} },
      { options: {} },
      "строка",
    ]);
    const list = loadPresets(saved, "2026-01-01");
    expect(list.map((p) => p.name)).toEqual(["Good"]);
    expect(list[0].options.fps).toBeNull();
    expect(list[0].options.bitrate).toBe("4M");
    expect(loadPresets("не json")).toEqual([]);
    expect(loadPresets("{}")).toEqual([]);
    expect(loadPresets("")).toEqual([]);
  });

  it("круг «сохранить → записать в настройки → прочитать» возвращает те же настройки", () => {
    const options = { ...base, ageMark: { enabled: true, geoId: "de-germany", position: "top" as const }, variations: { count: 3, styleIds: ["soft", "bright", "calm"], mode: "all-variations" as const } };
    const json = JSON.stringify(upsertPreset([], "DE 18+", options));
    expect(loadPresets(json, "2026-01-01")[0].options).toEqual(options);
  });
});
