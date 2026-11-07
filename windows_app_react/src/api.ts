// Связь интерфейса с приложением. В Tauri вызывает Rust-команды (src-tauri/src/lib.rs),
// в обычном браузере (npm run dev) подставляется демо-реализация с теми же типами.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { open } from "@tauri-apps/plugin-dialog";

import { t } from "./i18n";
export type Theme = "system" | "light" | "dark";
export type DownloadMode = "background" | "visible";
export type MediaFilter = "all" | "video_only";

export interface RememberedBlogger { username: string; countryFolder: string; targetFolder: string; lastUsedAt: string }

export interface Settings {
  theme: Theme;
  automaticThemeByTime: boolean;
  downloadMode: DownloadMode;
  mediaFilter: MediaFilter;
  saveDirectory: string;
  preventSleep: boolean;
  recentLists: string[][];
  lastUpdateCheckAt: string;
  runtimePromptShown: boolean;
  emptyFolderCleanupDirectory: string;
  sortingSourceDirectory: string;
  sortingDestinationDirectory: string;
  sortingRules: string;
  rememberedBloggers: RememberedBlogger[];
  notionInfluencerEnabled: boolean;
  notionRoutingRulesEnabled: boolean;
  notionInfluencerLastRefreshAt: string;
  notionInfluencerCachedProfiles: string[];
  notionRoutingRulesLastRefreshAt: string;
  notionRoutingRulesCachedRules: string;
  unikOutputDirectory: string;
  /** Настройки «Уникализатора» (JSON): разбирает сам раздел. */
  unikOptions: string;
  /** Свои пресеты «Уникализатора» (JSON-список). */
  unikPresets: string;
}

export interface SortedFileRecord {
  id: string; blogger: string; countryFolder: string; targetRelativeFolder: string; originalPath: string; currentPath: string;
}
export interface SortingOutcome {
  success: boolean; summary: string; records: SortedFileRecord[]; failedItems: string[]; report: string; remembered: RememberedBlogger[];
}
export interface UndoOutcome { summary: string; restoredRecords: SortedFileRecord[]; failedItems: string[] }
export interface DriveExport { digest: string; successCount: number; failureCount: number }
export interface CleanupOutcome { removed: string[]; failed: string[] }
export interface RuntimeStatus { chromiumInstalled: boolean; workerDepsInstalled: boolean; nodeAvailable: boolean; browsersDir: string }
export interface Preflight { ok: boolean; checks: { name: string; ok: boolean; message: string }[] }
export interface Snapshot { files: number; folders: number }

export interface AppInfo {
  version: string;
  appSupport: string;
  defaultDownloads: string;
  runtimeEmbedded: boolean;
  autoUpdate: boolean;
  /** Нативный материал окна (Mica) включён: интерфейс должен быть прозрачным, а не рисовать свой фон. */
  nativeGlass: boolean;
}

export interface WorkerRequest {
  command: string;
  url?: string;
  urls?: string[];
  outputDirectory?: string;
  headless?: boolean;
  mediaFilter?: string;
  /** «Уникализатор»: файлы на проверку / исходники / настройки обработки. */
  files?: string[];
  sources?: string[];
  options?: unknown;
}

export interface StoredEntry { url: string; status: string; message: string }

export interface BatchResult { url: string; status: string; message: string; foundCount?: number; savedCount?: number }
export interface WorkerItem { id: string; localPath: string; mediaType: string; sourceURL?: string; pageURL?: string; metadataPath?: string; createdAt?: string }
export interface WorkerResponse {
  ok: boolean;
  status: string;
  message: string;
  data?: Record<string, string>;
  counts?: { found: number; saved: number; processed: number; failed: number } | null;
  batchResults?: BatchResult[];
  items?: WorkerItem[];
  logs?: string[];
}

export interface ReleaseInfo {
  version: string; tag: string; title: string; notes: string; htmlUrl: string; publishedAt: string;
  asset: { name: string; url: string; size: number; digest: string; checksumUrl: string };
}
export type UpdateCheck =
  | { status: "disabled" }
  | { status: "up_to_date" }
  | { status: "update_available"; release: ReleaseInfo };

