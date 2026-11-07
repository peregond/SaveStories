// Демо-режим для браузера: имитирует ответы приложения в тех же форматах.
// Параметры URL: ?session=none (нет входа), ?fail=1 (профиль с ошибкой), ?chromium=none (нет Chromium),
// ?notion=1 (включён Notion), ?empty=1 (после выгрузки есть пустые папки).

import type {
  Api, AppInfo, RememberedBlogger, Settings, SortedFileRecord, SortingOutcome, WorkerItem, WorkerRequest, WorkerResponse,
} from "./api";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const params = new URLSearchParams(typeof location === "undefined" ? "" : location.search);
const nameOf = (url: string) => url.replace(/\/+$/, "").split("/").pop() ?? url;

export function createDemoApi(): Api {
  // Только для демо: имитация обоев под прозрачным окном (в приложении под ним настоящий Mica).
  if (params.get("glass") === "native" && typeof document !== "undefined") {
    const dark = params.get("theme") === "dark";
    document.documentElement.style.background = dark
      ? "radial-gradient(900px 600px at 15% 10%, #2b3a55 0%, transparent 60%), radial-gradient(800px 600px at 90% 90%, #1f4a45 0%, transparent 60%), #151a22"
      : "radial-gradient(900px 600px at 15% 10%, #c9d9f2 0%, transparent 60%), radial-gradient(800px 600px at 90% 90%, #cfe8dd 0%, transparent 60%), #e8ecf1";
  }
  let settings: Settings = {
    theme: (params.get("theme") as Settings["theme"]) || "system", automaticThemeByTime: false,
    downloadMode: "background", mediaFilter: "video_only", saveDirectory: "C:\\Users\\you\\Downloads\\SaveMe",
    preventSleep: true, recentLists: [], lastUpdateCheckAt: "", runtimePromptShown: false,
    emptyFolderCleanupDirectory: "", sortingSourceDirectory: "D:\\На перенос", sortingDestinationDirectory: "D:\\WhiteList INF Исходники",
    sortingRules: params.get("rules") === "1" ? "anna = Germany (DE) 🇩🇪 INF\nbob = Australia (AU) 🇦🇺 INF" : "",
    rememberedBloggers: [], unikOutputDirectory: "", unikOptions: "", unikPresets: "", notionInfluencerEnabled: params.get("notion") === "1", notionRoutingRulesEnabled: false,
    notionInfluencerLastRefreshAt: "", notionInfluencerCachedProfiles: [], notionRoutingRulesLastRefreshAt: "", notionRoutingRulesCachedRules: "",
  };
  let loggedIn = params.get("session") !== "none";
  let chromium = params.get("chromium") !== "none";
  let logListeners: Array<(l: string) => void> = [];
  let bootstrapListeners: Array<(l: string) => void> = [];
  let cancelled = false;
  const log = (l: string) => logListeners.forEach((cb) => cb(l));
  const info: AppInfo = { version: "0.6.94", appSupport: "C:\\Users\\you\\AppData\\Local\\SaveMe", defaultDownloads: settings.saveDirectory, runtimeEmbedded: true, autoUpdate: true, nativeGlass: params.get("glass") === "native" };

  const record = (blogger: string, rules: string, file: string, from: string): SortedFileRecord => {
    const rule = rules.split("\n").map((l) => l.split("=").map((x) => x.trim())).find(([u]) => u?.toLowerCase() === blogger.toLowerCase());
    const target = rule?.[1] ? `${rule[1]}\\${blogger}` : blogger;
    return { id: `${from}\\${file}`, blogger, countryFolder: rule?.[1] ?? "Без страны", targetRelativeFolder: target, originalPath: `${from}\\${file}`, currentPath: `D:\\Dst\\${target}\\${file}` };
  };
  const outcome = (records: SortedFileRecord[], remembered: RememberedBlogger[]): SortingOutcome => ({
    success: records.length > 0, summary: `Разложено файлов: ${records.length}. Подпапок затронуто: ${new Set(records.map((r) => r.targetRelativeFolder)).size}.`,
    records, failedItems: [], remembered: [...remembered, ...records.map((r) => ({ username: r.blogger, countryFolder: r.countryFolder, targetFolder: r.targetRelativeFolder, lastUsedAt: new Date().toISOString() }))],
    report: records.map((r) => `[${r.targetRelativeFolder}]\n${r.currentPath}`).join("\n\n"),
  });

  // «Уникализатор»: каталог как в воркере и имитация обработки (в браузере FFmpeg нет).
  const unikCatalog = {
    formatPresets: [
      { id: "meta-story", name: "Instagram Stories 9x16", description: "Вертикальный формат для Stories и Reels.", resize: { width: 1080, height: 1920, fit: "cover", backgroundStyle: "bars", backgroundColor: "#111111" }, fps: 30, bitrate: "4M" },
      { id: "meta-square", name: "Instagram/Facebook Post 1x1", description: "Квадрат для ленты Meta.", resize: { width: 1080, height: 1080, fit: "cover", backgroundStyle: "bars", backgroundColor: "#111111" }, fps: 30, bitrate: "5M" },
      { id: "meta-feed-4x5", name: "Meta 4x5 1080x1350", description: "Вертикальная лента Meta.", resize: { width: 1080, height: 1350, fit: "cover", backgroundStyle: "bars", backgroundColor: "#111111" }, fps: 30, bitrate: "6M" },
      { id: "facebook-feed-4x5", name: "Facebook 4x5 1080x1350", description: "Лента Facebook для мобильных.", resize: { width: 1080, height: 1350, fit: "cover", backgroundStyle: "bars", backgroundColor: "#111111" }, fps: 30, bitrate: "6M" },
      { id: "google-ads-landscape", name: "Google Ads 1.91:1 1200x628", description: "Горизонтальный формат для Google Ads.", resize: { width: 1200, height: 628, fit: "contain", backgroundStyle: "bars", backgroundColor: "#111111" }, fps: 30, bitrate: "5M" },
    ],
    stylePresets: [["clean", "Чистый", "Без доп. стиля"], ["soft", "Мягкий", "Теплее и мягче"], ["cinematic", "Кино", "Глубже, темнее, спокойнее"], ["bright", "Яркий", "Сочнее и быстрее"], ["warm", "Тёплый", "Выраженные тёплые тона"], ["cold", "Холодный", "Холоднее и строже"], ["crisp", "Чёткий", "Резче и контрастнее"], ["calm", "Спокойный", "Приглушённый и медленный"]]
      .map(([id, label, hint]) => ({ id, label, hint, hueShift: 0, saturation: 1, sharpness: 0, speedOffsetMs: 0 })),
    fpsOptions: [25, 30, 50, 60], variationOptions: [1, 2, 3, 5],
    bitrateOptions: [{ value: "1.5M", label: "Низкое", hint: "Легче файл" }, { value: "2M", label: "Стандарт", hint: "По умолчанию" }, { value: "3M", label: "Высокое", hint: "Лучше качество" }, { value: "4M", label: "Очень высокое", hint: "Больше деталей" }, { value: "6M", label: "Максимум", hint: "Мастер-режим" }],
    ageMarkGeos: [["au-australia", "AU - Australia"], ["de-germany", "DE - Germany"], ["nl-netherlands", "NL - Netherlands"], ["nda-amonbet", "NDA - AmonBet"], ["da-luckyhunter", "DA - LuckyHunter"], ["gb-great-britain", "GB - Great Britain"], ["ca-canada", "CA - Canada"], ["fr-france", "FR - France"], ["es-spain", "ES - Spain"]].map(([id, name]) => ({ id, name })),
  };
  let ffmpegInstalled = params.get("ffmpeg") !== "none";
  const unikDemo = async (req: WorkerRequest): Promise<WorkerResponse> => {
    if (req.command === "unik_status") return { ok: true, status: "unik_status", message: "", data: { ffmpegInstalled: String(ffmpegInstalled), ffmpegVersion: ffmpegInstalled ? "7.1-essentials_build" : "", catalog: JSON.stringify(unikCatalog) } };
    if (req.command === "unik_install_ffmpeg") {
      for (const [p, m] of [[0, "Ищу актуальную сборку FFmpeg…"], [10, "Скачиваю ffmpeg-7.1-essentials_build.zip (83 МБ)…"], [60, ""], [100, "Распаковываю…"]] as Array<[number, string]>) { if (m) log(`unik_ffmpeg_message=${m}`); log(`unik_ffmpeg_progress=${p}`); await sleep(500); }
      ffmpegInstalled = true;
      return { ok: true, status: "unik_ffmpeg_ready", message: "FFmpeg 7.1 установлен.", data: { ffmpegVersion: "7.1-essentials_build" } };
    }
    if (req.command === "unik_inspect") return { ok: true, status: "unik_inspected", message: "", data: { inspections: JSON.stringify((req.files ?? []).map((f, i) => (/\.(png|jpe?g|webp)$/i.test(f) ? { ok: true, filePath: f, kind: "image", width: 1080, height: 1080 } : { ok: true, filePath: f, kind: "video", width: 720, height: 1280, durationSeconds: 14 + i * 7, hasAudio: i !== 1 }))) } };
    // unik_process
    const sources = req.sources ?? [];
    const opts = (req.options ?? {}) as { variations?: { count?: number; mode?: string } };
    const perFile = opts.variations?.mode === "preset-per-file" && sources.length > 1;
    const per = perFile ? 1 : opts.variations?.count ?? 1;
    const total = sources.length * per;
    log(`unik_total=${total}`);
    const results: Array<{ index: number; outputPath: string; status: string; message: string }> = [];
    for (let i = 0; i < total; i++) {
      const name = `${nameOf(sources[Math.floor(i / per)] ?? "x")}_v${i + 1}.mp4`;
      log(`unik_job_${i}_start=${name}`);
      for (const p of [20, 55, 90]) { await sleep(300); if (cancelled) return { ok: false, status: "cancelled", message: "Остановлено пользователем." }; log(`unik_job_${i}_progress=${p}`); }
      const failed = params.get("fail") === "1" && i === 1;
      if (failed) { log(`unik_job_${i}_error=FFmpeg завершился с кодом 1.`); results.push({ index: i, outputPath: "", status: "failed", message: "FFmpeg завершился с кодом 1." }); }
      else { log(`unik_job_${i}_done=${req.outputDirectory}\\${name}`); results.push({ index: i, outputPath: `${req.outputDirectory}\\${name}`, status: "completed", message: "" }); }
    }
    const done = results.filter((r) => r.status === "completed").length;
    return { ok: done > 0, status: "unik_complete", message: `Готово: ${done} из ${total}${done < total ? `, ошибок: ${total - done}` : ""}.`, data: { total: String(total), done: String(done), failed: String(total - done), results: JSON.stringify(results) } };
  };

  return {
    info: async () => info,
    appReady: async () => {},
    setWindowTheme: async () => {},
    notify: async () => false,
    setTrayStatus: async () => {},
    setTrayLabels: async () => {},
    getSettings: async () => structuredClone(settings),
    saveSettings: async (s) => { settings = structuredClone(s); },
    loadQueue: async () => (params.get("queue") === "restore"
      ? [{ url: "https://www.instagram.com/dian.vegas1/", status: "completed", message: "Сохранено 3" }, { url: "https://www.instagram.com/stevensetu/", status: "running", message: "Скачивается…" }, { url: "https://www.instagram.com/leftlanepapi/", status: "pending", message: "" }]
      : []),
    saveQueue: async () => {},
    onLog: async (cb) => { logListeners.push(cb); return () => { logListeners = logListeners.filter((l) => l !== cb); }; },
    onBootstrapLog: async (cb) => { bootstrapListeners.push(cb); return () => { bootstrapListeners = bootstrapListeners.filter((l) => l !== cb); }; },
    cancel: async () => { cancelled = true; return true; },
    login: async () => { setTimeout(() => { loggedIn = true; }, 4000); },
    pickDirectory: async () => null,
    pickFiles: async (_t, _e, multiple) => (params.get("unik") ? ["C:\\Видео\\creo_1.mp4", "C:\\Видео\\creo_2.mov", "C:\\Видео\\banner.png"].slice(0, multiple ? 3 : 1) : []),
    onFilesDropped: async () => () => {},
    openPath: async () => {},
    copyText: async (t) => { await navigator.clipboard?.writeText(t).catch(() => {}); },
    parseRules: async (rules, remembered) => ({ count: rules.split("\n").filter((l) => l.includes("=")).length, remembered }),
    sortFromSource: async (_s, _d, rules, remembered) => { await sleep(300); return outcome([record("anna", rules, "1.mp4", "D:\\На перенос\\anna"), record("zed", rules, "9.mp4", "D:\\На перенос\\zed")], remembered); },
    sortItems: async (items: WorkerItem[], _d, rules, remembered) => { await sleep(300); return outcome(items.map((i) => record(nameOf(i.sourceURL ?? "x"), rules, i.localPath.split("\\").pop() ?? "f", "C:\\dl")), remembered); },
    undoSorting: async (records) => ({ summary: `Отменён перенос файлов: ${records.length}.`, restoredRecords: records.map((r) => ({ ...r, originalPath: r.currentPath, currentPath: r.originalPath })), failedItems: [] }),
    exportDriveLinks: async (records) => { await sleep(600); return { digest: records.map((r) => `${r.countryFolder}\n\n${r.blogger}\nhttps://drive.google.com/open?id=DEMO${r.blogger}`).join("\n\n"), successCount: records.length, failureCount: 0 }; },
    fetchNotionRules: async () => { await sleep(400); return "anna = Germany (DE) 🇩🇪 INF\nbob = Australia (AU) 🇦🇺 INF"; },
    fetchNotionProfiles: async () => { await sleep(400); return ["https://www.instagram.com/notion_anna/", "https://www.instagram.com/notion_bob/"]; },
    findEmptyFolders: async () => (params.get("empty") === "1" ? ["C:\\x\\empty_a", "C:\\x\\empty_b"] : []),
    deleteEmptyFolders: async (f) => ({ removed: f, failed: [] }),
    snapshot: async () => ({ files: 3, folders: 2 }),
    runtimeStatus: async () => ({ chromiumInstalled: chromium, workerDepsInstalled: true, nodeAvailable: true, browsersDir: "C:\\Users\\you\\AppData\\Local\\SaveMe\\worker\\ms-playwright" }),
    installChromium: async () => {
      for (const l of ["Скачиваю Chromium для Playwright…", "Downloading Chromium 141.0 (playwright build v1194) 20%", "Downloading Chromium 141.0 (playwright build v1194) 100%"]) { bootstrapListeners.forEach((cb) => cb(l)); await sleep(500); }
      chromium = true; return "Chromium установлен.";
    },
    preflight: async () => ({ ok: chromium, checks: [
      { name: "Node runtime", ok: true, message: "C:\\Program Files\\SaveMe\\runtime\\node\\node.exe" }, { name: "node_worker", ok: true, message: "OK" },
      { name: "Запись в папку загрузок", ok: true, message: settings.saveDirectory }, { name: "Chromium", ok: chromium, message: chromium ? "установлен" : "не установлен" },
      { name: "Зависимости воркера", ok: true, message: "установлены" },
    ] }),
    exportDiagnostics: async () => "C:\\Users\\you\\AppData\\Local\\SaveMe\\logs\\diagnostics-demo.txt",
    checkUpdate: async () => ({ status: "up_to_date" }),
    prepareUpdate: async () => {},
    installUpdate: async () => {},
    onUpdateProgress: async () => () => {},
    async run(req: WorkerRequest): Promise<WorkerResponse> {
      cancelled = false;
      await sleep(250);
      if (req.command === "environment") return { ok: true, status: "environment_ready", message: "Среда Node worker готова.", data: { runtime: "node" } };
      if (req.command === "check_session") return { ok: loggedIn, status: loggedIn ? "session_ready" : "session_missing", message: loggedIn ? "Сессия Instagram найдена." : "Активная сессия Instagram не найдена. Сначала откройте браузер для входа.", data: { loggedIn: String(loggedIn) } };
      if (req.command?.startsWith("unik_")) return unikDemo(req);
      const urls = req.urls ?? [];
      if (req.command === "download_reels_urls") {
        const items = urls.map((u, i) => ({ id: `r${i}`, localPath: `${settings.saveDirectory}\\reels\\${i + 1}.mp4`, mediaType: "video", sourceURL: u }));
        const failed = params.get("fail") === "1" ? urls.slice(1) : [];
        return { ok: true, status: "completed", message: `Сохранено Reels: ${urls.length - failed.length}.`, data: { savedCount: String(urls.length - failed.length), processedCount: String(urls.length), failedCount: String(failed.length) },
          items: items.slice(0, urls.length - failed.length), logs: failed.map((u) => `reel_failed=${u} :: недоступно`) };
      }
      const results = []; const items: WorkerItem[] = [];
      for (const [i, url] of urls.entries()) {
        log(`batch_slot_${i + 1}_start=${url}`);
        await sleep(900);
        if (cancelled) return { ok: false, status: "cancelled", message: "Остановлено пользователем." };
        const failed = params.get("fail") === "1" && i === 1;
        const n = failed ? 0 : 2 + (i % 3);
        results.push({ url, status: failed ? "failed" : "completed", message: failed ? "Активных stories не найдено." : `Сохранено ${n}`, foundCount: n, savedCount: n });
        for (let k = 0; k < n; k++) items.push({ id: `${i}-${k}`, localPath: `${settings.saveDirectory}\\${nameOf(url)}\\${k + 1}.mp4`, mediaType: "video", sourceURL: url });
        log(failed ? `batch_slot_${i + 1}_error=${url} :: нет stories` : `batch_slot_${i + 1}_done=${url}`);
      }
      const saved = items.length;
      return { ok: true, status: "completed", message: `Сохранено файлов: ${saved}.`, batchResults: results, items,
        data: { foundCount: String(saved), savedCount: String(saved), processedCount: String(urls.length) },
        counts: { found: saved, saved, processed: urls.length, failed: results.filter((r) => r.status === "failed").length } };
    },
  };
}
