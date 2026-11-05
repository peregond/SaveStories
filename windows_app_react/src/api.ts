// Связь интерфейса с приложением. В Tauri вызывает Rust-команды (src-tauri/src/lib.rs),
// в обычном браузере (npm run dev) подставляется демо-реализация с теми же типами.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";

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
}

export interface WorkerRequest {
  command: string;
  url?: string;
  urls?: string[];
  outputDirectory?: string;
  headless?: boolean;
  mediaFilter?: string;
}

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
  getSettings(): Promise<Settings>;
  saveSettings(settings: Settings): Promise<void>;
  run(request: WorkerRequest, timeoutSecs?: number): Promise<WorkerResponse>;
  cancel(): Promise<boolean>;
  login(request: WorkerRequest): Promise<void>;
  onLog(cb: (line: string) => void): Promise<() => void>;
  pickDirectory(current: string, title?: string): Promise<string | null>;
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

const tauriApi: Api = {
  info: () => invoke("app_info"),
  getSettings: () => invoke("settings_get"),
  saveSettings: (settings) => invoke("settings_save", { settings }),
  run: (request, timeoutSecs) => invoke("worker_run", { request, timeoutSecs: timeoutSecs ?? null }),
  cancel: () => invoke("worker_cancel"),
  login: (request) => invoke("worker_login", { request }),
  onLog: (cb) => listen<string>("worker-log", (e) => cb(e.payload)),
  pickDirectory: async (current, title) => {
    const picked = await open({ directory: true, multiple: false, defaultPath: current || undefined, title: title ?? "Выбор папки" });
    return typeof picked === "string" ? picked : null;
  },
  openPath: (path) => invoke("open_path", { path }),
  copyText: (text) => navigator.clipboard.writeText(text),
  parseRules: (rules, remembered) => invoke("sorting_parse_rules", { rules, remembered }),
  sortFromSource: (source, destination, rules, remembered) => invoke("sorting_run_source", { source, destination, rules, remembered }),
  sortItems: (items, destination, rules, remembered) => invoke("sorting_run_items", { items, destination, rules, remembered }),
  undoSorting: (records) => invoke("sorting_undo", { records }),
  exportDriveLinks: (records) => invoke("drive_export", { records }),
  fetchNotionRules: () => invoke("notion_fetch_rules", { url: null }),
  fetchNotionProfiles: () => invoke("notion_fetch_profiles", { url: null }),
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
