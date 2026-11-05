import { Banner, Pill } from "../components/ui";
import { IconTrash } from "../icons";
import { profileName } from "../parse";
import type { EntryStatus, Store } from "../store";

type Tone = "" | "ok" | "run" | "err" | "warn";

export function statusPill(s: Store): { tone: Tone; label: string } {
  if (s.stopping) return { tone: "warn", label: "Остановка" };
  if (s.busy === "batch" || s.busy === "reels") return { tone: "run", label: "Выгрузка" };
  if (s.busy === "probe" || s.bootstrapping) return { tone: "run", label: "Проверка" };
  if (s.workerReady === false) return { tone: "err", label: "Ошибка среды" };
  if (s.runtime && !s.runtime.chromiumInstalled) return { tone: "warn", label: "Нужен Chromium" };
  if (s.session === "error") return { tone: "err", label: "Ошибка сессии" };
  if (s.session === "login_required") return { tone: "warn", label: "Нужен вход" };
  if (s.session === "waiting_login") return { tone: "warn", label: "Жду вход" };
  if (s.session === "ready") return { tone: "ok", label: "Готово" };
  return { tone: "", label: "Проверка…" };
}

const ENTRY: Record<EntryStatus, [Tone, string]> = {
  pending: ["", "В очереди"], running: ["run", "Скачивается"], completed: ["ok", "Готово"], failed: ["err", "Ошибка"], stopped: ["warn", "Остановлено"],
};

export function QueueList({ s }: { s: Store }) {
  return (
    <div className="list">
      {s.entries.map((e) => {
        const [tone, label] = ENTRY[e.status];
        const name = profileName(e.url);
        return (
          <div className="item" key={e.url}>
            <div className="avatar sm">{name[0]?.toUpperCase()}</div>
            <div className="grow"><div className="name">{name}</div><div className="hint">{e.message}</div></div>
            <Pill tone={tone}>{label}</Pill>
            <button className="btn sm ghost" aria-label={`Убрать ${name}`} disabled={!!s.busy} onClick={() => s.removeEntry(e.url)}><IconTrash size={16} /></button>
          </div>
        );
      })}
    </div>
  );
}

/** Баннеры о состоянии среды и входа: общие для экранов выгрузки. */
export function EnvironmentBanners({ s }: { s: Store }) {
  return (
    <>
      {s.runtime && !s.runtime.chromiumInstalled && s.workerReady !== false && (
        <BannerRow tone="warn" label={s.bootstrapping ? "Скачиваю…" : "Докачать Chromium"} text="Нужно докачать Chromium: браузер для выгрузки скачивается один раз (~150 МБ)." busy={s.bootstrapping} onClick={s.installChromium} />
      )}
      {s.runtime?.chromiumInstalled && s.session === "login_required" && s.workerReady && (
        <BannerRow tone="warn" label="Войти в Instagram" text="Сессия Instagram не найдена. Откройте браузер и войдите — приложение само найдёт сессию." onClick={s.login} />
      )}
      {s.session === "waiting_login" && <BannerRow tone="warn" text="Ожидаю вход в Instagram в отдельном окне браузера…" />}
      {s.session === "error" && s.runtime?.chromiumInstalled && (
        <BannerRow tone="err" label="Проверить снова" text={`Не удалось проверить сессию Instagram: ${s.sessionSummary}`} busy={!!s.busy} onClick={() => void s.checkSession()} plain />
      )}
      {s.workerReady === false && <BannerRow tone="err" text={s.workerSummary} />}
      {s.notice && <BannerRow tone={s.notice.tone} text={s.notice.text} onClose={() => s.setNotice(null)} />}
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
