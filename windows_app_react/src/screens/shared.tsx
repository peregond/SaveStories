import { Pill } from "../components/ui";
import { IconTrash } from "../icons";
import { profileName } from "../parse";
import type { EntryStatus, Store } from "../store";

type Tone = "" | "ok" | "run" | "err" | "warn";

export function statusPill(s: Store): { tone: Tone; label: string } {
  if (s.stopping) return { tone: "warn", label: "Остановка" };
  if (s.busy === "batch" || s.busy === "reels") return { tone: "run", label: "Выгрузка" };
  if (s.busy === "probe") return { tone: "run", label: "Проверка" };
  if (s.workerReady === false) return { tone: "err", label: "Ошибка среды" };
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
