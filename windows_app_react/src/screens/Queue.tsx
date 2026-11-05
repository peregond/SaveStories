import { useState } from "react";
import { Banner, Card, Empty } from "../components/ui";
import { IconDownload, IconEmpty, IconStop } from "../icons";
import { parseBatchLinks } from "../parse";
import type { Store } from "../store";
import { QueueList } from "./shared";

export function Queue({ s }: { s: Store }) {
  const [text, setText] = useState("");
  const links = parseBatchLinks(text);
  return (
    <>
      {s.notice && <Banner tone={s.notice.tone} onClose={() => s.setNotice(null)}>{s.notice.text}</Banner>}
      <div className="cols">
        <Card title="Добавить профили">
          <div className="editor">
            <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder={"Вставьте ссылки или username,\nпо одному на строку"} aria-label="Список профилей" />
            <span className="counter">{links.length}</span>
          </div>
          <div className="actions">
            <button className="btn go" disabled={!!s.busy || (!links.length && !s.pending)} onClick={async () => { const v = text; setText(""); await s.startQueue(v); }}>
              <IconDownload /> {!links.length && s.retryOnly ? "Повторить ошибочные" : "Скачать очередь"}{links.length + s.pending ? ` · ${links.length + s.pending}` : ""}
            </button>
            <button className="btn danger" disabled={s.busy !== "batch"} onClick={s.stop}><IconStop /> Стоп</button>
          </div>
          <div className="row" style={{ marginTop: 10 }}>
            <button className="btn sm ghost" disabled={!links.length || !!s.busy} onClick={() => { s.addProfiles(text); setText(""); }}>Только добавить в очередь</button>
          </div>
        </Card>
        <Card title="Очередь" aside={s.entries.length ? <button className="btn sm ghost" disabled={!!s.busy} onClick={s.clearQueue}>Очистить</button> : null}>
          {s.entries.length === 0 ? <Empty icon={<IconEmpty size={32} />} text="Очередь пока пуста" /> : <QueueList s={s} />}
        </Card>
      </div>
    </>
  );
}
