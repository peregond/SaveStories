import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Api, AppInfo, ReleaseInfo, Settings, WorkerItem, WorkerResponse } from "./api";
import { parseBatchLinks, parseReelLinks, profileName } from "./parse";

export type Session = "unknown" | "checking" | "ready" | "login_required" | "waiting_login" | "error";
export type EntryStatus = "pending" | "running" | "completed" | "failed" | "stopped";
export interface Entry { url: string; status: EntryStatus; message: string }
export type UpdatePhase = "idle" | "checking" | "up_to_date" | "available" | "downloading" | "ready" | "error" | "disabled";
export interface UpdateState { phase: UpdatePhase; release?: ReleaseInfo; percent: number; message: string }
export interface Totals { found: number; saved: number }

const TWELVE_HOURS = 12 * 60 * 60 * 1000;
const LOG_LIMIT = 300;
const fallbackSettings: Settings = {
  theme: "system", downloadMode: "background", mediaFilter: "video_only",
  saveDirectory: "", preventSleep: true, recentLists: [], lastUpdateCheckAt: "",
};

export function useStore(api: Api) {
  const [info, setInfo] = useState<AppInfo | null>(null);
  const [settings, setSettingsState] = useState<Settings>(fallbackSettings);
  const [loaded, setLoaded] = useState(false);
  const [workerReady, setWorkerReady] = useState<boolean | null>(null);
  const [workerSummary, setWorkerSummary] = useState("Проверяю среду…");
  const [session, setSession] = useState<Session>("unknown");
  const [sessionSummary, setSessionSummary] = useState("");
  const [entries, setEntries] = useState<Entry[]>([]);
  const [totals, setTotals] = useState<Totals>({ found: 0, saved: 0 });
  const [busy, setBusy] = useState<null | "batch" | "reels" | "probe">(null);
  const [stopping, setStopping] = useState(false);
  const [step, setStep] = useState("Ожидание команды.");
  const [notice, setNotice] = useState<{ tone: "ok" | "err" | "warn"; text: string } | null>(null);
  const [log, setLog] = useState<string[]>([]);
  const [reelItems, setReelItems] = useState<WorkerItem[]>([]);
  const [reelsMessage, setReelsMessage] = useState("");
  const [update, setUpdate] = useState<UpdateState>({ phase: "idle", percent: 0, message: "" });
  const settingsRef = useRef(settings);
  settingsRef.current = settings;
  const entriesRef = useRef<Entry[]>([]);

  const pushLog = useCallback((line: string) => {
    setLog((l) => [...l.slice(-(LOG_LIMIT - 1)), line]);
  }, []);

  const updateSettings = useCallback((patch: Partial<Settings>) => {
    const next = { ...settingsRef.current, ...patch };
    settingsRef.current = next;
    setSettingsState(next);
    void api.saveSettings(next).catch((e) => pushLog(`[settings] ${String(e)}`));
  }, [api, pushLog]);

  const headless = settings.downloadMode === "background";

  // ---- Сессия и среда
  const checkSession = useCallback(async (opts: { silent?: boolean } = {}) => {
    setSession((s) => (s === "waiting_login" ? s : "checking"));
    try {
      const r = await api.run({ command: "check_session", headless: true });
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
      setSessionSummary(String(e));
      return false;
    }
  }, [api]);

  const probe = useCallback(async () => {
    setBusy("probe");
    try {
      const env = await api.run({ command: "environment" });
      setWorkerReady(env.ok);
      setWorkerSummary(env.message);
      if (env.ok) await checkSession({ silent: true });
      else setSession("unknown");
    } catch (e) {
      setWorkerReady(false);
      setWorkerSummary(String(e));
    } finally {
      setBusy(null);
    }
  }, [api, checkSession]);

  const checkUpdates = useCallback(async (opts: { silent?: boolean } = {}) => {
    setUpdate((u) => (u.phase === "downloading" || u.phase === "ready" ? u : { phase: "checking", percent: 0, message: "Проверяю обновления…" }));
    try {
      const r = await api.checkUpdate();
      updateSettings({ lastUpdateCheckAt: new Date().toISOString() });
      if (r.status === "update_available") setUpdate({ phase: "available", release: r.release, percent: 0, message: `Доступна версия ${r.release.version}.` });
      else if (r.status === "disabled") setUpdate({ phase: "disabled", percent: 0, message: "Проверка обновлений отключена." });
      else setUpdate({ phase: "up_to_date", percent: 0, message: "Установлена последняя версия." });
    } catch (e) {
      setUpdate(opts.silent ? { phase: "idle", percent: 0, message: "" } : { phase: "error", percent: 0, message: String(e) });
    }
  }, [api, updateSettings]);

  // ---- Запуск
  useEffect(() => {
    let off: (() => void) | undefined;
    let offUpdate: (() => void) | undefined;
    let alive = true;
    void (async () => {
      off = await api.onLog(pushLog);
      offUpdate = await api.onUpdateProgress((percent, message) => setUpdate((u) => ({ ...u, phase: "downloading", percent, message })));
      const [i, s] = await Promise.all([api.info(), api.getSettings()]);
      if (!alive) return;
      setInfo(i); setSettingsState(s); settingsRef.current = s; setLoaded(true);
      await probe();
      const last = Date.parse(s.lastUpdateCheckAt);
      if (!(Date.now() - last < TWELVE_HOURS)) void checkUpdates({ silent: true });
    })();
    return () => { alive = false; off?.(); offUpdate?.(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api]);

  // Пока ждём вход в браузере, раз в 3 секунды проверяем сессию (как в Python-клиенте).
  useEffect(() => {
    if (session !== "waiting_login") return;
    const id = window.setInterval(async () => {
      if (await checkSession({ silent: true })) {
        pushLog("Сессия Instagram найдена. Окно входа можно закрыть.");
        setNotice({ tone: "ok", text: "Вход выполнен: сессия Instagram сохранена." });
      }
    }, 3000);
    return () => window.clearInterval(id);
  }, [session, checkSession, pushLog]);

  const login = useCallback(async () => {
    try {
      await api.login({ command: "login", headless: false, outputDirectory: settingsRef.current.saveDirectory });
      setSession("waiting_login");
      setNotice({ tone: "warn", text: "Войдите в Instagram в открывшемся окне браузера. Приложение само найдёт сессию." });
      pushLog("Открыл отдельное окно браузера для входа в Instagram.");
    } catch (e) {
      setNotice({ tone: "err", text: `Не удалось открыть браузер для входа: ${String(e)}` });
    }
  }, [api, pushLog]);

  // ---- Очередь профилей
  // Очередь хранится и в ref (всегда актуальный снимок для async-кода), и в state (для отрисовки).
  const commit = useCallback((next: Entry[]) => { entriesRef.current = next; setEntries(next); }, []);

  const addProfiles = useCallback((text: string): number => {
    const links = parseBatchLinks(text);
    const known = new Set(entriesRef.current.map((e) => e.url));
    const fresh: Entry[] = [];
    for (const url of links) {
      if (known.has(url)) continue;
      known.add(url);
      fresh.push({ url, status: "pending", message: "Ожидает запуска." });
    }
    if (fresh.length) commit([...entriesRef.current, ...fresh]);
    return fresh.length;
  }, [commit]);

  const applyBatch = useCallback((urls: string[], r: WorkerResponse) => {
    const byUrl = new Map((r.batchResults ?? []).map((x) => [x.url, x]));
    commit(entriesRef.current.map((e) => {
      if (!urls.includes(e.url)) return e;
      if (r.status === "cancelled") return { ...e, status: "stopped" as const, message: "Остановлено пользователем." };
      const res = byUrl.get(e.url);
      if (!res) {
        return r.batchResults?.length
          ? { ...e, status: "failed" as const, message: "Для профиля нет результата пакетной выгрузки." }
          : { ...e, status: r.ok ? ("completed" as const) : ("failed" as const), message: r.message };
      }
      return { ...e, status: res.status === "completed" ? ("completed" as const) : ("failed" as const), message: res.message || r.message };
    }));
  }, [commit]);

  const startQueue = useCallback(async (extraText = "") => {
    if (busy) return;
    if (extraText) addProfiles(extraText);
    const urls = entriesRef.current.filter((e) => e.status === "pending" || e.status === "failed").map((e) => e.url);
    if (!urls.length) { setNotice({ tone: "warn", text: "В очереди нет профилей для выгрузки." }); return; }

    setStopping(false);
    setBusy("batch"); setNotice(null); setTotals({ found: 0, saved: 0 });
    commit(entriesRef.current.map((e) => (urls.includes(e.url) ? { ...e, status: "running" as const, message: "Ожидает обработки в общем окне браузера." } : e)));
    setStep(`Выгрузка профилей: ${urls.length}. Очередь выполняется в одном окне браузера.`);
    try {
      const r = await api.run({
        command: "download_profile_batch", urls, outputDirectory: settingsRef.current.saveDirectory,
        headless, mediaFilter: settingsRef.current.mediaFilter,
      });
      applyBatch(urls, r);
      const found = r.counts?.found ?? Number(r.data?.foundCount ?? 0);
      const saved = r.counts?.saved ?? Number(r.data?.savedCount ?? 0);
      setTotals({ found, saved });
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
    } catch (e) {
      commit(entriesRef.current.map((x) => (urls.includes(x.url) && x.status === "running" ? { ...x, status: "failed" as const, message: String(e) } : x)));
      setNotice({ tone: "err", text: String(e) }); setStep("Ошибка.");
    } finally {
      setBusy(null); setStopping(false);
    }
  }, [api, busy, headless, addProfiles, applyBatch, commit]);

  const stop = useCallback(async () => {
    if (!busy || busy === "probe") return;
    setStopping(true); setStep("Останавливаю выгрузку…");
    pushLog("Запрошена остановка выгрузки.");
    await api.cancel();
  }, [api, busy, pushLog]);

  const clearQueue = useCallback(() => {
    if (busy) return;
    commit([]); setTotals({ found: 0, saved: 0 }); setStep("Ожидание команды."); setNotice(null);
  }, [busy, commit]);

  const removeEntry = useCallback((url: string) => { if (!busy) commit(entriesRef.current.filter((e) => e.url !== url)); }, [busy, commit]);

  // ---- Reels
  const downloadReels = useCallback(async (text: string): Promise<boolean> => {
    const urls = parseReelLinks(text);
    if (!urls.length || busy) return false;
    setBusy("reels"); setNotice(null); setReelsMessage("Скачиваю Reels…");
    try {
      const r = await api.run({ command: "download_reels_urls", urls, outputDirectory: settingsRef.current.saveDirectory, headless });
      if (r.status === "cancelled") setReelsMessage("Остановлено.");
      else { setReelsMessage(r.message); setReelItems((cur) => [...(r.items ?? []), ...cur]); }
      setNotice({ tone: r.ok ? "ok" : r.status === "cancelled" ? "warn" : "err", text: r.status === "cancelled" ? "Выгрузка Reels остановлена." : r.message });
      return r.ok;
    } catch (e) {
      setReelsMessage(String(e)); setNotice({ tone: "err", text: String(e) });
      return false;
    } finally {
      setBusy(null); setStopping(false);
    }
  }, [api, busy, headless]);

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
      setUpdate({ phase: "error", release, percent: 0, message: String(e) });
    }
  }, [api, update.release]);
  const installUpdate = useCallback(async () => {
    try { await api.installUpdate(); } catch (e) { setUpdate((u) => ({ ...u, phase: "error", message: String(e) })); }
  }, [api]);

  const pickDirectory = useCallback(async () => {
    const dir = await api.pickDirectory(settingsRef.current.saveDirectory);
    if (dir) updateSettings({ saveDirectory: dir });
  }, [api, updateSettings]);
  const openSaveDirectory = useCallback(() => {
    api.openPath(settingsRef.current.saveDirectory).catch((e) => setNotice({ tone: "err", text: String(e) }));
  }, [api]);
  const openAppData = useCallback(() => { if (info) api.openPath(info.appSupport).catch((e) => setNotice({ tone: "err", text: String(e) })); }, [api, info]);

  const stats = useMemo(() => ({
    profiles: entries.length,
    saved: totals.saved,
    files: totals.found,
    folders: entries.filter((e) => e.status === "completed").length,
  }), [entries, totals]);
  const done = entries.filter((e) => e.status === "completed" || e.status === "failed" || e.status === "stopped").length;
  const progress = entries.length ? Math.round((done / entries.length) * 100) : 0;
  const pending = entries.filter((e) => e.status === "pending" || e.status === "failed").length;
  const retryOnly = pending > 0 && entries.filter((e) => e.status === "pending").length === 0;

  return {
    api, info, settings, loaded, updateSettings, workerReady, workerSummary, session, sessionSummary,
    entries, stats, retryOnly, busy, running: busy === "batch" || busy === "reels", stopping, step, notice, setNotice, log, progress, pending,
    reelItems, reelsMessage, update, headless,
    probe, checkSession, login, addProfiles, startQueue, stop, clearQueue, removeEntry,
    downloadReels, rememberList, removeList, checkUpdates, prepareUpdate, installUpdate,
    pickDirectory, openSaveDirectory, openAppData,
  };
}
export type Store = ReturnType<typeof useStore>;
