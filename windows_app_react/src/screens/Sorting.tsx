import { useEffect, useRef, useState } from "react";
import { Card, Empty, PathRow, StepTitle, Switch } from "../components/ui";
import { IconBroom, IconCopy, IconEmpty, IconSort, IconUndo } from "../icons";
import type { Store } from "../store";
import { EnvironmentBanners } from "./shared";

export function Sorting({ s }: { s: Store }) {
  const so = s.sorting;
  const cfg = s.settings;
  const [rules, setRules] = useState(cfg.sortingRules);
  const latest = useRef({ rules, saved: cfg.sortingRules });
  latest.current = { rules, saved: cfg.sortingRules };

  // Правила могут обновиться снаружи (Notion) — показываем их в поле.
  useEffect(() => { setRules(cfg.sortingRules); }, [cfg.sortingRules]);
  // Ввод сохраняем и разбираем с небольшой задержкой, а при уходе с экрана — сразу.
  useEffect(() => {
    if (rules === cfg.sortingRules) return;
    const id = window.setTimeout(() => void so.setRules(rules), 500);
    return () => window.clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rules]);
  useEffect(() => () => { if (latest.current.rules !== latest.current.saved) void so.setRules(latest.current.rules); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const remembered = [...cfg.rememberedBloggers].sort((a, b) => a.countryFolder.localeCompare(b.countryFolder) || a.username.localeCompare(b.username));
  const sorting = so.busy === "sort";

  return (
    <>
      <EnvironmentBanners s={s} />
      <div className="cols sorting">
        <div className="stack">
          <Card title="Разложить файлы из папки «На перенос» по странам и блогерам">
            <StepTitle>0. Удалить пустые папки</StepTitle>
            <div className="hint" style={{ marginBottom: 8 }}>Работает отдельно от сортировки и не трогает папку «На перенос».</div>
            <PathRow path={cfg.emptyFolderCleanupDirectory} placeholder="Папка ещё не выбрана." onPick={() => void so.pick("cleanup")} onOpen={() => void so.open(cfg.emptyFolderCleanupDirectory)} />
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn" onClick={() => void so.cleanEmptyFolders()}><IconBroom size={16} /> Удалить пустые папки</button>
            </div>
            <div className="hint" style={{ marginTop: 8 }}>{so.cleanupStatus}</div>

            <StepTitle>1. Укажи, где находится папка «На перенос»</StepTitle>
            <PathRow path={cfg.sortingSourceDirectory} placeholder="Папка ещё не выбрана." onPick={() => void so.pick("source")} onOpen={() => void so.open(cfg.sortingSourceDirectory)} />

            <StepTitle>2. Выбери папку WhiteList INF Исходники</StepTitle>
            <PathRow path={cfg.sortingDestinationDirectory} placeholder="Папка ещё не выбрана." onPick={() => void so.pick("destination")} onOpen={() => void so.open(cfg.sortingDestinationDirectory)} />

            <StepTitle>3. Правила</StepTitle>
            <div className="setting" style={{ paddingTop: 0 }}>
              <div>
                <div>Обновлять правила из Notion</div>
                <div className="hint">{so.rulesSummary || (cfg.notionRoutingRulesEnabled ? "Перед сортировкой правила обновятся из Notion не чаще одного раза в день." : "Автоправила Notion выключены.")}</div>
              </div>
              <Switch checked={cfg.notionRoutingRulesEnabled} label="Правила из Notion" disabled={so.busy === "notion"} onChange={(v) => s.updateSettings({ notionRoutingRulesEnabled: v })} />
            </div>
            <div className="row" style={{ marginBottom: 10 }}>
              <button className="btn sm" disabled={so.busy !== null} onClick={() => void so.refreshNotionRules(true)}>{so.busy === "notion" ? "Загружаю…" : "Обновить из Notion"}</button>
            </div>
            <textarea className="rules" value={rules} onChange={(e) => setRules(e.target.value)} spellCheck={false} aria-label="Правила сортировки"
              placeholder={"nick = Germany (DE)\nnick2 = Australia (AU)/Папка блогера"} />

            <StepTitle>4. Перенос</StepTitle>
            <div className="statusline" style={{ marginTop: 0 }}>{so.status}</div>
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn go" style={{ height: 40, fontSize: 14 }} disabled={so.busy !== null} onClick={() => void so.run("source")}><IconSort size={18} /> {sorting ? "Раскладываю…" : "Разложить из папки Перенос"}</button>
              <button className="btn" disabled={so.busy !== null} onClick={() => void so.run("latest")}>Из последней загрузки</button>
              <button className="btn" disabled={so.undoRecords.length === 0 || so.busy !== null} onClick={() => void so.undo()}><IconUndo size={16} /> Отмена переноса</button>
            </div>
            <div className="hint" style={{ marginTop: 8 }}>{s.latestItems.length === 0 ? "Файлов из последней выгрузки пока нет." : `Файлов из последней выгрузки: ${s.latestItems.length}.`}</div>

            <StepTitle>5. Скопируй готовый результат</StepTitle>
            <div className="hint">Drive-ссылки копируются дайджестом: страна, блогер, ссылки.</div>
            <div className="statusline">{so.driveStatus}</div>
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn" disabled={so.records.length === 0 || so.busy !== null} onClick={() => void so.copyLinks()}><IconCopy size={16} /> {so.busy === "drive" ? "Собираю ссылки…" : "Скопировать ссылки"}</button>
              <button className="btn" disabled={!so.digest.trim() || so.busy !== null} onClick={() => void so.copyDigest()}>Скопировать список</button>
            </div>
          </Card>
        </div>

        <div className="stack">
          <Card title="Запомненные блогеры">
            <div className="hint" style={{ marginBottom: 10 }}>{remembered.length === 0 ? "Блогеры появятся здесь после правил или переноса." : `Запомнено блогеров: ${remembered.length}.`}</div>
            {remembered.length === 0 ? <Empty icon={<IconEmpty size={28} />} text="Пока никого" /> : (
              <div className="chips">{remembered.map((b) => <span className="chip" key={b.username}>{b.countryFolder}: {b.username}</span>)}</div>
            )}
          </Card>
          <Card title={so.digestTitle}>
            <textarea className="digest" readOnly value={so.digest} spellCheck={false} aria-label="Дайджест" placeholder="Здесь появится результат сортировки." />
          </Card>
        </div>
      </div>
    </>
  );
}
