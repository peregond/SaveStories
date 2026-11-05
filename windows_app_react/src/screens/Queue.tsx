import { useState } from "react";
import { parseProfiles } from "../bridge";
import { Card, Empty } from "../components/ui";
import { IconDownload, IconEmpty, IconStop } from "../icons";
import type { Runner } from "../useRunner";

const STATUS: Record<string, [string, string]> = {
  pending: ["", "Ожидает"], running: ["run", "В работе"], done: ["ok", "Готово"], failed: ["err", "Ошибка"],
};

export function Queue({ r }: { r: Runner }) {
  const [text, setText] = useState("");
  const profiles = parseProfiles(text);
  return (
    <div className="cols">
      <Card title="Добавить профили">
        <div className="editor">
          <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder={"Вставьте ссылки или username,\nпо одному на строку"} aria-label="Список профилей" />
          <span className="counter">{profiles.length}</span>
        </div>
        <div className="actions">
          <button className="btn go" disabled={!profiles.length || r.running} onClick={() => { r.start(profiles); setText(""); }}><IconDownload /> Скачать очередь</button>
          <button className="btn danger" disabled={!r.running} onClick={r.stop}><IconStop /> Стоп</button>
        </div>
      </Card>
      <Card title="Очередь" aside={r.entries.length ? <button className="btn sm ghost" disabled={r.running} onClick={r.clear}>Очистить</button> : null}>
        {r.entries.length === 0 ? <Empty icon={<IconEmpty size={32} />} text="Очередь пока пуста" /> : (
          <div className="list">
            {r.entries.map((e) => {
              const [cls, label] = STATUS[e.status];
              return (
                <div className="item" key={e.url}>
                  <div className="avatar">{e.url[0].toUpperCase()}</div>
                  <div className="grow"><div className="name">{e.url}</div><div className="hint">{e.message}</div></div>
                  <span className={`pill ${cls}`}><i />{label}</span>
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}
