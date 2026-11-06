import { lazy, Suspense, useEffect, useRef, useState, type ComponentType } from "react";
import { createApi, type Api } from "./api";
import { Logo } from "./components/Logo";
import { Dialog } from "./components/ui";
import { IconReels, IconSettings, IconSort, IconStories, IconUnik } from "./icons";
import { themeForHour } from "./parse";
import { Stories } from "./screens/Stories";
import { useStore, type Store } from "./store";

// Остальные экраны грузятся при первом открытии: меньше JS при старте и в памяти.
const Reels = lazy(() => import("./screens/Reels").then((m) => ({ default: m.Reels })));
const Unikalizer = lazy(() => import("./screens/Unikalizer").then((m) => ({ default: m.Unikalizer })));
const Sorting = lazy(() => import("./screens/Sorting").then((m) => ({ default: m.Sorting })));
const Settings = lazy(() => import("./screens/Settings").then((m) => ({ default: m.Settings })));

type Page = "stories" | "reels" | "unik" | "sorting" | "settings";
const NAV: { id: Page; title: string; sub: string; Icon: ComponentType<{ size?: number }> }[] = [
  { id: "stories", title: "Stories", sub: "Выгрузка из профилей", Icon: IconStories },
  { id: "reels", title: "Reels", sub: "Видео по ссылкам", Icon: IconReels },
  { id: "unik", title: "Уникализатор", sub: "Обработка видео и картинок: форматы, вариации, плашка 18+", Icon: IconUnik },
  { id: "sorting", title: "Сортировка", sub: "Разложить файлы по странам и блогерам", Icon: IconSort },
];

export default function App() {
  const [api, setApi] = useState<Api | null>(null);
  useEffect(() => { void createApi().then(setApi); }, []);
  return api ? <Shell api={api} /> : null;
}

/** Итоговая тема: по времени суток, иначе выбранная (или системная). */
function useTheme(api: Api, theme: "system" | "light" | "dark", byTime: boolean, loaded: boolean) {
  const applied = useRef("");
  useEffect(() => {
    if (!loaded) return;
    const mq = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const resolved = byTime ? themeForHour(new Date().getHours()) : theme === "system" ? (mq.matches ? "dark" : "light") : theme;
      document.documentElement.dataset.theme = resolved;
      const windowTheme = byTime || theme !== "system" ? resolved : "system";
      if (applied.current === `${windowTheme}|${resolved}`) return;
      applied.current = `${windowTheme}|${resolved}`;
      void api.setWindowTheme(windowTheme).catch(() => {});
    };
    apply();
    mq.addEventListener("change", apply);
    const timer = window.setInterval(apply, 60_000);
    return () => { mq.removeEventListener("change", apply); window.clearInterval(timer); };
  }, [api, theme, byTime, loaded]);
}

function Shell({ api }: { api: Api }) {
  const s = useStore(api);
  const [page, setPage] = useState<Page>(() => (new URLSearchParams(location.search).get("page") as Page) || "stories");
  useTheme(api, s.settings.theme, s.settings.automaticThemeByTime, s.loaded);

  // Материал окна и показ окна: после загрузки настроек, один раз, после первой отрисовки.
  useEffect(() => {
    if (!s.loaded || !s.info) return;
    document.documentElement.dataset.glass = s.info.nativeGlass ? "native" : "fallback";
    const id = requestAnimationFrame(() => requestAnimationFrame(() => void api.appReady().catch(() => {})));
    return () => cancelAnimationFrame(id);
  }, [api, s.loaded, s.info]);

  // Свёрнутое окно: останавливаем бесконечные анимации.
  useEffect(() => {
    const sync = () => { document.documentElement.dataset.hidden = String(document.hidden); };
    sync();
    document.addEventListener("visibilitychange", sync);
    return () => document.removeEventListener("visibilitychange", sync);
  }, []);

  const current = page === "settings" ? { title: "Настройки", sub: "Вход, модули, обновления и данные" } : NAV.find((n) => n.id === page)!;
  return (
    <div className="app">
      <nav className="sidebar" aria-label="Разделы">
        <div className="brand">
          <Logo />
          <div className="brand-name">SaveMe</div>
        </div>
        {NAV.map(({ id, title, Icon }) => (
          <button key={id} className="nav-item" aria-current={page === id ? "page" : undefined} onClick={() => setPage(id)}><Icon /><span>{title}</span></button>
        ))}
        <div className="nav-spacer" />
        <UpdateButton s={s} />
        <button className="nav-item" aria-current={page === "settings" ? "page" : undefined} onClick={() => setPage("settings")}><IconSettings /><span>Настройки</span></button>
        <div className="sidebar-foot"><span>Версия {s.info?.version ?? ""}</span></div>
      </nav>
      <main className="main">
        <header className="page-head">
          <div><h1 className="page-title">{current.title}</h1><div className="page-sub">{current.sub}</div></div>
        </header>
        <div className="page-body">
          <Suspense fallback={null}>
            {page === "stories" && <Stories s={s} />}
            {page === "reels" && <Reels s={s} />}
            {page === "unik" && <Unikalizer s={s} />}
            {page === "sorting" && <Sorting s={s} />}
            {page === "settings" && <Settings s={s} />}
          </Suspense>
        </div>
      </main>
      {s.cleanupOffer && (
        <Dialog title={s.cleanupOffer.title} primary="Удалить" secondary="Не удалять" onPrimary={s.confirmCleanup} onSecondary={s.dismissCleanup}>
          {`${s.cleanupOffer.intro}\n\n${previewNames(s.cleanupOffer.folders)}`}
        </Dialog>
      )}
    </div>
  );
}

function previewNames(folders: string[]): string {
  const names = folders.map((f) => f.split(/[\\/]/).filter(Boolean).pop() ?? f).slice(0, 12);
  return folders.length > 12 ? `${names.join("\n")}\nи ещё ${folders.length - 12}` : names.join("\n");
}

function UpdateButton({ s }: { s: Store }) {
  const { phase, release } = s.update;
  if (phase === "ready") return <button className="btn update-btn" disabled={s.running} title={s.running ? "Идёт выгрузка" : "Приложение перезапустится"} onClick={s.installUpdate}>Установить {release?.version}</button>;
  if (phase === "available" && release) return <button className="btn update-btn" disabled={!s.info?.autoUpdate || !!s.busy} onClick={s.prepareUpdate}>Обновить до {release.version}</button>;
  if (phase === "downloading") return <div className="sidebar-foot">Загрузка обновления {s.update.percent}%</div>;
  return null;
}
