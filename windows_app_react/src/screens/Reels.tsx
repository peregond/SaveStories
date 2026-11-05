import { useState } from "react";
import { Banner, Card, Empty } from "../components/ui";
import { IconDownload, IconEmpty, IconStop } from "../icons";
import { parseReelLinks } from "../parse";
import type { Store } from "../store";

export function Reels({ s }: { s: Store }) {
  const [text, setText] = useState("");
  const links = parseReelLinks(text);
  const running = s.busy === "reels";
  return (
    <>
      {s.notice && <Banner tone={s.notice.tone} onClose={() => s.setNotice(null)}>{s.notice.text}</Banner>}
      <div className="cols">
        <Card title="Ссылки на Reels">
          <div className="editor">
            <textarea value={text} onChange={(e) => setText(e.target.value)} disabled={running}
              placeholder={"https://www.instagram.com/reel/…\nПо одной ссылке на строку"} aria-label="Ссылки на Reels" />
            <span className="counter">{links.length} {links.length === 1 ? "ссылка" : "ссылок"}</span>
          </div>
          <div className="actions">
            <button className="btn go" disabled={!links.length || !!s.busy} onClick={async () => { if (await s.downloadReels(text)) setText(""); }}>
              <IconDownload /> Скачать{links.length ? ` · ${links.length}` : ""}
            </button>
            <button className="btn danger" disabled={!running} onClick={s.stop}><IconStop /> Стоп</button>
          </div>
          {s.reelsMessage && <p className="hint" style={{ marginTop: 12 }}>{s.reelsMessage}</p>}
        </Card>
        <Card title="Загрузки" aside={s.reelItems.length ? <button className="btn sm ghost" onClick={s.openSaveDirectory}>Открыть папку</button> : null}>
          {s.reelItems.length === 0 ? <Empty icon={<IconEmpty size={32} />} text="Скачанные видео появятся здесь" /> : (
            <div className="list">
              {s.reelItems.map((it) => (
                <div className="item" key={it.id + it.localPath}>
                  <div className="grow"><div className="name" title={it.localPath}>{it.localPath.split(/[\\/]/).pop()}</div><div className="hint">{it.mediaType}</div></div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
