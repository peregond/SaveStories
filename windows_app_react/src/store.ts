import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Api, AppInfo, Preflight, ReleaseInfo, RuntimeStatus, Settings, WorkerItem, WorkerResponse } from "./api";
import { isToday, parseProfiles, parseReelLines, profileFromProgress, profileName, progressDetail, workerTimeoutSecs } from "./parse";
import { useSorting } from "./sorting";

export type Session = "unknown" | "checking" | "ready" | "login_required" | "waiting_login" | "error";
export type EntryStatus = "pending" | "running" | "completed" | "failed" | "stopped";
export interface Entry { url: string; status: EntryStatus; message: string }
export type UpdatePhase = "idle" | "checking" | "up_to_date" | "available" | "downloading" | "ready" | "error" | "disabled";
export interface UpdateState { phase: UpdatePhase; release?: ReleaseInfo; percent: number; message: string }
export interface Totals { found: number; saved: number; processed: number; files: number }
export interface Notice { tone: "ok" | "err" | "warn"; text: string }
export interface CleanupOffer { folders: string[]; title: string; intro: string }
export interface ReelsState { queue: string[]; failed: string[]; downloads: string[]; summary: string }

const TWELVE_HOURS = 12 * 60 * 60 * 1000;
const LOG_LIMIT = 1500;
const emptyTotals: Totals = { found: 0, saved: 0, processed: 0, files: 0 };

export const defaultSettings: Settings = {
  theme: "system", automaticThemeByTime: true, downloadMode: "background", mediaFilter: "video_only", saveDirectory: "",
  preventSleep: true, recentLists: [], lastUpdateCheckAt: "", runtimePromptShown: false,
  emptyFolderCleanupDirectory: "", sortingSourceDirectory: "", sortingDestinationDirectory: "", sortingRules: "", rememberedBloggers: [],
  notionInfluencerEnabled: false, notionRoutingRulesEnabled: false, notionInfluencerLastRefreshAt: "", notionInfluencerCachedProfiles: [],
  notionRoutingRulesLastRefreshAt: "", notionRoutingRulesCachedRules: "",
};

const stamp = () => new Date().toTimeString().slice(0, 8);
const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e));

