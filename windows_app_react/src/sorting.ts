// Состояние экрана «Сортировка» (порт SortingPage.xaml.cs). Сама раскладка файлов — в Rust (src-tauri/src/sorting.rs).

import { useCallback, useRef, useState, type Dispatch, type MutableRefObject, type SetStateAction } from "react";
import type { Api, Settings, SortedFileRecord, SortingOutcome, WorkerItem } from "./api";
import { isToday } from "./parse";

import { t } from "./i18n";
export interface SortingContext {
  api: Api;
  settingsRef: MutableRefObject<Settings>;
  updateSettings: (patch: Partial<Settings>) => void;
  latestItems: WorkerItem[];
  setLatestItems: Dispatch<SetStateAction<WorkerItem[]>>;
  requestCleanup: (root: string, intro: string, quietIfNone?: boolean) => Promise<void>;
  setNotice: (n: { tone: "ok" | "err" | "warn"; text: string } | null) => void;
  pushLog: (line: string) => void;
}

const norm = (p: string) => p.replace(/[\\/]+/g, "\\").replace(/\\$/, "").toLowerCase();
export const pathsEqual = (a: string, b: string) => norm(a) === norm(b);
const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e));

/** После раскладки/отмены обновляет пути в «последней выгрузке» (LatestDownloadStore.UpdatePaths). */
export function updateItemPaths(items: WorkerItem[], records: SortedFileRecord[]): WorkerItem[] {
  const byId = new Map(records.filter((r) => r.id).map((r) => [r.id.toLowerCase(), r.currentPath]));
  return items.map((item) => {
    const updated = byId.get((item.id || item.localPath).toLowerCase());
    return updated ? { ...item, localPath: updated } : item;
  });
}

