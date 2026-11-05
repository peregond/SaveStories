// Слой между интерфейсом и воркером. Типы повторяют windows_app/savestories_windows/models.py.
// Сейчас работает демо-режим; в Tauri `invoke` заменит mockBridge, экраны не меняются.

export type MediaFilter = "all" | "video";
export type BrowserMode = "background" | "visible";
export type BatchStatus = "pending" | "running" | "done" | "failed";

export interface BatchEntry {
  url: string;
  status: BatchStatus;
  message: string;
  found?: number;
  saved?: number;
}

export interface RunOptions {
  urls: string[];
  outputDirectory: string;
  headless: boolean;
  mediaFilter: MediaFilter;
}

export interface Bridge {
  onUpdate(cb: (e: BatchEntry[], log: string[], step: string) => void): () => void;
  startBatch(opts: RunOptions): Promise<void>;
  stop(): void;
  pickDirectory(): Promise<string | null>;
}

export const DEFAULT_DIR = "C:\\Users\\you\\Downloads\\SaveMe";

export function parseProfiles(text: string): string[] {
  const seen = new Set<string>();
  for (const raw of text.split(/[\s,;]+/)) {
    const v = raw.trim();
    if (!v) continue;
    const m = v.match(/instagram\.com\/([A-Za-z0-9._]+)/i);
    const name = (m ? m[1] : v.replace(/^@/, "")).toLowerCase();
    if (/^[a-z0-9._]{1,30}$/.test(name)) seen.add(name);
  }
  return [...seen];
}

export function createMockBridge(): Bridge {
  let listeners: Array<(e: BatchEntry[], log: string[], step: string) => void> = [];
  let timer: number | undefined;
  return {
    onUpdate(cb) {
      listeners.push(cb);
      return () => { listeners = listeners.filter((l) => l !== cb); };
    },
    async startBatch(opts) {
      const entries: BatchEntry[] = opts.urls.map((url) => ({ url, status: "pending", message: "Ожидает запуска." }));
      const log: string[] = [];
      let i = 0;
      const emit = (step: string) => listeners.forEach((l) => l([...entries], [...log], step));
      const tick = () => {
        if (i >= entries.length) { emit("Готово"); timer = undefined; return; }
        const e = entries[i];
        e.status = "running"; e.message = "Ищу активные stories…";
        log.push(`Открываю профиль ${e.url}`);
        emit(`Обработка ${e.url} (${i + 1} из ${entries.length})`);
        timer = window.setTimeout(() => {
          const found = 2 + (i % 4);
          e.status = "done"; e.found = found; e.saved = found; e.message = `Сохранено ${found}`;
          log.push(`✓ ${e.url}: ${found} файлов`);
          i += 1; emit("Сохраняю файлы"); timer = window.setTimeout(tick, 400);
        }, 1100);
      };
      tick();
    },
    stop() { if (timer) window.clearTimeout(timer); timer = undefined; },
    async pickDirectory() { return null; },
  };
}
