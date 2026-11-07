import { useState } from "react";
import { Card, Empty } from "../components/ui";
import { IconDownload, IconEmpty, IconStop } from "../icons";
import { parseReelLines } from "../parse";
import type { Store } from "../store";
import { EnvironmentBanners } from "./shared";

import { t, tr } from "../i18n";
export function Reels({ s }: { s: Store }) {
  const [text, setText] = useState("");
  const lines = parseReelLines(text);
  const total = lines.length + s.reels.queue.length;
  const running = s.busy === "reels";
  return (
    <>
      <EnvironmentBanners s={s} />
      <div className="cols">
        <div className="stack">
          <Card title={t("Ссылки на Reels")}>
            <div className="editor">
              <textarea value={text} onChange={(e) => setText(e.target.value)} disabled={running}
                placeholder={t("https://www.instagram.com/reel/…\nПо одной ссылке на строку")} aria-label={t("Ссылки на Reels")} />
              <span className="counter">{lines.length} {lines.length === 1 ? t("ссылка") : t("ссылок")}</span>
            </div>
            <div className="actions">
              <button className="btn go" disabled={!total || !!s.busy || s.runtime?.chromiumInstalled === false} onClick={async () => { if (await s.downloadReels(text)) setText(""); }}>
                <IconDownload /> {t("Скачать")}{total ? ` · ${total}` : ""}
              </button>
              <button className="btn danger" disabled={!running} onClick={s.stop}><IconStop /> {t("Стоп")}</button>
            </div>
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn sm ghost" disabled={!lines.length || !!s.busy} onClick={() => { s.addReels(text); setText(""); }}>{t("В очередь")}</button>
              <button className="btn sm ghost" disabled={!s.reels.failed.length || !!s.busy} onClick={s.retryFailedReels}>{t("Повторить ошибочные (")}{s.reels.failed.length})</button>
              <button className="btn sm ghost" disabled={!s.reels.queue.length || !!s.busy} onClick={s.clearReelsQueue}>{t("Очистить очередь")}</button>
            </div>
            {s.reels.summary && <p className="statusline">{tr(s.reels.summary)}</p>}
          </Card>
          {s.reels.queue.length > 0 && (
            <Card title={t("Очередь · {0}", [s.reels.queue.length])}>
              <div className="list">
                {s.reels.queue.map((u) => <div className="item" key={u}><div className="grow"><div className="name" title={u}>{u}</div></div></div>)}
              </div>
            </Card>
          )}
        </div>
        <Card title={t("Загрузки")} aside={s.reels.downloads.length ? <button className="btn sm ghost" onClick={s.openSaveDirectory}>{t("Открыть папку")}</button> : null}>
          {s.reels.downloads.length === 0 ? <Empty icon={<IconEmpty size={32} />} text={t("Скачанные видео появятся здесь")} /> : (
            <div className="list">
              {s.reels.downloads.slice(0, 100).map((name, i) => <div className="item" key={`${name}-${i}`}><div className="grow"><div className="name">{name}</div></div></div>)}
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
