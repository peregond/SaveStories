import { useEffect, useState, type ComponentType } from "react";
import { IconQueue, IconReels, IconSettings, IconStories } from "./icons";
import { Queue } from "./screens/Queue";
import { Reels } from "./screens/Reels";
import { Settings, type Theme } from "./screens/Settings";
import { Stories } from "./screens/Stories";
import { useRunner } from "./useRunner";

const VERSION = "0.6.85";
type Page = "stories" | "queue" | "reels" | "settings";
const NAV: { id: Page; title: string; sub: string; Icon: ComponentType<{ size?: number }> }[] = [
  { id: "stories", title: "Stories", sub: "Выгрузка из профилей", Icon: IconStories },
  { id: "queue", title: "Очередь", sub: "Пакетная выгрузка", Icon: IconQueue },
  { id: "reels", title: "Reels", sub: "Видео по ссылкам", Icon: IconReels },
];

export default function App() {
  const [page, setPage] = useState<Page>(() => (new URLSearchParams(location.search).get("page") as Page) || "stories");
  const [theme, setTheme] = useState<Theme>(() => (new URLSearchParams(location.search).get("theme") as Theme) || "system");
  const runner = useRunner();

  useEffect(() => {
    const mq = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => { document.documentElement.dataset.theme = theme === "system" ? (mq.matches ? "dark" : "light") : theme; };
    apply(); mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, [theme]);

  const current = page === "settings" ? { title: "Настройки", sub: "Тема, вход и обновления" } : NAV.find((n) => n.id === page)!;
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
        <button className="nav-item" aria-current={page === "settings" ? "page" : undefined} onClick={() => setPage("settings")}><IconSettings />Настройки</button>
        <div className="sidebar-foot"><span>Версия {VERSION}</span></div>
      </nav>
      <main className="main">
        <header className="page-head">
          <div><h1 className="page-title">{current.title}</h1><div className="page-sub">{current.sub}</div></div>
        </header>
        <div className="page-body">
          {page === "stories" && <Stories r={runner} ready />}
          {page === "queue" && <Queue r={runner} />}
          {page === "reels" && <Reels />}
          {page === "settings" && <Settings theme={theme} setTheme={setTheme} version={VERSION} />}
        </div>
      </main>
    </div>
  );
}
