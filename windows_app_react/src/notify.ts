// Уведомления и подсказка у значка в трее: что показать в конце работы и пока она идёт.

export type RunKind = "batch" | "reels" | "unik";
export interface NoticeLike { tone: "ok" | "err" | "warn"; text: string }

const TITLES: Record<RunKind, string> = {
  batch: "Выгрузка Stories",
  reels: "Выгрузка Reels",
  unik: "Уникализатор",
};

/** Текст системного уведомления после завершения работы; null — уведомлять не о чем (остановлено вручную, нет итога). */
export function finishNotification(kind: RunKind, notice: NoticeLike | null, stoppedByUser: boolean): { title: string; body: string } | null {
  if (stoppedByUser || !notice || !notice.text.trim() || /остановлен/i.test(notice.text)) return null;
  const prefix = notice.tone === "err" ? "Ошибка. " : "";
  return { title: TITLES[kind], body: `${prefix}${notice.text}`.slice(0, 220) };
}

/** Подсказка у значка в трее. */
export function trayStatus(busy: string | null, finished: number, total: number): string {
  if (busy === "batch") return total ? `SaveMe — выгрузка: ${Math.min(finished, total)} из ${total}` : "SaveMe — идёт выгрузка";
  if (busy === "reels") return "SaveMe — идёт выгрузка Reels";
  if (busy === "unik") return "SaveMe — идёт обработка";
  return "SaveMe";
}
