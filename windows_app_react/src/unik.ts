// Состояние раздела «Уникализатор». Сама обработка (FFmpeg, вариации, имена) — в общем воркере node_worker/unik_*.mjs;
// здесь только настройки, список файлов и разбор строк прогресса.

import { useCallback, useEffect, useRef, useState, type MutableRefObject } from "react";
import type { Api, Settings } from "./api";

export const VIDEO_EXT = ["mp4", "mov", "m4v", "webm", "mkv", "avi"];
export const IMAGE_EXT = ["png", "jpg", "jpeg", "webp"];
export const MEDIA_EXT = [...VIDEO_EXT, ...IMAGE_EXT];
export const AUDIO_EXT = ["mp3", "m4a", "aac", "wav", "ogg", "flac"];

export const extOf = (path: string) => (path.split(".").pop() ?? "").toLowerCase();
export const baseName = (path: string) => path.split(/[\\/]/).pop() ?? path;
export const isMedia = (path: string) => MEDIA_EXT.includes(extOf(path));
export const isImage = (path: string) => IMAGE_EXT.includes(extOf(path));

// ---------------------------------------------------------------- каталог из воркера

export interface FormatPreset { id: string; name: string; description: string; resize: { width: number; height: number; fit: "cover" | "contain"; backgroundStyle: string; backgroundColor: string }; fps: number; bitrate: string }
export interface StylePreset { id: string; label: string; hint: string; hueShift: number; saturation: number; sharpness: number; speedOffsetMs: number }
export interface UnikCatalog {
  formatPresets: FormatPreset[]; stylePresets: StylePreset[]; fpsOptions: number[]; variationOptions: number[];
  bitrateOptions: { value: string; label: string; hint: string }[]; ageMarkGeos: { id: string; name: string }[];
}

// ---------------------------------------------------------------- настройки

export type FitMode = "cover" | "contain";
export type BackgroundStyle = "bars" | "blur" | "solid";
export type MetadataMode = "strip" | "export-date" | "custom-date";

export interface UnikOptions {
  formatPresetId: string; // "custom" — свой размер
  resize: { width: number; height: number; fit: FitMode; backgroundStyle: BackgroundStyle; backgroundColor: string };
  fps: number | null;
  bitrate: string;
  variations: { count: number; styleIds: string[]; mode: "all-variations" | "preset-per-file" };
  manual: { enabled: boolean; hueShift: number; saturation: number; sharpness: number; speedOffsetMs: number };
  ageMark: { enabled: boolean; geoId: string; position: "top" | "bottom" };
  intro: { enabled: boolean; imagePath: string; durationMs: number; random: boolean; library: string[] };
  overlay: { enabled: boolean; videoPath: string; opacity: number; random: boolean; library: string[] };
  audio: { normalize: boolean; replacePath: string };
  metadata: { mode: MetadataMode; customDate: string };
  naming: { mode: "structured" | "source-random"; geo: string; presetToken: string; versionToken: string; randomTail: string };
}

