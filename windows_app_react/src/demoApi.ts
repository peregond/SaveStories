// Демо-режим для браузера: имитирует ответы воркера в том же формате.
// Параметры URL: ?session=none (нет входа), ?fail=1 (один профиль с ошибкой).

import type { Api, AppInfo, Settings, WorkerRequest, WorkerResponse } from "./api";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const params = new URLSearchParams(typeof location === "undefined" ? "" : location.search);

export function createDemoApi(): Api {
  let settings: Settings = {
    theme: (params.get("theme") as Settings["theme"]) || "system",
    downloadMode: "background", mediaFilter: "video_only",
    saveDirectory: "C:\\Users\\you\\Downloads\\SaveMe", preventSleep: true, recentLists: [], lastUpdateCheckAt: "",
  };
  let loggedIn = params.get("session") !== "none";
  let logListeners: Array<(l: string) => void> = [];
  let cancelled = false;
  const log = (l: string) => logListeners.forEach((cb) => cb(l));
  const info: AppInfo = { version: "0.6.85", appSupport: "C:\\Users\\you\\AppData\\Local\\SaveMe", defaultDownloads: settings.saveDirectory, runtimeEmbedded: true, autoUpdate: true };

  return {
    info: async () => info,
    getSettings: async () => structuredClone(settings),
    saveSettings: async (s) => { settings = structuredClone(s); },
    onLog: async (cb) => { logListeners.push(cb); return () => { logListeners = logListeners.filter((l) => l !== cb); }; },
    cancel: async () => { cancelled = true; return true; },
    login: async () => { setTimeout(() => { loggedIn = true; }, 4000); },
    pickDirectory: async () => null,
    openPath: async () => {},
    checkUpdate: async () => ({ status: "up_to_date" }),
    prepareUpdate: async () => {},
    installUpdate: async () => {},
    onUpdateProgress: async () => () => {},
    async run(req: WorkerRequest): Promise<WorkerResponse> {
      cancelled = false;
      await sleep(250);
      if (req.command === "environment") return { ok: true, status: "environment_ready", message: "Среда Node worker готова.", data: { runtime: "node" } };
      if (req.command === "check_session") return { ok: true, status: "session_ready", message: loggedIn ? "Сессия Instagram найдена." : "Сессия не найдена.", data: { loggedIn: String(loggedIn) } };
      const urls = req.urls ?? [];
      const results = [];
      for (const [i, url] of urls.entries()) {
        log(`Открываю профиль ${url}`);
        await sleep(900);
        if (cancelled) return { ok: false, status: "cancelled", message: "Остановлено пользователем." };
        const failed = params.get("fail") === "1" && i === 1;
        results.push({ url, status: failed ? "failed" : "completed", message: failed ? "Активных stories не найдено." : `Сохранено ${2 + (i % 3)}`, foundCount: failed ? 0 : 2 + (i % 3), savedCount: failed ? 0 : 2 + (i % 3) });
        log(failed ? `✗ ${url}: нет stories` : `✓ ${url}`);
      }
      const saved = results.reduce((n, r) => n + (r.savedCount ?? 0), 0);
      return {
        ok: true, status: "completed", message: `Сохранено файлов: ${saved}.`, batchResults: results,
        counts: { found: saved, saved, processed: results.length, failed: results.filter((r) => r.status === "failed").length },
        items: req.command === "download_reels_urls" ? urls.map((u, i) => ({ id: String(i), localPath: `${settings.saveDirectory}\\reels\\${i + 1}.mp4`, mediaType: "video", sourceURL: u })) : [],
      };
    },
  };
}