export function useStore(api: Api) {
  const [info, setInfo] = useState<AppInfo | null>(null);
  const [settings, setSettingsState] = useState<Settings>(defaultSettings);
  const [loaded, setLoaded] = useState(false);
  const [workerReady, setWorkerReady] = useState<boolean | null>(null);
  const [workerSummary, setWorkerSummary] = useState("Проверяю среду…");
  const [runtime, setRuntime] = useState<RuntimeStatus | null>(null);
  const [bootstrapping, setBootstrapping] = useState(false);
  const [preflight, setPreflight] = useState<Preflight | null>(null);
  const [session, setSession] = useState<Session>("unknown");
  const [sessionSummary, setSessionSummary] = useState("");
  const [entries, setEntries] = useState<Entry[]>([]);
  const [totals, setTotals] = useState<Totals>(emptyTotals);
  const [live, setLive] = useState({ files: 0, folders: 0 });
  const [busy, setBusy] = useState<null | "batch" | "reels" | "probe">(null);
  const [stopping, setStopping] = useState(false);
  const [step, setStep] = useState("Ожидание команды.");
  const [notice, setNotice] = useState<Notice | null>(null);
  const [log, setLog] = useState<string[]>([]);
  const [latestItems, setLatestItems] = useState<WorkerItem[]>([]);
  const [cleanupOffer, setCleanupOffer] = useState<CleanupOffer | null>(null);
  const [notionBusy, setNotionBusy] = useState(false);
  const [notionSummary, setNotionSummary] = useState("");
  const [reels, setReels] = useState<ReelsState>({ queue: [], failed: [], downloads: [], summary: "" });
  const [update, setUpdate] = useState<UpdateState>({ phase: "idle", percent: 0, message: "" });

  const settingsRef = useRef(settings);
  settingsRef.current = settings;
  const entriesRef = useRef<Entry[]>([]);
  const baseline = useRef({ files: 0, folders: 0 });
  const lastStatsAt = useRef(0);
  const busyRef = useRef(busy);
  busyRef.current = busy;

  const pushLog = useCallback((line: string) => {
    setLog((l) => [...l.slice(-(LOG_LIMIT - 1)), `${stamp()}  ${line}`]);
  }, []);

  const updateSettings = useCallback((patch: Partial<Settings>) => {
    const next = { ...settingsRef.current, ...patch };
    settingsRef.current = next;
    setSettingsState(next);
    void api.saveSettings(next).catch((e) => pushLog(`[settings] ${errorText(e)}`));
  }, [api, pushLog]);

  const commit = useCallback((next: Entry[]) => { entriesRef.current = next; setEntries(next); }, []);
  const headless = settings.downloadMode === "background";

  // ---- Живая статистика выгрузки (файлы в папке сохранения минус то, что было до запуска)
  const refreshLive = useCallback(async (force = false) => {
    const now = Date.now();
    if (!force && now - lastStatsAt.current < 1000) return;
    lastStatsAt.current = now;
    try {
      const s = await api.snapshot(settingsRef.current.saveDirectory);
      setLive({ files: Math.max(s.files - baseline.current.files, 0), folders: Math.max(s.folders - baseline.current.folders, 0) });
    } catch { /* папка может быть недоступна — статистика необязательна */ }
  }, [api]);

  // ---- Прогресс воркера: строки batch_slot_N_start / _done / _error
  const onWorkerLine = useCallback((line: string) => {
    pushLog(line);
    if (!line.startsWith("batch_slot_")) return;
    const kind = line.includes("_start=") ? "start" : line.includes("_done=") ? "done" : line.includes("_error=") ? "error" : "";
    if (!kind) return;
    const who = profileFromProgress(line).toLowerCase();
    const detail = progressDetail(line);
    commit(entriesRef.current.map((e) => {
      if (profileName(e.url).toLowerCase() !== who || e.status === "completed") return e;
      if (kind === "start") return { ...e, status: "running" as const, message: "Скачивается…" };
      if (kind === "done") return { ...e, status: "completed" as const, message: "Профиль обработан." };
      return { ...e, status: "failed" as const, message: detail || "Не удалось обработать профиль." };
    }));
    const processed = entriesRef.current.filter((e) => e.status === "completed" || e.status === "failed").length;
    if (kind === "start") setStep(`Сейчас обрабатывается: ${profileFromProgress(line)}`);
    else if (kind === "done") setStep(`Готов профиль: ${profileFromProgress(line)}`);
    else setStep(detail ? `Не удалось обработать ${profileFromProgress(line)}: ${detail}` : `Не удалось обработать: ${profileFromProgress(line)}`);
    setTotals((t) => ({ ...t, processed }));
    void refreshLive();
  }, [commit, pushLog, refreshLive]);

  // ---- Сессия и среда
  const checkSession = useCallback(async (opts: { silent?: boolean } = {}) => {
    setSession((s) => (s === "waiting_login" ? s : "checking"));
    try {
      const r = await api.run({ command: "check_session", headless: true }, workerTimeoutSecs("check_session", 0, true));
      const ready = r.ok && r.data?.loggedIn === "true";
      const missing = r.status === "session_missing" || r.data?.loggedIn === "false";
      setSessionSummary(r.message);
      setSession((prev) => {
        if (ready) return "ready";
        if (prev === "waiting_login" && opts.silent) return "waiting_login";
        return missing ? "login_required" : "error";
      });
      return ready;
    } catch (e) {
      setSession("error");
      setSessionSummary(errorText(e));
      return false;
    }
  }, [api]);

  const probe = useCallback(async () => {
    setBusy("probe");
    try {
      const rt = await api.runtimeStatus();
      setRuntime(rt);
      const env = await api.run({ command: "environment" }, 120);
      setWorkerReady(env.ok);
      setWorkerSummary(env.message);
      if (env.ok && rt.chromiumInstalled) await checkSession({ silent: true });
      else setSession("unknown");
    } catch (e) {
      setWorkerReady(false);
      setWorkerSummary(errorText(e));
    } finally {
      setBusy(null);
    }
  }, [api, checkSession]);

  const installChromium = useCallback(async () => {
    if (bootstrapping) return;
    setBootstrapping(true);
    setNotice({ tone: "warn", text: "Скачиваю Chromium. Это занимает несколько минут." });
    try {
      const msg = await api.installChromium();
      pushLog(msg);
      setNotice({ tone: "ok", text: msg });
      updateSettings({ runtimePromptShown: true });
      await probe();
    } catch (e) {
      setNotice({ tone: "err", text: errorText(e) });
    } finally {
      setBootstrapping(false);
    }
  }, [api, bootstrapping, probe, pushLog, updateSettings]);

  const runPreflight = useCallback(async () => {
    try { setPreflight(await api.preflight()); } catch (e) { setNotice({ tone: "err", text: errorText(e) }); }
  }, [api]);

  const exportDiagnostics = useCallback(async () => {
    try {
      const path = await api.exportDiagnostics();
      setNotice({ tone: "ok", text: `Диагностика сохранена: ${path}` });
    } catch (e) {
      setNotice({ tone: "err", text: errorText(e) });
    }
  }, [api]);

  const checkUpdates = useCallback(async (opts: { silent?: boolean } = {}) => {
    setUpdate((u) => (u.phase === "downloading" || u.phase === "ready" ? u : { phase: "checking", percent: 0, message: "Проверяю обновления…" }));
    try {
      const r = await api.checkUpdate();
      updateSettings({ lastUpdateCheckAt: new Date().toISOString() });
      if (r.status === "update_available") setUpdate({ phase: "available", release: r.release, percent: 0, message: `Доступна версия ${r.release.version}.` });
      else if (r.status === "disabled") setUpdate({ phase: "disabled", percent: 0, message: "Проверка обновлений отключена." });
      else setUpdate({ phase: "up_to_date", percent: 0, message: "Установлена последняя версия." });
    } catch (e) {
      setUpdate(opts.silent ? { phase: "idle", percent: 0, message: "" } : { phase: "error", percent: 0, message: errorText(e) });
    }
  }, [api, updateSettings]);

  // ---- Запуск приложения
  useEffect(() => {
    const offs: Array<() => void> = [];
    let alive = true;
    void (async () => {
      offs.push(await api.onLog(onWorkerLine));
      offs.push(await api.onBootstrapLog(pushLog));
      offs.push(await api.onUpdateProgress((percent, message) => setUpdate((u) => ({ ...u, phase: "downloading", percent, message }))));
      const [i, s] = await Promise.all([api.info(), api.getSettings()]);
      if (!alive) return;
      setInfo(i); setSettingsState(s); settingsRef.current = s; setLoaded(true);
      await probe();
      const last = Date.parse(s.lastUpdateCheckAt);
      if (!(Date.now() - last < TWELVE_HOURS)) void checkUpdates({ silent: true });
    })();
    return () => { alive = false; offs.forEach((off) => off()); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api]);

  // Пока ждём вход в браузере, раз в 3 секунды проверяем сессию.
  useEffect(() => {
    if (session !== "waiting_login") return;
    const id = window.setInterval(async () => {
      if (busyRef.current) return;
      if (await checkSession({ silent: true })) {
        pushLog("Сессия Instagram найдена. Окно входа можно закрыть.");
        setNotice({ tone: "ok", text: "Вход выполнен: сессия Instagram сохранена." });
      }
    }, 3000);
    return () => window.clearInterval(id);
  }, [session, checkSession, pushLog]);

  // Пока идёт пакетная выгрузка, раз в 2 секунды обновляем счётчики файлов.
  useEffect(() => {
    if (busy !== "batch") return;
    const id = window.setInterval(() => void refreshLive(true), 2000);
    return () => window.clearInterval(id);
  }, [busy, refreshLive]);

  const login = useCallback(async () => {
    try {
      await api.login({ command: "login", headless: false, outputDirectory: settingsRef.current.saveDirectory });
      setSession("waiting_login");
      setNotice({ tone: "warn", text: "Войдите в Instagram в открывшемся окне браузера. Приложение само найдёт сессию." });
      pushLog("Открыл отдельное окно браузера для входа в Instagram.");
    } catch (e) {
      setNotice({ tone: "err", text: `Не удалось открыть браузер для входа: ${errorText(e)}` });
    }
  }, [api, pushLog]);

  // ---- Notion: список инфлюенсеров (не чаще раза в день)
  const applyProfiles = useCallback((profiles: string[], replace: boolean) => {
    const known = new Set((replace ? [] : entriesRef.current).map((e) => e.url.toLowerCase()));
    const fresh: Entry[] = [];
    for (const url of profiles) {
      if (known.has(url.toLowerCase())) continue;
      known.add(url.toLowerCase());
      fresh.push({ url, status: "pending", message: "Ожидает запуска." });
    }
    commit(replace ? fresh : [...entriesRef.current, ...fresh]);
    return fresh.length;
  }, [commit]);

  const refreshNotionInfluencers = useCallback(async (opts: { replace: boolean; force?: boolean }): Promise<boolean> => {
    const s = settingsRef.current;
    if (busyRef.current === "batch" || notionBusy) return false;
    if (!opts.force && isToday(s.notionInfluencerLastRefreshAt)) {
      if (!s.notionInfluencerCachedProfiles.length) {
        setNotionSummary("Notion уже обновлялся сегодня, но сохранённый список пуст.");
        pushLog("Повторная загрузка Notion пропущена: сегодня уже обновляли, сохранённый список пуст.");
        return false;
      }
      const n = applyProfiles(s.notionInfluencerCachedProfiles, opts.replace);
      setNotionSummary(`Notion уже обновлялся сегодня: использую сохранённый список (${s.notionInfluencerCachedProfiles.length} профилей).`);
      pushLog(`Повторная загрузка Notion пропущена: применён сохранённый список, профилей: ${n}.`);
      return true;
    }
    setNotionBusy(true);
    setNotionSummary("Загружаю свежий список из Notion…");
    pushLog("Загружаю свежий список инфлюенсеров из Notion.");
    try {
      const profiles = await api.fetchNotionProfiles();
      if (!profiles.length) {
        setNotionSummary("В Notion не найдено профилей.");
        setNotice({ tone: "err", text: "В Notion-списке не найдено профилей." });
        return false;
      }
      const n = applyProfiles(profiles, opts.replace);
      pushLog(opts.replace ? `Очередь заменена свежим Notion-списком: ${profiles.length} профилей.` : `Из Notion-списка добавлено новых профилей: ${n}.`);
      updateSettings({ notionInfluencerLastRefreshAt: new Date().toISOString(), notionInfluencerCachedProfiles: profiles });
      setNotionSummary(`Notion обновлён в ${stamp().slice(0, 5)}: ${profiles.length} профилей.`);
      return true;
    } catch (e) {
      setNotionSummary(`Не удалось обновить Notion: ${errorText(e)}`);
      setNotice({ tone: "err", text: `Не удалось обновить Notion: ${errorText(e)}` });
      return false;
    } finally {
      setNotionBusy(false);
    }
  }, [api, applyProfiles, notionBusy, pushLog, updateSettings]);

  // ---- Очередь профилей
  const addProfiles = useCallback((text: string): number => {
    const links = parseProfiles(text);
    const known = new Set(entriesRef.current.map((e) => e.url.toLowerCase()));
    const fresh: Entry[] = [];
    for (const url of links) {
      if (known.has(url.toLowerCase())) continue;
      known.add(url.toLowerCase());
      fresh.push({ url, status: "pending", message: "Ожидает запуска." });
    }
    if (fresh.length) commit([...entriesRef.current, ...fresh]);
    return fresh.length;
  }, [commit]);

  const requestCleanup = useCallback(async (root: string, intro: string, quietIfNone = false): Promise<void> => {
    if (!root.trim()) { setNotice({ tone: "warn", text: "Сначала выбери папку для очистки." }); return; }
    const folders = await api.findEmptyFolders(root);
    if (!folders.length) {
      if (quietIfNone) pushLog("Пустых папок после выгрузки stories не найдено.");
      else setNotice({ tone: "ok", text: "Пустых папок в выбранной папке не найдено." });
      return;
    }
    pushLog(`Найдены пустые папки: ${folders.length}.`);
    setCleanupOffer({ folders, title: "Удалить пустые папки?", intro });
  }, [api, pushLog]);

  const confirmCleanup = useCallback(async () => {
    const offer = cleanupOffer;
    setCleanupOffer(null);
    if (!offer) return;
    try {
      const r = await api.deleteEmptyFolders(offer.folders);
      const text = r.failed.length ? `Удалено пустых папок: ${r.removed.length}. Ошибок: ${r.failed.length}.` : `Удалено пустых папок: ${r.removed.length}.`;
      pushLog(text);
      setNotice({ tone: r.failed.length ? "warn" : "ok", text });
    } catch (e) {
      setNotice({ tone: "err", text: errorText(e) });
    }
  }, [api, cleanupOffer, pushLog]);
  const dismissCleanup = useCallback(() => { setCleanupOffer(null); pushLog("Удаление пустых папок пропущено."); }, [pushLog]);

  const applyBatch = useCallback((urls: string[], r: WorkerResponse) => {
    const byUrl = new Map((r.batchResults ?? []).map((x) => [x.url.toLowerCase(), x]));
    commit(entriesRef.current.map((e) => {
      if (!urls.includes(e.url)) return e;
      if (r.status === "cancelled") return { ...e, status: e.status === "completed" ? e.status : ("stopped" as const), message: e.status === "completed" ? e.message : "Остановлено пользователем." };
      const res = byUrl.get(e.url.toLowerCase());
      if (!res) {
        return r.batchResults?.length
          ? { ...e, status: "failed" as const, message: "Для профиля нет результата пакетной выгрузки." }
          : { ...e, status: r.ok ? ("completed" as const) : ("failed" as const), message: r.message };
      }
      return { ...e, status: res.status === "completed" ? ("completed" as const) : ("failed" as const), message: res.message || r.message };
    }));
  }, [commit]);

  const startQueue = useCallback(async (extraText = "") => {
    if (busyRef.current) return;
    if (settingsRef.current.notionInfluencerEnabled) {
      if (!(await refreshNotionInfluencers({ replace: true }))) return;
    }
    if (extraText) addProfiles(extraText);
    const urls = entriesRef.current.filter((e) => e.status === "pending" || e.status === "failed").map((e) => e.url);
    if (!urls.length) { setNotice({ tone: "warn", text: "Добавь хотя бы один профиль." }); return; }

    const s = settingsRef.current;
    setStopping(false); setBusy("batch"); setNotice(null);
    setTotals({ ...emptyTotals, processed: 0 });
    try { baseline.current = await api.snapshot(s.saveDirectory); } catch { baseline.current = { files: 0, folders: 0 }; }
    setLive({ files: 0, folders: 0 });
    commit(entriesRef.current.map((e) => (urls.includes(e.url) ? { ...e, status: "pending" as const, message: "Ожидает обработки в общем окне браузера." } : e)));
    setStep(`Выгрузка профилей: ${urls.length}. Очередь выполняется в одном окне браузера.`);
    const timeout = workerTimeoutSecs("download_profile_batch", urls.length, headless);
    pushLog(`batch_timeout_minutes=${Math.round(timeout / 60)}`);
    try {
      const r = await api.run({ command: "download_profile_batch", urls, outputDirectory: s.saveDirectory, headless, mediaFilter: s.mediaFilter }, timeout);
      setLatestItems((r.items ?? []).filter((i) => i.localPath));
      applyBatch(urls, r);
      const found = Number(r.counts?.found ?? r.data?.foundCount ?? 0);
      const saved = Number(r.counts?.saved ?? r.data?.savedCount ?? (r.items ?? []).length);
      setTotals({ found, saved, processed: Number(r.data?.processedCount ?? urls.length), files: (r.items ?? []).length });
      for (const l of r.logs ?? []) pushLog(l);
      pushLog(`[${r.status}] ${r.message}`);
      if (r.status === "cancelled") { setStep("Остановлено."); setNotice({ tone: "warn", text: "Выгрузка остановлена." }); }
      else if (!r.ok && !r.batchResults?.length) { setStep("Ошибка."); setNotice({ tone: "err", text: r.message }); }
      else {
        const failed = (r.batchResults ?? []).filter((x) => x.status !== "completed").length;
        setStep("Очередь обработана.");
        setNotice(failed
          ? { tone: "warn", text: `Завершено с ошибками: ${failed} из ${urls.length}. Сохранено файлов: ${saved}.` }
          : { tone: "ok", text: `Готово. Сохранено файлов: ${saved}.` });
      }
      if (!r.ok && /session|login|вход|сесс/i.test(`${r.status} ${r.message}`)) setSession("login_required");
      await refreshLive(true);
      if (r.status !== "cancelled") {
        await requestCleanup(s.saveDirectory, "После выгрузки stories найдены пустые папки. Папка «На перенос» и её содержимое не трогаются.", true).catch(() => {});
      }
    } catch (e) {
      commit(entriesRef.current.map((x) => (urls.includes(x.url) && x.status !== "completed" ? { ...x, status: "failed" as const, message: errorText(e) } : x)));
      setNotice({ tone: "err", text: errorText(e) }); setStep("Ошибка.");
    } finally {
      setBusy(null); setStopping(false);
    }
  }, [api, headless, addProfiles, applyBatch, commit, pushLog, refreshLive, refreshNotionInfluencers, requestCleanup]);

  const stop = useCallback(async () => {
    if (!busyRef.current || busyRef.current === "probe") return;
    setStopping(true); setStep("Останавливаю выгрузку…");
    pushLog("Запрошена остановка текущей задачи.");
    await api.cancel();
  }, [api, pushLog]);

  const clearQueue = useCallback(() => {
    if (busyRef.current) return;
    commit([]); setTotals(emptyTotals); setLive({ files: 0, folders: 0 }); setStep("Ожидание команды."); setNotice(null);
    pushLog("Очередь очищена.");
  }, [commit, pushLog]);

  const retryFailed = useCallback(() => {
    if (busyRef.current) return;
    const failed = entriesRef.current.filter((e) => e.status === "failed");
    if (!failed.length) return;
    commit(failed.map((e) => ({ ...e, status: "pending" as const, message: "Ожидает запуска." })));
    pushLog(`Сформирована очередь из неудачных профилей: ${failed.length}`);
  }, [commit, pushLog]);

  const removeEntry = useCallback((url: string) => { if (!busyRef.current) commit(entriesRef.current.filter((e) => e.url !== url)); }, [commit]);

  // ---- Reels
  const addReels = useCallback((text: string) => {
    const lines = parseReelLines(text);
    setReels((r) => {
      const known = new Set(r.queue.map((x) => x.toLowerCase()));
      return { ...r, queue: [...r.queue, ...lines.filter((l) => !known.has(l.toLowerCase()))] };
    });
    return lines.length;
  }, []);

  const downloadReels = useCallback(async (text: string): Promise<boolean> => {
    if (busyRef.current) return false;
    const queue = [...new Set([...reels.queue, ...parseReelLines(text)])];
    if (!queue.length) { setNotice({ tone: "warn", text: "Добавь хотя бы одну ссылку Reels." }); return false; }
    setBusy("reels"); setStopping(false); setNotice(null);
    setReels((r) => ({ ...r, queue, summary: "Запускаю выгрузку Reels…" }));
    try {
      const r = await api.run({ command: "download_reels_urls", urls: queue, outputDirectory: settingsRef.current.saveDirectory, headless }, workerTimeoutSecs("download_reels_urls", queue.length, headless));
      const failed = (r.logs ?? []).filter((l) => l.startsWith("reel_failed=")).map((l) => l.slice("reel_failed=".length).split(" :: ")[0].trim()).filter(Boolean);
      for (const l of r.logs ?? []) pushLog(l);
      pushLog(`[${r.status}] ${r.message}`);
      const saved = r.data?.savedCount ?? String((r.items ?? []).length);
      const processed = r.data?.processedCount ?? String(queue.length);
      setReels((cur) => ({
        queue: r.status === "cancelled" ? cur.queue : [], failed,
        downloads: [...(r.items ?? []).map((i) => i.localPath.split(/[\\/]/).pop() || i.localPath), ...cur.downloads],
        summary: r.status === "cancelled" ? "Остановлено." : `Ссылок: ${queue.length}  ·  Обработано: ${processed}  ·  Сохранено: ${saved}  ·  Ошибок: ${r.data?.failedCount ?? failed.length}  ·  Файлов: ${(r.items ?? []).length}`,
      }));
      setNotice({ tone: r.ok ? "ok" : r.status === "cancelled" ? "warn" : "err", text: r.status === "cancelled" ? "Выгрузка Reels остановлена." : r.message });
      return r.ok;
    } catch (e) {
      setNotice({ tone: "err", text: errorText(e) });
      return false;
    } finally {
      setBusy(null); setStopping(false);
    }
  }, [api, headless, pushLog, reels.queue]);

  const retryFailedReels = useCallback(() => {
    setReels((r) => (r.failed.length ? { ...r, queue: r.failed, failed: [] } : r));
  }, []);
  const clearReelsQueue = useCallback(() => setReels((r) => ({ ...r, queue: [], failed: [] })), []);

  // ---- Недавние наборы
  const rememberList = useCallback((urls: string[]) => {
    const names = urls.map(profileName);
    if (!names.length) return;
    const key = names.join("|");
    const rest = settingsRef.current.recentLists.filter((l) => l.join("|") !== key);
    updateSettings({ recentLists: [names, ...rest].slice(0, 12) });
  }, [updateSettings]);
  const removeList = useCallback((index: number) => {
    updateSettings({ recentLists: settingsRef.current.recentLists.filter((_, i) => i !== index) });
  }, [updateSettings]);

  // ---- Обновления
  const prepareUpdate = useCallback(async () => {
    const release = update.release;
    if (!release) return;
    setUpdate({ phase: "downloading", release, percent: 0, message: `Скачивание обновления ${release.version}: 0%` });
    try {
      await api.prepareUpdate(release);
      setUpdate({ phase: "ready", release, percent: 100, message: `Обновление ${release.version} подготовлено.` });
    } catch (e) {
      setUpdate({ phase: "error", release, percent: 0, message: errorText(e) });
    }
  }, [api, update.release]);
  const installUpdate = useCallback(async () => {
    try { await api.installUpdate(); } catch (e) { setUpdate((u) => ({ ...u, phase: "error", message: errorText(e) })); }
  }, [api]);

  const pickDirectory = useCallback(async () => {
    const dir = await api.pickDirectory(settingsRef.current.saveDirectory, "Папка сохранения");
    if (dir) { updateSettings({ saveDirectory: dir }); pushLog(`Папка сохранения обновлена: ${dir}`); }
  }, [api, pushLog, updateSettings]);
  const openSaveDirectory = useCallback(() => {
    api.openPath(settingsRef.current.saveDirectory).catch((e) => setNotice({ tone: "err", text: errorText(e) }));
  }, [api]);
  const openAppData = useCallback(() => { if (info) api.openPath(info.appSupport).catch((e) => setNotice({ tone: "err", text: errorText(e) })); }, [api, info]);

  const sorting = useSorting({ api, settingsRef, updateSettings, latestItems, setLatestItems, requestCleanup, setNotice, pushLog });

  const stats = useMemo(() => ({
    profiles: entries.length,
    processed: totals.processed,
    found: totals.found,
    saved: totals.saved,
    files: totals.files,
    done: entries.filter((e) => e.status === "completed").length,
  }), [entries, totals]);
  const finished = entries.filter((e) => e.status === "completed" || e.status === "failed" || e.status === "stopped").length;
  const progress = entries.length ? Math.round((finished / entries.length) * 100) : 0;
  const pending = entries.filter((e) => e.status === "pending" || e.status === "failed").length;
  const failedCount = entries.filter((e) => e.status === "failed").length;
  const retryOnly = pending > 0 && entries.filter((e) => e.status === "pending").length === 0;

  return {
    api, info, settings, loaded, updateSettings, workerReady, workerSummary, runtime, bootstrapping, preflight, session, sessionSummary,
    entries, stats, live, retryOnly, failedCount, busy, running: busy === "batch" || busy === "reels", stopping, step, notice, setNotice, log, progress, pending,
    latestItems, cleanupOffer, notionBusy, notionSummary, reels, update, headless, sorting,
    probe, checkSession, login, installChromium, runPreflight, exportDiagnostics,
    addProfiles, startQueue, stop, clearQueue, retryFailed, removeEntry, refreshNotionInfluencers,
    addReels, downloadReels, retryFailedReels, clearReelsQueue, rememberList, removeList, checkUpdates, prepareUpdate, installUpdate,
    pickDirectory, openSaveDirectory, openAppData, requestCleanup, confirmCleanup, dismissCleanup,
  };
}
export type Store = ReturnType<typeof useStore>;