export function useSorting(ctx: SortingContext) {
  const [records, setRecords] = useState<SortedFileRecord[]>([]);
  const [undoRecords, setUndoRecords] = useState<SortedFileRecord[]>([]);
  const [digest, setDigest] = useState("");
  const [digestTitle, setDigestTitle] = useState(t("ДАЙДЖЕСТ"));
  const [linksDigest, setLinksDigest] = useState("");
  const [status, setStatus] = useState(t("Готово к сортировке."));
  const [driveStatus, setDriveStatus] = useState(t("Ссылки Google Drive ещё не собирались."));
  const [cleanupStatus, setCleanupStatus] = useState(t("Очистка пустых папок ещё не запускалась."));
  const [rulesSummary, setRulesSummary] = useState("");
  const [busy, setBusy] = useState<null | "sort" | "drive" | "notion">(null);
  const ctxRef = useRef(ctx);
  ctxRef.current = ctx;
  const refreshing = useRef(false);

  const say = useCallback((text: string) => setStatus(text), []);

  // ---- Правила
  const setRules = useCallback(async (text: string) => {
    const { api, settingsRef, updateSettings } = ctxRef.current;
    try {
      const parsed = await api.parseRules(text, settingsRef.current.rememberedBloggers);
      updateSettings({ sortingRules: text, rememberedBloggers: parsed.remembered });
      return parsed.count;
    } catch {
      updateSettings({ sortingRules: text });
      return 0;
    }
  }, []);

  const refreshNotionRules = useCallback(async (force = false): Promise<boolean> => {
    const { api, settingsRef, updateSettings, pushLog } = ctxRef.current;
    if (refreshing.current) return false;
    const s = settingsRef.current;
    if (!force && isToday(s.notionRoutingRulesLastRefreshAt)) {
      if (!s.notionRoutingRulesCachedRules.trim()) {
        const message = t("Notion уже обновлялся сегодня, но сохранённые правила пустые.");
        setRulesSummary(message); say(message);
        return false;
      }
      const count = await setRules(s.notionRoutingRulesCachedRules);
      const message = t("Notion уже обновлялся сегодня: использую сохранённые правила ({0}).", [count]);
      setRulesSummary(message); say(message);
      return true;
    }
    refreshing.current = true;
    setBusy("notion");
    setRulesSummary(t("Загружаю правила из Notion…")); say(t("Загружаю правила сортировки из Notion…"));
    try {
      const rules = await api.fetchNotionRules();
      if (!rules.trim()) {
        setRulesSummary(t("В Notion не найдено правил.")); say(t("В Notion не найдено правил."));
        return false;
      }
      const count = await setRules(rules);
      updateSettings({ notionRoutingRulesLastRefreshAt: new Date().toISOString(), notionRoutingRulesCachedRules: rules });
      const message = t("Notion обновлён: {0} правил.", [count]);
      setRulesSummary(message); say(message);
      return true;
    } catch (e) {
      const message = t("Не удалось обновить Notion: {0}", [errorText(e)]);
      setRulesSummary(message); say(message); pushLog(`[notion_rules] ${errorText(e)}`);
      return false;
    } finally {
      refreshing.current = false;
      setBusy((b) => (b === "notion" ? null : b));
    }
  }, [say, setRules]);

  // ---- Папки
  const pick = useCallback(async (kind: "source" | "destination" | "cleanup") => {
    const { api, settingsRef, updateSettings } = ctxRef.current;
    const s = settingsRef.current;
    const titles = { source: t("Папка «На перенос»"), destination: t("WhiteList INF Исходники"), cleanup: t("Папка для очистки пустых подпапок") };
    const keys = { source: "sortingSourceDirectory", destination: "sortingDestinationDirectory", cleanup: "emptyFolderCleanupDirectory" } as const;
    try {
      const dir = await api.pickDirectory(s[keys[kind]], titles[kind]);
      if (!dir) return;
      updateSettings({ [keys[kind]]: dir });
      if (kind === "cleanup") { setCleanupStatus(t("Папка для очистки выбрана.")); say(t("Папка для очистки выбрана.")); }
    } catch (e) {
      say(t("Не удалось открыть выбор папки: {0}", [errorText(e)]));
    }
  }, [say]);

  const open = useCallback(async (path: string) => {
    try { await ctxRef.current.api.openPath(path); } catch (e) { say(t("Не удалось открыть папку: {0}", [errorText(e)])); }
  }, [say]);

  const cleanEmptyFolders = useCallback(async () => {
    const root = ctxRef.current.settingsRef.current.emptyFolderCleanupDirectory;
    if (!root.trim()) { setCleanupStatus(t("Сначала выбери папку для очистки.")); say(t("Сначала выбери папку для очистки.")); return; }
    await ctxRef.current.requestCleanup(root, t("Приложение удалит только пустые папки из списка ниже. Папка «На перенос» и её содержимое не трогаются."));
  }, [say]);

  // ---- Раскладка
  const apply = useCallback((o: SortingOutcome, fromLatest: boolean) => {
    const { setLatestItems, updateSettings } = ctxRef.current;
    setRecords(o.records);
    if (fromLatest) setLatestItems((items) => updateItemPaths(items, o.records));
    setUndoRecords(o.records.filter((r) => !pathsEqual(r.originalPath, r.currentPath)));
    setDigest(o.report); setLinksDigest(""); setDigestTitle(t("ЛОКАЛЬНЫЙ СПИСОК"));
    setDriveStatus(o.report.trim() ? t("Локальный список готов. Для Google Drive нажми «Скопировать ссылки».") : t("Ссылки Google Drive ещё не собирались."));
    say(o.failedItems.length ? t("{0} Ошибок: {1}.", [o.summary, o.failedItems.length]) : o.summary);
    updateSettings({ rememberedBloggers: o.remembered });
  }, [say]);

  const run = useCallback(async (mode: "source" | "latest") => {
    const { api, settingsRef } = ctxRef.current;
    const s = settingsRef.current;
    if (mode === "source" && (!s.sortingSourceDirectory.trim() || !s.sortingDestinationDirectory.trim())) { say(t("Сначала выбери папку Перенос и папку назначения.")); return; }
    if (mode === "latest") {
      if (!s.sortingDestinationDirectory.trim()) { say(t("Сначала выбери папку назначения.")); return; }
      if (ctxRef.current.latestItems.length === 0) { say(t("Нет файлов из последней выгрузки для раскладки.")); return; }
    }
    setBusy("sort");
    try {
      if (settingsRef.current.notionRoutingRulesEnabled && !(await refreshNotionRules())) return;
      const cur = ctxRef.current.settingsRef.current;
      const outcome = mode === "source"
        ? await api.sortFromSource(cur.sortingSourceDirectory, cur.sortingDestinationDirectory, cur.sortingRules, cur.rememberedBloggers)
        : await api.sortItems(ctxRef.current.latestItems, cur.sortingDestinationDirectory, cur.sortingRules, cur.rememberedBloggers);
      apply(outcome, mode === "latest");
    } catch (e) {
      say(errorText(e));
      ctxRef.current.pushLog(`[sorting] ${errorText(e)}`);
    } finally {
      setBusy((b) => (b === "sort" ? null : b));
    }
  }, [apply, refreshNotionRules, say]);

  const undo = useCallback(async () => {
    const { api, setLatestItems } = ctxRef.current;
    if (!undoRecords.length) { say(t("Нет переноса для отмены.")); return; }
    try {
      const r = await api.undoSorting(undoRecords);
      setLatestItems((items) => updateItemPaths(items, r.restoredRecords));
      if (!r.failedItems.length) {
        setUndoRecords([]); setRecords([]); setDigest(""); setLinksDigest(""); setDigestTitle(t("ДАЙДЖЕСТ"));
      } else {
        const restored = new Set(r.restoredRecords.map((x) => x.id));
        setUndoRecords((cur) => cur.filter((x) => !restored.has(x.id)));
      }
      setDriveStatus(t("Перенос отменён. После новой сортировки Drive-ссылки нужно собрать заново."));
      say(r.failedItems.length ? t("{0} Ошибок: {1}.", [r.summary, r.failedItems.length]) : r.summary);
    } catch (e) {
      say(t("Не удалось отменить перенос: {0}", [errorText(e)]));
    }
  }, [say, undoRecords]);

  const copyDigest = useCallback(async () => {
    if (!digest.trim()) return;
    await ctxRef.current.api.copyText(digest);
    setDriveStatus(t("Список папок и файлов скопирован в буфер обмена."));
    say(t("Список папок и файлов скопирован в буфер обмена."));
  }, [digest, say]);

  const copyLinks = useCallback(async () => {
    if (!records.length) { setDriveStatus(t("Нет результата сортировки для сбора ссылок.")); say(t("Нет результата сортировки для сбора ссылок.")); return; }
    setBusy("drive");
    const collecting = t("Собираю Google Drive ссылки для {0} файлов…", [records.length]);
    setDriveStatus(collecting); say(collecting);
    try {
      const r = await ctxRef.current.api.exportDriveLinks(records);
      if (!r.digest.trim()) {
        setDriveStatus(t("Не удалось собрать Drive-ссылки: дайджест пуст.")); say(t("Не удалось собрать Drive-ссылки: дайджест пуст."));
        return;
      }
      await ctxRef.current.api.copyText(r.digest);
      setLinksDigest(r.digest); setDigestTitle(t("GOOGLE DRIVE ДАЙДЖЕСТ"));
      const message = r.failureCount === 0
        ? t("Google Drive ссылки собраны: {0}. Результат скопирован в буфер.", [r.successCount])
        : t("Ссылки собраны: {0}. Ошибок: {1}. Сводка скопирована в буфер.", [r.successCount, r.failureCount]);
      setDriveStatus(message); say(message);
    } catch (e) {
      const message = t("Не удалось собрать Drive-ссылки: {0}", [errorText(e)]);
      setDriveStatus(message); say(message);
    } finally {
      setBusy((b) => (b === "drive" ? null : b));
    }
  }, [records, say]);

  return {
    records, undoRecords, digest: linksDigest || digest, digestTitle, status, driveStatus, cleanupStatus, setCleanupStatus, rulesSummary, busy,
    setRules, refreshNotionRules, pick, open, cleanEmptyFolders, run, undo, copyDigest, copyLinks,
  };
}
