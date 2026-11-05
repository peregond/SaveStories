import { useState } from "react";
import { Card, Empty, Pill, Segmented, Switch } from "../components/ui";
import { IconBookmark, IconDownload, IconEmpty, IconFolder, IconStop, IconTrash } from "../icons";
import { parseProfiles, pluralProfiles, profileName } from "../parse";
import type { Store } from "../store";
import { EnvironmentBanners, QueueList, statusPill } from "./shared";

export function Stories({ s }: { s: Store }) {
  const [text, setText] = useState("");
  const links = parseProfiles(text);
  const total = links.length + s.pending;
  const pill = statusPill(s);
  const canRun = s.runtime?.chromiumInstalled !== false;

  const run = async () => {
    const value = text;
    setText("");
    await s.startQueue(value);
  };

  return (
    <>
      <EnvironmentBanners s={s} />
      <div className="cols">
        <div className="stack">
          <Card title="Профили">
            <div className="editor">
              <textarea
                value={text}
                onChange={(e) => setText(e.target.value)}
                disabled={s.busy === "batch"}
                placeholder={"По одной ссылке или username на строку\ndian.vegas1\nhttps://www.instagram.com/stevensetu/"}
                aria-label="Список профилей"
              />
              <span className="counter">{links.length} {pluralProfiles(links.length)}</span>
            </div>
            <div className="actions">
              <button className="btn go" disabled={(!total && !s.settings.notionInfluencerEnabled) || !!s.busy || !canRun} onClick={run}>
                <IconDownload /> {!links.length && s.retryOnly ? "Повторить" : "Скачать"}{total ? ` · ${total}` : ""}
              </button>
              <button className="btn danger" disabled={s.busy !== "batch" && s.busy !== "reels"} onClick={s.stop}><IconStop /> Стоп</button>
            </div>
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn sm ghost" disabled={!links.length || !!s.busy} onClick={() => { s.addProfiles(text); setText(""); }}>В очередь</button>
              <button className="btn sm ghost" disabled={!links.length} onClick={() => s.rememberList(links)}><IconBookmark size={16} /> Запомнить набор</button>
              <button className="btn sm ghost" disabled={!text} onClick={() => setText("")}>Очистить</button>
            </div>
          </Card>

          <Card title="Список из Notion">
            <div className="setting" style={{ paddingTop: 0 }}>
              <div>
                <div>Автосписок инфлюенсеров</div>
                <div className="hint">{s.notionSummary || (s.settings.notionInfluencerEnabled ? "Перед запуском очередь обновится из Notion не чаще одного раза в день." : "Автосписок Notion выключен.")}</div>
              </div>
              <Switch checked={s.settings.notionInfluencerEnabled} disabled={!!s.busy || s.notionBusy} label="Автосписок Notion" onChange={(v) => s.updateSettings({ notionInfluencerEnabled: v })} />
            </div>
            <div className="row">
              <button className="btn sm" disabled={!!s.busy || s.notionBusy} onClick={() => void s.refreshNotionInfluencers({ replace: true, force: true })}>
                {s.notionBusy ? "Загружаю…" : "Обновить из Notion"}
              </button>
            </div>
          </Card>

          <Card title="Параметры">
            <div className="field-label">Браузер</div>
            <Segmented label="Режим браузера" value={s.settings.downloadMode} disabled={!!s.busy} onChange={(v) => s.updateSettings({ downloadMode: v })}
              options={[{ value: "background", label: "В фоне" }, { value: "visible", label: "Видимый" }]} />
            <div className="hint" style={{ marginTop: 6 }}>{s.settings.downloadMode === "background" ? "Браузер скрыт, работает незаметно." : "Откроется окно Chromium во время выгрузки."}</div>
            <div className="field-label">Что сохранять</div>
            <Segmented label="Тип медиа" value={s.settings.mediaFilter} disabled={!!s.busy} onChange={(v) => s.updateSettings({ mediaFilter: v })}
              options={[{ value: "all", label: "Фото и видео" }, { value: "video_only", label: "Только видео" }]} />
            <div className="field-label">Папка сохранения</div>
            <div className="pathbox">
              <span title={s.settings.saveDirectory}>{s.settings.saveDirectory}</span>
              <button className="btn sm" disabled={!!s.busy} onClick={s.pickDirectory}><IconFolder size={16} /> Выбрать</button>
              <button className="btn sm ghost" disabled={!!s.busy} onClick={s.openSaveDirectory}>Открыть</button>
            </div>
          </Card>
        </div>

        <div className="stack">
          <Card title="Состояние" aside={<Pill tone={pill.tone}>{pill.label}</Pill>}>
            <div className="step">{s.step}</div>
            {s.entries.length > 0 && (
              s.busy === "batch"
                ? <div className="progress indeterminate" role="progressbar" aria-label="Выгрузка идёт"><div /></div>
                : <div className="progress" role="progressbar" aria-valuenow={s.progress}><div style={{ width: `${s.progress}%` }} /></div>
            )}
          </Card>

          <Card title="Результат">
            <div className="metrics five">
              <Metric v={s.stats.profiles} l="Профилей" />
              <Metric v={`${s.stats.done}/${s.stats.profiles}`} l="Обработано" />
              <Metric v={s.stats.found} l="Найдено" />
              <Metric v={s.stats.saved} l="Сохранено" />
              <Metric v={s.stats.files} l="Файлов" />
              <Metric v={s.live.folders} l="Папок создано" />
            </div>
            <div className="live">Файлов загружено: {s.live.files}  ·  Папок создано: {s.live.folders}</div>
          </Card>

          {s.entries.length > 0 && (
            <Card title="Очередь" aside={
              <span className="row" style={{ gap: 4 }}>
                {s.failedCount > 0 && <button className="btn sm ghost" disabled={!!s.busy} onClick={s.retryFailed}>Только ошибочные</button>}
                <button className="btn sm ghost" disabled={!!s.busy} onClick={s.clearQueue}>Очистить</button>
              </span>
            }>
              <QueueList s={s} />
            </Card>
          )}

          <Card title="Недавние наборы">
            {s.settings.recentLists.length === 0 ? <Empty icon={<IconEmpty size={28} />} text="Сохранённые наборы появятся здесь" /> : (
              <div className="list">
                {s.settings.recentLists.map((list, i) => (
                  <div className="item" key={list.join("|")}>
                    <div className="grow">
                      <div className="name">{list.slice(0, 2).join(", ")}{list.length > 2 ? ` +${list.length - 2}` : ""}</div>
                      <div className="hint">{list.length} {pluralProfiles(list.length)}</div>
                    </div>
                    <button className="btn sm" disabled={!!s.busy} onClick={() => { s.addProfiles(list.map(profileName).join("\n")); }}>В очередь</button>
                    <button className="btn sm ghost" aria-label="Удалить набор" onClick={() => s.removeList(i)}><IconTrash size={16} /></button>
                  </div>
                ))}
              </div>
            )}
          </Card>

          {s.log.length > 0 && <LogCard lines={s.log} />}
        </div>
      </div>
    </>
  );
}

const Metric = ({ v, l }: { v: number | string; l: string }) => <div className="metric"><b>{v}</b><span>{l}</span></div>;

export function LogCard({ lines }: { lines: string[] }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    await navigator.clipboard?.writeText(lines.join("\n")).catch(() => {});
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };
  return (
    <Card title="Журнал" aside={<button className="btn sm ghost" onClick={copy}>{copied ? "Скопировано" : "Копировать"}</button>}>
      <div className="log" tabIndex={0}>{lines.slice(-120).map((l, i) => (
        <div key={i} className={/error|ошибк|✗|failed/i.test(l) ? "e" : /_done=|✓/.test(l) ? "s" : undefined}>{l}</div>
      ))}</div>
    </Card>
  );
}
