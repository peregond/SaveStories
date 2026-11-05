import { useState } from "react";
import { parseProfiles } from "../bridge";
import { Card, Empty, Segmented } from "../components/ui";
import { IconBookmark, IconDownload, IconEmpty, IconFolder, IconStop, IconTrash } from "../icons";
import type { Runner } from "../useRunner";

export function Stories({ r, ready }: { r: Runner; ready: boolean }) {
  const [text, setText] = useState("");
  const [saved, setSaved] = useState<string[][]>([]);
  const profiles = parseProfiles(text);
  const state = r.running ? "run" : r.entries.length && r.entries.every((e) => e.status === "done") ? "ok" : ready ? "ok" : "warn";
  const label = r.running ? "Выгрузка" : r.entries.length && r.entries.every((e) => e.status === "done") ? "Завершено" : ready ? "Готово" : "Нужен вход";

  return (
    <div className="cols">
      <div className="stack">
        <Card title="Профили">
          <div className="editor">
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder={"По одной ссылке или username на строку\ndian.vegas1\nhttps://www.instagram.com/stevensetu/"}
              aria-label="Список профилей"
            />
            <span className="counter">{profiles.length} {plural(profiles.length)}</span>
          </div>
          <div className="actions">
            <button className="btn go" disabled={!profiles.length || r.running} onClick={() => r.start(profiles)}>
              <IconDownload /> Скачать{profiles.length ? ` · ${profiles.length}` : ""}
            </button>
            <button className="btn danger" disabled={!r.running} onClick={r.stop}><IconStop /> Стоп</button>
          </div>
          <div className="row" style={{ marginTop: 10 }}>
            <button className="btn sm ghost" disabled={!profiles.length} onClick={() => { setSaved((s) => [profiles, ...s].slice(0, 6)); }}>
              <IconBookmark size={16} /> Запомнить набор
            </button>
            <button className="btn sm ghost" disabled={!text} onClick={() => setText("")}>Очистить</button>
          </div>
        </Card>

        <Card title="Параметры">
          <div className="field-label">Браузер</div>
          <Segmented label="Режим браузера" value={r.browser} onChange={r.setBrowser}
            options={[{ value: "background", label: "В фоне" }, { value: "visible", label: "Видимый" }]} />
          <div className="field-label">Что сохранять</div>
          <Segmented label="Тип медиа" value={r.media} onChange={r.setMedia}
            options={[{ value: "all", label: "Фото и видео" }, { value: "video", label: "Только видео" }]} />
          <div className="field-label">Папка</div>
          <div className="pathbox">
            <span title={r.directory}>{r.directory}</span>
            <button className="btn sm" onClick={r.pick}><IconFolder size={16} /> Выбрать</button>
          </div>
        </Card>
      </div>

      <div className="stack">
        <Card title="Состояние" aside={<span className={`pill ${state}`}><i />{label}</span>}>
          <div className="step">{r.step}</div>
          {r.entries.length > 0 && <div className="progress" role="progressbar" aria-valuenow={r.progress}><div style={{ width: `${r.progress}%` }} /></div>}
        </Card>

        <Card title="Результат">
          <div className="metrics">
            <Metric v={r.stats.profiles} l="Профилей" />
            <Metric v={r.stats.saved} l="Сохранено" />
            <Metric v={r.stats.files} l="Файлов" />
            <Metric v={r.stats.folders} l="Папок" />
          </div>
        </Card>

        <Card title="Недавние наборы">
          {saved.length === 0 ? <Empty icon={<IconEmpty size={28} />} text="Сохранённые наборы появятся здесь" /> : (
            <div className="list">
              {saved.map((s, i) => (
                <div className="item" key={i}>
                  <div className="grow"><div className="name">{s.slice(0, 2).join(", ")}{s.length > 2 ? ` +${s.length - 2}` : ""}</div><div className="hint">{s.length} {plural(s.length)}</div></div>
                  <button className="btn sm" onClick={() => setText(s.join("\n"))}>Вставить</button>
                  <button className="btn sm ghost" aria-label="Удалить набор" onClick={() => setSaved((x) => x.filter((_, j) => j !== i))}><IconTrash size={16} /></button>
                </div>
              ))}
            </div>
          )}
        </Card>

        {r.log.length > 0 && (
          <Card title="Журнал">
            <div className="log">{r.log.map((l, i) => <div key={i} className={l.startsWith("✓") ? "s" : undefined}>{l}</div>)}</div>
          </Card>
        )}
      </div>
    </div>
  );
}

const Metric = ({ v, l }: { v: number; l: string }) => <div className="metric"><b>{v}</b><span>{l}</span></div>;
function plural(n: number) { const m = n % 100, d = n % 10; return m > 10 && m < 15 ? "профилей" : d === 1 ? "профиль" : d >= 2 && d <= 4 ? "профиля" : "профилей"; }
