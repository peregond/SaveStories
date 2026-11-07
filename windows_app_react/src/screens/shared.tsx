import { memo } from "react";
import { Banner, Pill } from "../components/ui";
import { IconTrash } from "../icons";
import { profileName } from "../parse";
import type { EntryStatus, Store } from "../store";

import { t, tr } from "../i18n";
type Tone = "" | "ok" | "run" | "err" | "warn";

export function statusPill(s: Store): { tone: Tone; label: string } {
  if (s.stopping) return { tone: "warn", label: t("Остановка") };
  if (s.busy === "batch" || s.busy === "reels") return { tone: "run", label: t("Выгрузка") };
  if (s.busy === "probe" || s.bootstrapping) return { tone: "run", label: t("Проверка") };
  if (s.workerReady === false) return { tone: "err", label: t("Ошибка среды") };
  if (s.runtime && !s.runtime.chromiumInstalled) return { tone: "warn", label: t("Нужен Chromium") };
  if (s.session === "error") return { tone: "err", label: t("Ошибка сессии") };
  if (s.session === "login_required") return { tone: "warn", label: t("Нужен вход") };
  if (s.session === "waiting_login") return { tone: "warn", label: t("Жду вход") };
  if (s.session === "ready") return { tone: "ok", label: t("Готово") };
  return { tone: "", label: t("Проверка…") };
}

const ENTRY: Record<EntryStatus, [Tone, string]> = {
  pending: ["", t("В очереди")], running: ["run", t("Скачивается")], completed: ["ok", t("Готово")], failed: ["err", t("Ошибка")], stopped: ["warn", t("Остановлено")],
};

const QueueRow = memo(function QueueRow({ url, status, message, disabled, onRemove }: {
  url: string; status: EntryStatus; message: string; disabled: boolean; onRemove: (url: string) => void;
}) {
  const [tone, label] = ENTRY[status];
  const name = profileName(url);
  return (
    <div className="item">
      <div className="avatar sm">{name[0]?.toUpperCase()}</div>
      <div className="grow"><div className="name">{name}</div><div className="hint">{message}</div></div>
      <Pill tone={tone}>{label}</Pill>
      <button className="btn sm ghost" aria-label={t("Убрать {0}", [name])} disabled={disabled} onClick={() => onRemove(url)}><IconTrash size={16} /></button>
    </div>
  );
});

/** Строки перерисовываются только при смене своих данных, а не всей очереди на каждую строку журнала. */
export function QueueList({ s }: { s: Store }) {
  return (
    <div className="list">
      {s.entries.map((e) => <QueueRow key={e.url} url={e.url} status={e.status} message={tr(e.message)} disabled={!!s.busy} onRemove={s.removeEntry} />)}
    </div>
  );
}

/** Баннеры о состоянии среды и входа: общие для экранов выгрузки. */
export function EnvironmentBanners({ s }: { s: Store }) {
  return (
    <>
      {s.runtime && !s.runtime.chromiumInstalled && s.workerReady !== false && (
        <BannerRow tone="warn" label={s.bootstrapping ? t("Скачиваю…") : t("Докачать Chromium")} text={t("Нужно докачать Chromium: браузер для выгрузки скачивается один раз (~150 МБ).")} busy={s.bootstrapping} onClick={s.installChromium} />
      )}
      {s.runtime?.chromiumInstalled && s.session === "login_required" && s.workerReady && (
        <BannerRow tone="warn" label={t("Войти в Instagram")} text={t("Сессия Instagram не найдена. Откройте браузер и войдите — приложение само найдёт сессию.")} onClick={s.login} />
      )}
      {s.session === "waiting_login" && <BannerRow tone="warn" text={t("Ожидаю вход в Instagram в отдельном окне браузера…")} />}
      {s.session === "error" && s.runtime?.chromiumInstalled && (
        <BannerRow tone="err" label={t("Проверить снова")} text={t("Не удалось проверить сессию Instagram: {0}", [s.sessionSummary])} busy={!!s.busy} onClick={() => void s.checkSession()} plain />
      )}
      {s.workerReady === false && <BannerRow tone="err" text={tr(s.workerSummary)} />}
      {s.notice && <BannerRow tone={s.notice.tone} text={tr(s.notice.text)} onClose={() => s.setNotice(null)} />}
    </>
  );
}

function BannerRow({ tone, text, label, onClick, busy, plain, onClose }: {
  tone: "ok" | "err" | "warn"; text: string; label?: string; onClick?: () => void; busy?: boolean; plain?: boolean; onClose?: () => void;
}) {
  return (
    <Banner tone={tone} onClose={onClose} action={label && onClick ? <button className={`btn sm ${plain ? "" : "primary"}`} disabled={busy} onClick={onClick}>{label}</button> : undefined}>
      {text}
    </Banner>
  );
}
