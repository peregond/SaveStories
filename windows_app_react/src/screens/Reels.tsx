import { useState } from "react";
import { Card, Empty } from "../components/ui";
import { IconDownload, IconEmpty } from "../icons";

export function Reels() {
  const [text, setText] = useState("");
  const links = text.split(/\s+/).filter((l) => /instagram\.com\/(reel|p)\//i.test(l));
  return (
    <div className="cols">
      <Card title="Ссылки на Reels">
        <div className="editor">
          <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder={"https://www.instagram.com/reel/…\nПо одной ссылке на строку"} aria-label="Ссылки на Reels" />
          <span className="counter">{links.length} ссылок</span>
        </div>
        <div className="actions"><button className="btn go" disabled={!links.length}><IconDownload /> Скачать</button><span /></div>
      </Card>
      <Card title="Загрузки"><Empty icon={<IconEmpty size={32} />} text="Скачанные видео появятся здесь" /></Card>
    </div>
  );
}
