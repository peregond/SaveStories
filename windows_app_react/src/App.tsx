import { useEffect, useState, type ComponentType } from "react";
import { createApi, type Api, type Theme } from "./api";
import { IconQueue, IconReels, IconSettings, IconStories } from "./icons";
import { Queue } from "./screens/Queue";
import { Reels } from "./screens/Reels";
import { Settings } from "./screens/Settings";
import { Stories } from "./screens/Stories";
import { useStore, type Store } from "./store";

type Page = "stories" | "queue" | "reels" | "settings";
const NAV: { id: Page; title: string; sub: string; Icon: ComponentType<{ size?: number }> }[] = [
  { id: "stories", title: "Stories", sub: "Выгрузка из профилей", Icon: IconStories },
  { id: "queue", title: "Очередь", sub: "Пакетная выгрузка", Icon: IconQueue },
  { id: "reels", title: "Reels", sub: "Видео по ссылкам", Icon: IconReels },
];

export default function App() {
  const [api, setApi] = useState<Api | null>(null);
  useEffect(() => { void createApi().then(setApi); }, []);
  return api ? <Shell api={api} /> : null;
}

function useTheme(theme: Theme) {
  useEffect(() => {
    const mq = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => { document.documentElement.dataset.theme = theme === "system" ? (mq.matches ? "dark" : "light") : theme; };
    apply();
    mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, [theme]);
}

function Shell({ api }: { api: Api }) {
  const s = useStore(api);
  const [page, setPage] = useState<Page>(() => (new URLSearchParams(location.search).get("page") as Page) || "stories");
  useTheme(s.settings.theme);

  const current = page === "settings" ? { title: "Настройки", sub: "Вход, обновления и данные" } : NAV.find((n) => n.id === page)!;
  return (
    <div className="app">
      <nav className="sidebar" aria-label="Разделы">
        <div className="brand">
          <div className="brand-mark"><IconStories size={20} /></div>
          <div><div className="brand-name">SaveMe</div><div className="brand-sub">для Windows</div></div>
        </div>
        {NAV.map(({ id, title, Icon }) => (
          <button key={id} className="nav-item" aria-current={page === id ? "page" : undefined} onClick={() => setPage(id)}><Icon />{title}</button>
        ))}
        <div className="nav-spacer" />
        <UpdateButton s={s} />
        <button className="nav-item" aria-current={page === "settings" ? "page" : undefined} onClick={() => setPage("settings")}><IconSettings />Настройки</button>
        <div className="sidebar-foot"><span>Версия {s.info?.version ?? ""}</span></div>
      </nav>
      <main className="main">
        <header className="page-head">
          <div><h1 className="page-title">{current.title}</h1><div className="page-sub">{current.sub}</div></div>
        </header>
        <div className="page-body">
          {page === "stories" && <Stories s={s} />}
          {page === "queue" && <Queue s={s} />}
          {page === "reels" && <Reels s={s} />}
          {page === "settings" && <Settings s={s} />}
        </div>
      </main>
    </div>
  );
}

function UpdateButton({ s }: { s: Store }) {
  const { phase, release } = s.update;
  if (phase === "ready") return <button className="btn update-btn" onClick={s.installUpdate}>Установить {release?.version}</button>;
  if (phase === "available" && release) return <button className="btn update-btn" disabled={!s.info?.autoUpdate || !!s.busy} onClick={s.prepareUpdate}>Обновить до {release.version}</button>;
  if (phase === "downloading") return <div className="sidebar-foot">Загрузка обновления {s.update.percent}%</div>;
  return null;
}
