import { t } from "./i18n";
// Уведомления и подсказка у значка в трее: что показать в конце работы и пока она идёт.

export type RunKind = "batch" | "reels" | "unik";
export interface NoticeLike { tone: "ok" | "err" | "warn"; text: string }

const TITLES: Record<RunKind, string> = {
  batch: t("Выгрузка Stories"),
  reels: t("Выгрузка Reels"),
  unik: t("Уникализатор"),
};

/** Текст системного уведомления после завершения работы; null — уведомлять не о чем (остановлено вручную, нет итога). */
export function finishNotification(kind: RunKind, notice: NoticeLike | null, stoppedByUser: boolean): { title: string; body: string } | null {
  if (stoppedByUser || !notice || !notice.text.trim() || /остановлен|stopped/i.test(notice.text)) return null;
  const prefix = notice.tone === "err" ? t("Ошибка. ") : "";
  return { title: TITLES[kind], body: `${prefix}${notice.text}`.slice(0, 220) };
}

/** Подсказка у значка в трее. */
export function trayStatus(busy: string | null, finished: number, total: number): string {
  if (busy === "batch") return total ? t("SaveMe — выгрузка: {0} из {1}", [Math.min(finished, total), total]) : t("SaveMe — идёт выгрузка");
  if (busy === "reels") return t("SaveMe — идёт выгрузка Reels");
  if (busy === "unik") return t("SaveMe — идёт обработка");
  return "SaveMe";
}
