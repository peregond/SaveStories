// Восстановление очереди после запуска приложения (сама очередь хранится в queue.json, см. src-tauri/src/queue.rs).

import type { StoredEntry } from "./api";
import type { Entry } from "./store";

export interface Restored {
  entries: Entry[];
  /** Профили, которые были «в работе» или остановлены, когда приложение закрылось: после запуска снова ждут выгрузки. */
  interrupted: number;
  /** Сколько профилей будет выгружено при нажатии «Скачать». */
  toRun: number;
}

export function restoreEntries(stored: StoredEntry[]): Restored {
  let interrupted = 0;
  const entries = stored.map((s): Entry => {
    if (s.status === "running" || s.status === "stopped") {
      interrupted += 1;
      return { url: s.url, status: "pending", message: "Прервано: приложение было закрыто. Ждёт выгрузки." };
    }
    const status = s.status === "completed" || s.status === "failed" || s.status === "pending" ? s.status : "pending";
    return { url: s.url, status, message: s.message || (status === "pending" ? "Ожидает запуска." : "") };
  });
  const toRun = entries.filter((e) => e.status === "pending" || e.status === "failed").length;
  return { entries, interrupted, toRun };
}

export function restoreNotice(r: Restored): string | null {
  if (r.toRun === 0) return null;
  const word = r.entries.length === 1 ? "профиль" : "профилей";
  const tail = r.interrupted > 0 ? ` Прерванных выгрузкой: ${r.interrupted}.` : "";
  return `Восстановлена очередь: ${r.entries.length} ${word}, к выгрузке ${r.toRun}.${tail} Нажмите «Скачать», чтобы продолжить.`;
}
