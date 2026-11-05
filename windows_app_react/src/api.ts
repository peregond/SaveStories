// Связь интерфейса с приложением. В Tauri вызывает Rust-команды (src-tauri/src/lib.rs),
// в обычном браузере (npm run dev) подставляется демо-реализация с теми же типами.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";

export type Theme = "system" | "light" | "dark";
export type DownloadMode = "background" | "visible";
export type MediaFilter = "all" | "video_only";

export interface Settings {
  theme: Theme;
  downloadMode: DownloadMode;
  mediaFilter: MediaFilter;
  saveDirectory: string;
  preventSleep: boolean;
  recentLists: string[][];
  lastUpdateCheckAt: string;
}

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
export interface WorkerItem { id: string; localPath: string; mediaType: string; sourceURL?: string }
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
  run(request: WorkerRequest): Promise<WorkerResponse>;
  cancel(): Promise<boolean>;
  login(request: WorkerRequest): Promise<void>;
  onLog(cb: (line: string) => void): Promise<() => void>;
  pickDirectory(current: string): Promise<string | null>;
  openPath(path: string): Promise<void>;
  checkUpdate(): Promise<UpdateCheck>;
  prepareUpdate(release: ReleaseInfo): Promise<void>;
  installUpdate(): Promise<void>;
  onUpdateProgress(cb: (percent: number, message: string) => void): Promise<() => void>;
}

const tauriApi: Api = {
  info: () => invoke("app_info"),
  getSettings: () => invoke("settings_get"),
  saveSettings: (settings) => invoke("settings_save", { settings }),
  run: (request) => invoke("worker_run", { request }),
  cancel: () => invoke("worker_cancel"),
  login: (request) => invoke("worker_login", { request }),
  onLog: (cb) => listen<string>("worker-log", (e) => cb(e.payload)),
  pickDirectory: async (current) => {
    const picked = await open({ directory: true, multiple: false, defaultPath: current || undefined, title: "Папка для сохранения" });
    return typeof picked === "string" ? picked : null;
  },
  openPath: (path) => invoke("open_path", { path }),
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
