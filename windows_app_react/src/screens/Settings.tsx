import { Banner, Card, Pill, Segmented, Switch } from "../components/ui";
import { IconRefresh } from "../icons";
import type { Store } from "../store";
import { LogCard } from "./Stories";

export function Settings({ s }: { s: Store }) {
  const u = s.update;
  const rt = s.runtime;
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
              <button className="btn primary" disabled={!!s.busy || s.workerReady === false || rt?.chromiumInstalled === false} onClick={s.login}>{s.session === "ready" ? "Войти заново" : "Войти в Instagram"}</button>
              <button className="btn" disabled={!!s.busy || rt?.chromiumInstalled === false} onClick={() => s.checkSession()}>Проверить сессию</button>
            </div>
          </Card>

          <Card title="Модули после установки" aside={<Pill tone={rt?.chromiumInstalled ? "ok" : "warn"}>{rt?.chromiumInstalled ? "Chromium установлен" : "Нужен Chromium"}</Pill>}>
            <div className="hint" style={{ marginBottom: 12 }}>
              Node и зависимости воркера идут вместе с приложением, Chromium докачивается один раз в папку пользователя.
            </div>
            <dl className="kv">
              <dt>Node</dt><dd>{rt?.nodeAvailable ? "найден" : "не найден"}</dd>
              <dt>Зависимости</dt><dd>{rt?.workerDepsInstalled ? "установлены" : "не установлены"}</dd>
              <dt>Браузеры</dt><dd>{rt?.browsersDir ?? "—"}</dd>
            </dl>
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn primary" disabled={s.bootstrapping || !!s.busy || rt?.workerDepsInstalled === false} onClick={s.installChromium}>{s.bootstrapping ? "Скачиваю…" : rt?.chromiumInstalled ? "Переустановить Chromium" : "Докачать Chromium"}</button>
              <button className="btn" onClick={() => rt && s.api.openPath(rt.browsersDir)}>Открыть папку</button>
            </div>
          </Card>

          <Card title="Проверка готовности" aside={s.preflight ? <Pill tone={s.preflight.ok ? "ok" : "warn"}>{s.preflight.ok ? "Всё готово" : "Есть проблемы"}</Pill> : null}>
            {!s.preflight ? <div className="hint">Проверка ещё не запускалась.</div> : (
              <div className="checks">
                {s.preflight.checks.map((c) => (
                  <div key={c.name}><span className={`tick ${c.ok ? "ok" : "bad"}`}>{c.ok ? "✓" : "✗"}</span><b>{c.name}</b><span>{c.message}</span></div>
                ))}
              </div>
            )}
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn" onClick={s.runPreflight}>Проверить готовность</button>
              <button className="btn" onClick={s.exportDiagnostics}>Экспорт диагностики</button>
            </div>
          </Card>

          {s.log.length > 0 && <LogCard lines={s.log} />}
        </div>

        <div className="stack">
          <Card title="Оформление">
            <div className="setting" style={{ paddingTop: 0 }}>
              <div><div>Менять по времени суток</div><div className="hint">Светлая тема с 7:00 до 19:00, затем тёмная</div></div>
              <Switch checked={s.settings.automaticThemeByTime} onChange={(v) => s.updateSettings({ automaticThemeByTime: v })} label="Тема по времени суток" />
            </div>
            <Segmented label="Тема" value={s.settings.theme} disabled={s.settings.automaticThemeByTime} onChange={(v) => s.updateSettings({ theme: v })}
              options={[{ value: "system", label: "Системная" }, { value: "light", label: "Светлая" }, { value: "dark", label: "Тёмная" }]} />
          </Card>
          <Card title="Выгрузка">
            <div className="setting" style={{ paddingTop: 0 }}>
              <div><div>Не давать компьютеру засыпать</div><div className="hint">Только во время активной выгрузки</div></div>
              <Switch checked={s.settings.preventSleep} onChange={(v) => s.updateSettings({ preventSleep: v })} label="Не давать засыпать" />
            </div>
          </Card>
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
            {u.phase === "ready" && (
              <div className="row" style={{ marginTop: 12 }}>
                <button className="btn go" disabled={s.running} onClick={s.installUpdate}>Установить и перезапустить</button>
                <span className="hint">{s.running ? "Идёт выгрузка — дождись окончания или останови её." : "Приложение закроется и откроется снова уже новой версией."}</span>
              </div>
            )}
          </Card>
          <Card title="Данные">
            <dl className="kv">
              <dt>Воркер</dt><dd>{s.workerSummary}</dd>
              <dt>Папка данных</dt><dd>{s.info?.appSupport}</dd>
            </dl>
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn sm" onClick={s.openAppData}>Открыть папку данных</button>
              <button className="btn sm" disabled={!!s.busy} onClick={s.probe}>Проверить среду</button>
            </div>
          </Card>
        </div>
      </div>
    </>
  );
}
