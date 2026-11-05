import { useState } from "react";
import { Card, Empty } from "../components/ui";
import { IconDownload, IconEmpty, IconStop } from "../icons";
import { parseProfiles } from "../parse";
import type { Store } from "../store";
import { EnvironmentBanners, QueueList } from "./shared";
import { LogCard } from "./Stories";

/** «Списочная»: пакетная выгрузка. Очередь и параметры общие с экраном Stories. */
export function Queue({ s }: { s: Store }) {
  const [text, setText] = useState("");
  const links = parseProfiles(text);
  const total = links.length + s.pending;
  return (
    <>
      <EnvironmentBanners s={s} />
      <div className="cols">
        <div className="stack">
          <Card title="Добавить профили">
            <div className="editor">
              <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder={"Вставьте ссылки или username,\nпо одному на строку"} aria-label="Список профилей" />
              <span className="counter">{links.length}</span>
            </div>
            <div className="actions">
              <button className="btn go" disabled={!!s.busy || !total || s.runtime?.chromiumInstalled === false} onClick={async () => { const v = text; setText(""); await s.startQueue(v); }}>
                <IconDownload /> {!links.length && s.retryOnly ? "Повторить ошибочные" : "Скачать очередь"}{total ? ` · ${total}` : ""}
              </button>
              <button className="btn danger" disabled={s.busy !== "batch"} onClick={s.stop}><IconStop /> Стоп</button>
            </div>
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn sm ghost" disabled={!links.length || !!s.busy} onClick={() => { s.addProfiles(text); setText(""); }}>Только добавить в очередь</button>
              <button className="btn sm ghost" disabled={!text} onClick={() => setText("")}>Очистить поле</button>
            </div>
          </Card>
          {s.log.length > 0 && <LogCard lines={s.log} />}
        </div>
        <Card title="Очередь" aside={s.entries.length ? (
          <span className="row" style={{ gap: 4 }}>
            {s.failedCount > 0 && <button className="btn sm ghost" disabled={!!s.busy} onClick={s.retryFailed}>Только ошибочные</button>}
            <button className="btn sm ghost" disabled={!!s.busy} onClick={s.clearQueue}>Очистить</button>
          </span>
        ) : null}>
          <div className="hint" style={{ marginBottom: 10 }}>Очередь: {s.entries.length} {s.entries.length === 1 ? "профиль" : "профилей"} · {s.settings.downloadMode === "background" ? "в фоне" : "видимо"} · {s.settings.mediaFilter === "video_only" ? "только видео" : "фото и видео"}</div>
          {s.entries.length === 0 ? <Empty icon={<IconEmpty size={32} />} text="Очередь пока пуста" /> : <QueueList s={s} />}
        </Card>
      </div>
    </>
  );
}
