import { Banner, Card, Pill, Segmented, Switch } from "../components/ui";
import { IconRefresh } from "../icons";
import type { Store } from "../store";
import { LogCard } from "./Stories";

export function Settings({ s }: { s: Store }) {
  const u = s.update;
  return (
    <>
      {s.notice && <Banner tone={s.notice.tone} onClose={() => s.setNotice(null)}>{s.notice.text}</Banner>}
      <div className="cols">
        <div className="stack">
          <Card title="Instagram" aside={<Pill tone={s.session === "ready" ? "ok" : s.session === "error" ? "err" : s.session === "unknown" || s.session === "checking" ? "" : "warn"}>
            {s.session === "ready" ? "Вход выполнен" : s.session === "waiting_login" ? "Жду вход" : s.session === "login_required" ? "Нужен вход" : s.session === "error" ? "Ошибка" : "Проверка…"}
          </Pill>}>
            <div className="hint" style={{ marginBottom: 12 }}>{s.sessionSummary || "Состояние сессии неизвестно."}</div>
            <div className="row">
              <button className="btn primary" disabled={!!s.busy || s.workerReady === false} onClick={s.login}>{s.session === "ready" ? "Войти заново" : "Войти в Instagram"}</button>
              <button className="btn" disabled={!!s.busy} onClick={() => s.checkSession()}>Проверить сессию</button>
            </div>
          </Card>
          <Card title="Выгрузка">
            <div className="setting">
              <div><div>Не давать компьютеру засыпать</div><div className="hint">Только во время активной выгрузки</div></div>
              <Switch checked={s.settings.preventSleep} onChange={(v) => s.updateSettings({ preventSleep: v })} label="Не давать засыпать" />
            </div>
          </Card>
          <Card title="Внешний вид">
            <Segmented label="Тема" value={s.settings.theme} onChange={(v) => s.updateSettings({ theme: v })}
              options={[{ value: "system", label: "Системная" }, { value: "light", label: "Светлая" }, { value: "dark", label: "Тёмная" }]} />
          </Card>
        </div>
        <div className="stack">
          <Card title="Обновления">
            <div className="setting" style={{ paddingTop: 0 }}>
              <div><div>SaveMe {s.info?.version ?? ""}</div><div className="hint">{u.message || "Проверка выполняется автоматически раз в 12 часов."}</div></div>
              <button className="btn sm" disabled={u.phase === "checking" || u.phase === "downloading"} onClick={() => s.checkUpdates()}><IconRefresh size={16} /> Проверить</button>
            </div>
            {u.phase === "downloading" && <div className="progress" role="progressbar" aria-valuenow={u.percent}><div style={{ width: `${u.percent}%` }} /></div>}
            {u.release && (u.phase === "available" || u.phase === "error") && (
              <>
                {u.release.notes && <div className="notes">{u.release.notes}</div>}
                <div className="row" style={{ marginTop: 12 }}>
                  {s.info?.autoUpdate
                    ? <button className="btn primary" disabled={u.phase !== "available"} onClick={s.prepareUpdate}>Скачать {u.release.version}</button>
                    : <span className="hint">Автоустановка доступна только из установленной версии. <a className="linklike" href={u.release.htmlUrl} target="_blank" rel="noreferrer">Открыть релиз</a></span>}
                </div>
              </>
            )}
            {u.phase === "ready" && <div className="row" style={{ marginTop: 12 }}><button className="btn go" onClick={s.installUpdate}>Установить обновление</button></div>}
          </Card>
          <Card title="Данные и среда">
            <dl className="kv">
              <dt>Воркер</dt><dd>{s.workerSummary}</dd>
              <dt>Движок</dt><dd>{s.info?.runtimeEmbedded ? "Встроен в приложение" : "Системный Node"}</dd>
              <dt>Данные</dt><dd>{s.info?.appSupport}</dd>
            </dl>
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn sm" onClick={s.openAppData}>Открыть папку данных</button>
              <button className="btn sm" disabled={!!s.busy} onClick={s.probe}>Проверить среду</button>
            </div>
          </Card>
          {s.log.length > 0 && <LogCard lines={s.log} />}
        </div>
      </div>
    </>
  );
}