export interface Api {
  info(): Promise<AppInfo>;
  /** Сообщает, что интерфейс отрисован: окно создаётся скрытым и показывается тут (без белой вспышки). */
  appReady(): Promise<void>;
  setWindowTheme(theme: "light" | "dark" | "system"): Promise<void>;
  /** Системное уведомление; показывается, только если окно свёрнуто или не в фокусе. Возвращает, показано ли. */
  notify(title: string, body: string): Promise<boolean>;
  /** Подсказка у значка в трее. */
  setTrayStatus(text: string): Promise<void>;
  /** Подписи пунктов меню у значка в трее (язык интерфейса). */
  setTrayLabels(show: string, quit: string): Promise<void>;
  getSettings(): Promise<Settings>;
  saveSettings(settings: Settings): Promise<void>;
  loadQueue(): Promise<StoredEntry[]>;
  saveQueue(entries: StoredEntry[]): Promise<void>;
  run(request: WorkerRequest, timeoutSecs?: number): Promise<WorkerResponse>;
  cancel(): Promise<boolean>;
  login(request: WorkerRequest): Promise<void>;
  onLog(cb: (line: string) => void): Promise<() => void>;
  pickDirectory(current: string, title?: string): Promise<string | null>;
  /** Выбор файлов: extensions — без точки. Возвращает пустой список, если окно закрыли. */
  pickFiles(title: string, extensions: string[], multiple: boolean): Promise<string[]>;
  /** Файлы, перетащенные на окно приложения. */
  onFilesDropped(cb: (paths: string[]) => void): Promise<() => void>;
  openPath(path: string): Promise<void>;
  copyText(text: string): Promise<void>;
  // Сортировка
  parseRules(rules: string, remembered: RememberedBlogger[]): Promise<{ count: number; remembered: RememberedBlogger[] }>;
  sortFromSource(source: string, destination: string, rules: string, remembered: RememberedBlogger[]): Promise<SortingOutcome>;
  sortItems(items: WorkerItem[], destination: string, rules: string, remembered: RememberedBlogger[]): Promise<SortingOutcome>;
  undoSorting(records: SortedFileRecord[]): Promise<UndoOutcome>;
  exportDriveLinks(records: SortedFileRecord[]): Promise<DriveExport>;
  // Notion и очистка
  fetchNotionRules(): Promise<string>;
  fetchNotionProfiles(): Promise<string[]>;
  findEmptyFolders(root: string): Promise<string[]>;
  deleteEmptyFolders(folders: string[]): Promise<CleanupOutcome>;
  snapshot(root: string): Promise<Snapshot>;
  // Среда
  runtimeStatus(): Promise<RuntimeStatus>;
  installChromium(): Promise<string>;
  onBootstrapLog(cb: (line: string) => void): Promise<() => void>;
  preflight(): Promise<Preflight>;
  exportDiagnostics(): Promise<string>;
  // Обновления
  checkUpdate(): Promise<UpdateCheck>;
  prepareUpdate(release: ReleaseInfo): Promise<void>;
  installUpdate(): Promise<void>;
  onUpdateProgress(cb: (percent: number, message: string) => void): Promise<() => void>;
}

/** Копирование в буфер: современный API, а если он недоступен или запрещён — через временное поле. */
export async function copyToClipboard(text: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(text);
    return;
  } catch { /* пробуем запасной способ */ }
  const area = document.createElement("textarea");
  area.value = text;
  area.style.cssText = "position:fixed;left:-9999px;top:0;opacity:0";
  document.body.appendChild(area);
  area.select();
  const ok = document.execCommand("copy");
  area.remove();
  if (!ok) throw new Error(t("Не удалось скопировать в буфер обмена."));
}

const tauriApi: Api = {
  info: () => invoke("app_info"),
  appReady: () => invoke("app_ready"),
  setWindowTheme: (theme) => invoke("window_set_theme", { theme }),
  notify: (title, body) => invoke("notify", { title, body }),
  setTrayStatus: (text) => invoke("set_tray_status", { text }),
  setTrayLabels: (show, quit) => invoke("set_tray_labels", { show, quit }),
  getSettings: () => invoke("settings_get"),
  saveSettings: (settings) => invoke("settings_save", { settings }),
  loadQueue: () => invoke("queue_load"),
  saveQueue: (entries) => invoke("queue_save", { entries }),
  run: (request, timeoutSecs) => invoke("worker_run", { request, timeoutSecs: timeoutSecs ?? null }),
  cancel: () => invoke("worker_cancel"),
  login: (request) => invoke("worker_login", { request }),
  onLog: (cb) => listen<string>("worker-log", (e) => cb(e.payload)),
  pickDirectory: async (current, title) => {
    const picked = await open({ directory: true, multiple: false, defaultPath: current || undefined, title: title ?? t("Выбор папки") });
    return typeof picked === "string" ? picked : null;
  },
  pickFiles: async (title, extensions, multiple) => {
    const picked = await open({ directory: false, multiple, title, filters: [{ name: t("Файлы"), extensions }] });
    return Array.isArray(picked) ? picked : typeof picked === "string" ? [picked] : [];
  },
  onFilesDropped: (cb) => getCurrentWebview().onDragDropEvent((e) => { if (e.payload.type === "drop") cb(e.payload.paths); }),
  openPath: (path) => invoke("open_path", { path }),
  copyText: copyToClipboard,
  parseRules: (rules, remembered) => invoke("sorting_parse_rules", { rules, remembered }),
  sortFromSource: (source, destination, rules, remembered) => invoke("sorting_run_source", { source, destination, rules, remembered }),
  sortItems: (items, destination, rules, remembered) => invoke("sorting_run_items", { items, destination, rules, remembered }),
  undoSorting: (records) => invoke("sorting_undo", { records }),
  exportDriveLinks: (records) => invoke("drive_export", { records }),
  fetchNotionRules: () => invoke("notion_fetch_rules"),
  fetchNotionProfiles: () => invoke("notion_fetch_profiles"),
  findEmptyFolders: (root) => invoke("cleanup_find", { root }),
  deleteEmptyFolders: (folders) => invoke("cleanup_delete", { folders }),
  snapshot: (root) => invoke("dir_snapshot", { root }),
  runtimeStatus: () => invoke("runtime_status"),
  installChromium: () => invoke("runtime_install_chromium"),
  onBootstrapLog: (cb) => listen<string>("bootstrap-log", (e) => cb(e.payload)),
  preflight: () => invoke("preflight"),
  exportDiagnostics: () => invoke("export_diagnostics"),
  checkUpdate: () => invoke("update_check"),
  prepareUpdate: (release) => invoke("update_prepare", { release }),
  installUpdate: () => invoke("update_install"),
  onUpdateProgress: (cb) => listen<{ percent: number; message: string }>("update-progress", (e) => cb(e.payload.percent, e.payload.message)),
};

export const isTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

export async function createApi(): Promise<Api> {
  if (isTauri) return tauriApi;
  const { createDemoApi } = await import("./demoApi");
  return createDemoApi();
}