export const todayIso = (now = new Date()) => `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

export function defaultOptions(today = todayIso()): UnikOptions {
  return {
    formatPresetId: "meta-story",
    resize: { width: 1080, height: 1920, fit: "cover", backgroundStyle: "bars", backgroundColor: "#111111" },
    fps: 30, bitrate: "2M",
    variations: { count: 1, styleIds: ["clean"], mode: "all-variations" },
    manual: { enabled: false, hueShift: 0, saturation: 1, sharpness: 0, speedOffsetMs: 0 },
    ageMark: { enabled: false, geoId: "", position: "bottom" },
    intro: { enabled: false, imagePath: "", durationMs: 500, random: false, library: [] },
    overlay: { enabled: false, videoPath: "", opacity: 0.25, random: false, library: [] },
    audio: { normalize: true, replacePath: "" },
    metadata: { mode: "strip", customDate: today },
    naming: { mode: "structured", geo: "", presetToken: "", versionToken: "v1", randomTail: "" },
  };
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** Настройки из сохранённого JSON поверх значений по умолчанию: лишнее и испорченное отбрасывается. */
export function loadOptions(json: string, today = todayIso()): UnikOptions {
  const base = defaultOptions(today);
  let raw: unknown;
  try { raw = JSON.parse(json); } catch { return base; }
  if (!isObject(raw)) return base;
  const merged = { ...base };
  if (raw.fps === null || typeof raw.fps === "number") merged.fps = raw.fps; // null — «как есть», это сохранённый выбор
  for (const key of Object.keys(base) as Array<keyof UnikOptions>) {
    const value = raw[key];
    if (key === "fps" || value === undefined || value === null) continue;
    if (isObject(base[key]) && isObject(value)) (merged as Record<string, unknown>)[key] = { ...(base[key] as object), ...value };
    else if (!isObject(base[key]) && typeof value === typeof base[key]) (merged as Record<string, unknown>)[key] = value;
  }
  const count = Math.min(5, Math.max(1, Math.round(Number(merged.variations.count)) || 1));
  merged.variations = { ...merged.variations, count, styleIds: Array.from({ length: count }, (_, i) => String(merged.variations.styleIds?.[i] ?? merged.variations.styleIds?.[0] ?? "clean")) };
  return merged;
}

/** Сколько файлов получится на выходе (как в воркере). */
export function plannedOutputs(fileCount: number, o: UnikOptions): number {
  if (fileCount <= 0) return 0;
  return o.variations.mode === "preset-per-file" && fileCount > 1 ? fileCount : fileCount * o.variations.count;
}

export function sizeToken(width: number, height: number): string {
  if (!width || !height) return "custom";
  const r = width / height;
  if (Math.abs(r - 9 / 16) < 0.02) return "9x16";
  if (Math.abs(r - 1) < 0.02) return "1x1";
  if (Math.abs(r - 4 / 5) < 0.02) return "4x5";
  if (Math.abs(r - 1.91) < 0.03) return "191x1";
  if (Math.abs(r - 16 / 9) < 0.02) return "16x9";
  return `${width}x${height}`;
}

const slug = (v: string) => v.trim().replace(/[^a-zA-Z0-9]+/g, "").replace(/^_+|_+$/g, "");

/** Пример имени результата для подсказки под полями названия. */
export function previewName(o: UnikOptions, firstFile: string, outputs: number, index = 0): string {
  const ext = firstFile && isImage(firstFile) ? extOf(firstFile).replace("jpeg", "jpg") : "mp4";
  if (o.naming.mode === "source-random") {
    const stem = firstFile ? baseName(firstFile).replace(/\.[^.]+$/, "") : "result";
    return `${stem}_${o.naming.randomTail ? slug(o.naming.randomTail) : "Asdc56Dg"}.${ext}`;
  }
  const start = Number(/(\d+)$/.exec(o.naming.versionToken)?.[1] ?? 1) || 1;
  const version = outputs > 1 ? `v${start + index}` : o.naming.versionToken;
  const stem = [o.naming.geo, o.naming.presetToken, sizeToken(o.resize.width, o.resize.height), version].map(slug).filter(Boolean).join("_");
  return `${stem || "result"}.${ext}`;
}

/** Проверка до запуска: понятные причины, почему кнопка «Создать» недоступна. */
export function optionProblems(o: UnikOptions, fileCount: number): string[] {
  const problems: string[] = [];
  if (!fileCount) problems.push("Добавьте хотя бы один файл.");
  const { width, height } = o.resize;
  if (!(width >= 2 && height >= 2) || width > 8192 || height > 8192) problems.push("Размер кадра — от 2 до 8192 пикселей.");
  else if (width % 2 || height % 2) problems.push("Ширина и высота должны быть чётными.");
  if (o.ageMark.enabled && !o.ageMark.geoId) problems.push("Выберите страну для плашки 18+.");
  if (o.intro.enabled && !o.intro.random && !o.intro.imagePath) problems.push("Выберите картинку для заставки.");
  if (o.intro.enabled && o.intro.random && !o.intro.library.length) problems.push("В наборе заставок нет файлов.");
  if (o.overlay.enabled && !o.overlay.random && !o.overlay.videoPath) problems.push("Выберите видео для слоя поверх.");
  if (o.overlay.enabled && o.overlay.random && !o.overlay.library.length) problems.push("В наборе видео-слоёв нет файлов.");
  if (o.metadata.mode === "custom-date" && !/^\d{4}-\d{2}-\d{2}$/.test(o.metadata.customDate)) problems.push("Укажите дату в метаданных.");
  return problems;
}

/** Запрос воркеру: заставка и слой выключаются, если не выбраны; «без FPS» → 0. */
export function toWorkerOptions(o: UnikOptions) {
  return { ...o, fps: o.fps ?? 0 };
}

// ---------------------------------------------------------------- строки прогресса

export type UnikLine =
  | { kind: "total"; total: number }
  | { kind: "job"; index: number; phase: "start" | "progress" | "done" | "error"; value: string }
  | { kind: "ffmpeg-progress"; percent: number }
  | { kind: "ffmpeg-message"; text: string };

export function parseUnikLine(line: string): UnikLine | null {
  let m = /^unik_total=(\d+)$/.exec(line);
  if (m) return { kind: "total", total: Number(m[1]) };
  m = /^unik_job_(\d+)_(start|progress|done|error)=(.*)$/.exec(line);
  if (m) return { kind: "job", index: Number(m[1]), phase: m[2] as "start" | "progress" | "done" | "error", value: m[3] };
  m = /^unik_ffmpeg_progress=(\d+)$/.exec(line);
  if (m) return { kind: "ffmpeg-progress", percent: Number(m[1]) };
  m = /^unik_ffmpeg_message=(.*)$/.exec(line);
  if (m) return { kind: "ffmpeg-message", text: m[1] };
  return null;
}

export interface UnikJob { index: number; label: string; percent: number; status: "queued" | "running" | "done" | "error"; outputPath: string; message: string }

export function applyUnikLine(jobs: UnikJob[], line: UnikLine): UnikJob[] {
  if (line.kind === "total") return Array.from({ length: line.total }, (_, index) => ({ index, label: "", percent: 0, status: "queued" as const, outputPath: "", message: "" }));
  if (line.kind !== "job") return jobs;
  const next = jobs.slice();
  while (next.length <= line.index) next.push({ index: next.length, label: "", percent: 0, status: "queued", outputPath: "", message: "" });
  const job = { ...next[line.index] };
  if (line.phase === "start") { job.status = "running"; job.label = line.value; job.percent = 0; }
  else if (line.phase === "progress") { job.percent = Number(line.value) || 0; }
  else if (line.phase === "done") { job.status = "done"; job.percent = 100; job.outputPath = line.value; }
  else { job.status = "error"; job.message = line.value; }
  next[line.index] = job;
  return next;
}

// ---------------------------------------------------------------- хук

export interface UnikFile { path: string; name: string; image: boolean; ok: boolean; info: string }
interface Inspection { ok: boolean; filePath: string; kind?: string; durationSeconds?: number | null; width?: number | null; height?: number | null; hasAudio?: boolean; message?: string }

export interface UnikContext {
  api: Api;
  settingsRef: MutableRefObject<Settings>;
  updateSettings: (patch: Partial<Settings>) => void;
  busy: string | null;
  setBusy: (b: "unik" | null) => void;
  setNotice: (n: { tone: "ok" | "err" | "warn"; text: string } | null) => void;
  pushLog: (line: string) => void;
}

export type FfmpegState = { phase: "unknown" | "missing" | "ready" | "installing" | "error"; version: string; percent: number; message: string };

const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e));
const formatDuration = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;

export function describeInspection(i: Inspection): string {
  if (!i.ok) return i.message ?? "Файл не удалось прочитать.";
  const parts = [i.width && i.height ? `${i.width}×${i.height}` : "", i.kind === "video" && i.durationSeconds ? formatDuration(i.durationSeconds) : "", i.kind === "video" ? (i.hasAudio ? "со звуком" : "без звука") : "картинка"];
  return parts.filter(Boolean).join(" · ");
}

export function useUnik(ctx: UnikContext) {
  const ctxRef = useRef(ctx);
  ctxRef.current = ctx;
  const [catalog, setCatalog] = useState<UnikCatalog | null>(null);
  const [ffmpeg, setFfmpeg] = useState<FfmpegState>({ phase: "unknown", version: "", percent: 0, message: "" });
  const [files, setFiles] = useState<UnikFile[]>([]);
  const [options, setOptionsState] = useState<UnikOptions>(() => defaultOptions());
  const [jobs, setJobs] = useState<UnikJob[]>([]);
  const [summary, setSummary] = useState("");
  const [lastOutputDirectory, setLastOutputDirectory] = useState("");
  const loadedOptions = useRef(false);
  const saveTimer = useRef<number | undefined>(undefined);
  const jobsRef = useRef<UnikJob[]>([]);

  // Настройки читаются один раз, когда приложение загрузило сохранённое состояние.
  const loadSaved = useCallback((json: string) => {
    if (loadedOptions.current) return;
    loadedOptions.current = true;
    setOptionsState(loadOptions(json));
  }, []);

  const setOptions = useCallback((update: (o: UnikOptions) => UnikOptions) => {
    setOptionsState((current) => {
      const next = update(current);
      window.clearTimeout(saveTimer.current);
      saveTimer.current = window.setTimeout(() => ctxRef.current.updateSettings({ unikOptions: JSON.stringify(next) }), 600);
      return next;
    });
  }, []);

  const refresh = useCallback(async () => {
    try {
      const r = await ctxRef.current.api.run({ command: "unik_status" }, 60);
      if (r.data?.catalog) setCatalog(JSON.parse(r.data.catalog) as UnikCatalog);
      const ready = r.data?.ffmpegInstalled === "true";
      setFfmpeg((f) => (f.phase === "installing" ? f : { phase: ready ? "ready" : "missing", version: r.data?.ffmpegVersion ?? "", percent: 0, message: "" }));
    } catch (e) {
      setFfmpeg({ phase: "error", version: "", percent: 0, message: errorText(e) });
    }
  }, []);

  const installFfmpeg = useCallback(async () => {
    setFfmpeg({ phase: "installing", version: "", percent: 0, message: "Готовлюсь к установке…" });
    try {
      const r = await ctxRef.current.api.run({ command: "unik_install_ffmpeg" }, 30 * 60);
      if (!r.ok) throw new Error(r.message);
      setFfmpeg({ phase: "ready", version: r.data?.ffmpegVersion ?? "", percent: 100, message: "" });
      ctxRef.current.setNotice({ tone: "ok", text: r.message });
    } catch (e) {
      setFfmpeg({ phase: "error", version: "", percent: 0, message: errorText(e) });
    }
  }, []);

  const inspect = useCallback(async (paths: string[]) => {
    if (!paths.length) return;
    try {
      const r = await ctxRef.current.api.run({ command: "unik_inspect", files: paths }, 120);
      const list = JSON.parse(r.data?.inspections ?? "[]") as Inspection[];
      setFiles((current) => current.map((f) => {
        const found = list.find((i) => i.filePath === f.path);
        return found ? { ...f, ok: found.ok, info: describeInspection(found) } : f;
      }));
    } catch { /* подробности появятся при запуске */ }
  }, []);

  const addFiles = useCallback((paths: string[]) => {
    const media = paths.filter(isMedia);
    const rejected = paths.length - media.length;
    if (rejected > 0) ctxRef.current.setNotice({ tone: "warn", text: `Пропущено файлов неподдерживаемого типа: ${rejected}.` });
    if (!media.length) return;
    let added: string[] = [];
    setFiles((current) => {
      const known = new Set(current.map((f) => f.path.toLowerCase()));
      const fresh = media.filter((p, i) => !known.has(p.toLowerCase()) && media.findIndex((q) => q.toLowerCase() === p.toLowerCase()) === i);
      added = fresh;
      return [...current, ...fresh.map((p) => ({ path: p, name: baseName(p), image: isImage(p), ok: true, info: "" }))];
    });
    queueMicrotask(() => { if (ffmpegPhaseRef.current === "ready" && !ctxRef.current.busy) void inspect(added); });
  }, [inspect]);
  const ffmpegPhaseRef = useRef(ffmpeg.phase);
  ffmpegPhaseRef.current = ffmpeg.phase;

  const pickSources = useCallback(async () => {
    const picked = await ctxRef.current.api.pickFiles("Исходные видео и картинки", MEDIA_EXT, true);
    addFiles(picked);
  }, [addFiles]);

  const removeFile = useCallback((path: string) => setFiles((c) => c.filter((f) => f.path !== path)), []);
  const clearFiles = useCallback(() => setFiles([]), []);

  const effectiveOutput = useCallback(() => {
    const s = ctxRef.current.settingsRef.current;
    if (s.unikOutputDirectory) return s.unikOutputDirectory;
    return s.saveDirectory ? `${s.saveDirectory.replace(/[\\/]+$/, "")}\\Уникализатор` : "";
  }, []);

  const handleLine = useCallback((raw: string) => {
    const line = parseUnikLine(raw);
    if (!line) return;
    if (line.kind === "ffmpeg-progress") { setFfmpeg((f) => (f.phase === "installing" ? { ...f, percent: line.percent } : f)); return; }
    if (line.kind === "ffmpeg-message") { setFfmpeg((f) => (f.phase === "installing" ? { ...f, message: line.text } : f)); return; }
    jobsRef.current = applyUnikLine(jobsRef.current, line);
    setJobs(jobsRef.current);
  }, []);

  const run = useCallback(async () => {
    const c = ctxRef.current;
    if (c.busy) return;
    const output = effectiveOutput();
    if (!output) { c.setNotice({ tone: "warn", text: "Выберите папку для результата." }); return; }
    c.setBusy("unik"); c.setNotice(null);
    jobsRef.current = []; setJobs([]); setSummary("Запускаю обработку…");
    setLastOutputDirectory(output);
    try {
      const r = await c.api.run({ command: "unik_process", sources: files.map((f) => f.path), outputDirectory: output, options: toWorkerOptions(options) }, 6 * 3600);
      const results = JSON.parse(r.data?.results ?? "[]") as Array<{ index: number; outputPath: string; status: string; message: string }>;
      if (results.length) {
        const next = jobsRef.current.slice();
        for (const res of results) if (res.index >= 0 && next[res.index]) next[res.index] = { ...next[res.index], status: res.status === "completed" ? "done" : "error", percent: res.status === "completed" ? 100 : next[res.index].percent, outputPath: res.outputPath, message: res.message.split("\n")[0] };
        jobsRef.current = next; setJobs(next);
      }
      setSummary(r.message);
      if (r.status === "cancelled") c.setNotice({ tone: "warn", text: "Обработка остановлена." });
      else if (!r.ok) c.setNotice({ tone: "err", text: r.message });
      else c.setNotice({ tone: r.data?.failed && r.data.failed !== "0" ? "warn" : "ok", text: r.message });
    } catch (e) {
      setSummary(errorText(e));
      c.setNotice({ tone: "err", text: errorText(e) });
    } finally {
      c.setBusy(null);
    }
  }, [files, options, effectiveOutput]);

  const pickOutput = useCallback(async () => {
    const dir = await ctxRef.current.api.pickDirectory(effectiveOutput(), "Папка для результатов");
    if (dir) ctxRef.current.updateSettings({ unikOutputDirectory: dir });
  }, [effectiveOutput]);

  const openOutput = useCallback(() => {
    const dir = lastOutputDirectory || effectiveOutput();
    if (dir) ctxRef.current.api.openPath(dir).catch((e) => ctxRef.current.setNotice({ tone: "err", text: errorText(e) }));
  }, [lastOutputDirectory, effectiveOutput]);

  const pickOne = useCallback(async (title: string, extensions: string[]) => (await ctxRef.current.api.pickFiles(title, extensions, false))[0] ?? "", []);
  const pickLibrary = useCallback(async (title: string, extensions: string[]) => ctxRef.current.api.pickFiles(title, extensions, true), []);

  useEffect(() => () => window.clearTimeout(saveTimer.current), []);

  return {
    catalog, ffmpeg, files, options, jobs, summary, loadSaved, setOptions, refresh, installFfmpeg, addFiles, pickSources, removeFile, clearFiles,
    effectiveOutput, pickOutput, openOutput, pickOne, pickLibrary, run, handleLine,
  };
}
