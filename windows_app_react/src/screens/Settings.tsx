import { Banner, Card, Pill, Segmented, Switch } from "../components/ui";
import { getLang, storeLang, t, type Lang } from "../i18n";
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
            {s.session === "ready" ? t("Вход выполнен") : s.session === "waiting_login" ? t("Жду вход") : s.session === "login_required" ? t("Нужен вход") : s.session === "error" ? t("Ошибка") : t("Проверка…")}
          </Pill>}>
            <div className="hint" style={{ marginBottom: 12 }}>{s.sessionSummary || t("Состояние сессии неизвестно.")}</div>
            <div className="row">
              <button className="btn primary" disabled={!!s.busy || s.workerReady === false || rt?.chromiumInstalled === false} onClick={s.login}>{s.session === "ready" ? t("Войти заново") : t("Войти в Instagram")}</button>
              <button className="btn" disabled={!!s.busy || rt?.chromiumInstalled === false} onClick={() => s.checkSession()}>{t("Проверить сессию")}</button>
            </div>
          </Card>

          <Card title={t("Модули после установки")} aside={<Pill tone={rt?.chromiumInstalled ? "ok" : "warn"}>{rt?.chromiumInstalled ? t("Chromium установлен") : t("Нужен Chromium")}</Pill>}>
            <div className="hint" style={{ marginBottom: 12 }}>
              {t("Node и зависимости воркера идут вместе с приложением, Chromium докачивается один раз в папку пользователя.")}
            </div>
            <dl className="kv">
              <dt>Node</dt><dd>{rt?.nodeAvailable ? t("найден") : t("не найден")}</dd>
              <dt>{t("Зависимости")}</dt><dd>{rt?.workerDepsInstalled ? t("установлены") : t("не установлены")}</dd>
              <dt>{t("Браузеры")}</dt><dd>{rt?.browsersDir ?? "—"}</dd>
            </dl>
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn primary" disabled={s.bootstrapping || !!s.busy || rt?.workerDepsInstalled === false} onClick={s.installChromium}>{s.bootstrapping ? t("Скачиваю…") : rt?.chromiumInstalled ? t("Переустановить Chromium") : t("Докачать Chromium")}</button>
              <button className="btn" onClick={() => rt && s.api.openPath(rt.browsersDir)}>{t("Открыть папку")}</button>
            </div>
          </Card>

          <Card title={t("Проверка готовности")} aside={s.preflight ? <Pill tone={s.preflight.ok ? "ok" : "warn"}>{s.preflight.ok ? t("Всё готово") : t("Есть проблемы")}</Pill> : null}>
            {!s.preflight ? <div className="hint">{t("Проверка ещё не запускалась.")}</div> : (
              <div className="checks">
                {s.preflight.checks.map((c) => (
                  <div key={c.name}><span className={`tick ${c.ok ? "ok" : "bad"}`}>{c.ok ? "✓" : "✗"}</span><b>{c.name}</b><span>{c.message}</span></div>
                ))}
              </div>
            )}
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn" onClick={s.runPreflight}>{t("Проверить готовность")}</button>
              <button className="btn" onClick={s.exportDiagnostics}>{t("Экспорт диагностики")}</button>
            </div>
          </Card>

          {s.log.length > 0 && <LogCard lines={s.log} />}
        </div>

        <div className="stack">
          <Card title={t("Оформление")}>
            <div className="setting" style={{ paddingTop: 0 }}>
              <div><div>{t("Менять по времени суток")}</div><div className="hint">{t("Светлая тема с 7:00 до 19:00, затем тёмная")}</div></div>
              <Switch checked={s.settings.automaticThemeByTime} onChange={(v) => s.updateSettings({ automaticThemeByTime: v })} label={t("Тема по времени суток")} />
            </div>
            <Segmented label={t("Тема")} value={s.settings.theme} disabled={s.settings.automaticThemeByTime} onChange={(v) => s.updateSettings({ theme: v })}
              options={[{ value: "system", label: t("Системная") }, { value: "light", label: t("Светлая") }, { value: "dark", label: t("Тёмная") }]} />
            <div className="setting">
              <div><div>Язык / Language</div><div className="hint">{t("Окно перезагрузится, очередь и настройки сохранятся")}</div></div>
              <Segmented<Lang> label="Language" value={getLang()} onChange={(v) => { if (v !== getLang()) { storeLang(v); location.reload(); } }}
                options={[{ value: "ru", label: "Русский" }, { value: "en", label: "English" }]} />
            </div>
          </Card>
          <Card title={t("Выгрузка")}>
            <div className="setting" style={{ paddingTop: 0 }}>
              <div><div>{t("Не давать компьютеру засыпать")}</div><div className="hint">{t("Только во время активной выгрузки")}</div></div>
              <Switch checked={s.settings.preventSleep} onChange={(v) => s.updateSettings({ preventSleep: v })} label={t("Не давать засыпать")} />
            </div>
          </Card>
          <Card title={t("Обновления")}>
            <div className="setting" style={{ paddingTop: 0 }}>
              <div><div>SaveMe {s.info?.version ?? ""}</div><div className="hint">{u.message || t("Проверка выполняется автоматически раз в 12 часов.")}</div></div>
              <button className="btn sm" disabled={u.phase === "checking" || u.phase === "downloading"} onClick={() => s.checkUpdates()}><IconRefresh size={16} /> {t("Проверить")}</button>
            </div>
            {u.phase === "downloading" && <div className="progress" role="progressbar" aria-valuenow={u.percent}><div style={{ width: `${u.percent}%` }} /></div>}
            {u.release && (u.phase === "available" || u.phase === "error") && (
              <>
                {u.release.notes && <div className="notes">{u.release.notes}</div>}
                <div className="row" style={{ marginTop: 12 }}>
                  {s.info?.autoUpdate
                    ? <button className="btn primary" disabled={u.phase !== "available"} onClick={s.prepareUpdate}>{t("Скачать")} {u.release.version}</button>
                    : <span className="hint">{t("Автоустановка доступна только из установленной версии.")} <a className="linklike" href={u.release.htmlUrl} target="_blank" rel="noreferrer">{t("Открыть релиз")}</a></span>}
                </div>
              </>
            )}
            {u.phase === "ready" && (
              <div className="row" style={{ marginTop: 12 }}>
                <button className="btn go" disabled={s.running} onClick={s.installUpdate}>{t("Установить и перезапустить")}</button>
                <span className="hint">{s.running ? t("Идёт выгрузка — дождись окончания или останови её.") : t("Приложение закроется и откроется снова уже новой версией.")}</span>
              </div>
            )}
          </Card>
          <Card title={t("Данные")}>
            <dl className="kv">
              <dt>{t("Воркер")}</dt><dd>{s.workerSummary}</dd>
              <dt>{t("Папка данных")}</dt><dd>{s.info?.appSupport}</dd>
            </dl>
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn sm" onClick={s.openAppData}>{t("Открыть папку данных")}</button>
              <button className="btn sm" disabled={!!s.busy} onClick={s.probe}>{t("Проверить среду")}</button>
            </div>
          </Card>
        </div>
      </div>
    </>
  );
}
