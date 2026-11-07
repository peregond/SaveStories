import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Banner, Card, Empty, Pill, PathRow, Segmented, Switch } from "../components/ui";
import { IconDownload, IconEmpty, IconFolder, IconStop, IconTrash } from "../icons";
import type { Store } from "../store";
import {
  AUDIO_EXT, IMAGE_EXT, VIDEO_EXT, baseName, optionProblems, plannedOutputs, previewName, type BackgroundStyle, type FitMode, type MetadataMode, type UnikOptions,
} from "../unik";

const Field = ({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) => (
  <label className="field"><span className="field-label">{label}</span>{children}{hint && <span className="hint">{hint}</span>}</label>
);

const Row = ({ title, hint, children }: { title: string; hint?: string; children: ReactNode }) => (
  <div className="setting"><div><div>{title}</div>{hint && <div className="hint">{hint}</div>}</div>{children}</div>
);

/** Число из поля: пустое или неверное — оставляем прежнее значение. */
const num = (value: string, fallback: number) => (value.trim() !== "" && Number.isFinite(Number(value)) ? Number(value) : fallback);

/** Сохранить текущие настройки под именем, применить или удалить сохранённый набор. */
function PresetBar({ u, disabled }: { u: Store["unik"]; disabled: boolean }) {
  const [name, setName] = useState("");
  const [chosen, setChosen] = useState("");
  const exists = u.presets.some((p) => p.name.toLocaleLowerCase("ru") === name.trim().toLocaleLowerCase("ru"));
  return (
    <>
      <Field label="Сохранённые наборы" hint={u.presets.length ? undefined : "Настройте раздел и сохраните набор под своим именем, например «Reels DE 18+»."}>
        <div className="row-actions">
          <select className="ctl" value={chosen} disabled={disabled || !u.presets.length} onChange={(e) => { setChosen(e.target.value); setName(e.target.value); }}>
            <option value="">{u.presets.length ? "Выберите набор…" : "Пока нет наборов"}</option>
            {u.presets.map((p) => <option key={p.name} value={p.name}>{p.name}</option>)}
          </select>
          <button className="btn sm" disabled={disabled || !chosen} onClick={() => u.applySavedPreset(chosen)}>Применить</button>
          <button className="btn sm ghost" aria-label="Удалить набор" disabled={disabled || !chosen} onClick={() => { u.deletePreset(chosen); setChosen(""); }}><IconTrash size={16} /></button>
        </div>
      </Field>
      <Field label="Сохранить текущие настройки как">
        <div className="row-actions">
          <input className="ctl" value={name} maxLength={60} placeholder="Название набора" disabled={disabled} onChange={(e) => setName(e.target.value)} />
          <button className="btn sm" disabled={disabled || !name.trim()} onClick={() => { u.savePreset(name); setChosen(name.trim()); }}>{exists ? "Заменить" : "Сохранить"}</button>
        </div>
      </Field>
    </>
  );
}

export function Unikalizer({ s }: { s: Store }) {
  const u = s.unik;
  const o = u.options;
  const set = (change: (o: UnikOptions) => UnikOptions) => u.setOptions(change);
  const busy = s.busy === "unik";
  const locked = !!s.busy || u.ffmpeg.phase === "installing";
  const catalog = u.catalog;
  const outputs = plannedOutputs(u.files.length, o);
  const problems = optionProblems(o, u.files.length);
  const ready = u.ffmpeg.phase === "ready";
  const customSize = o.formatPresetId === "custom";
  const firstFile = u.files[0]?.name ?? "";

  useEffect(() => { void u.refresh(); }, [u.refresh]);
  useEffect(() => {
    let off: (() => void) | undefined;
    let alive = true;
    void s.onFilesDropped((paths) => u.addFiles(paths)).then((fn) => { if (alive) off = fn; else fn(); });
    return () => { alive = false; off?.(); };
  }, [s.onFilesDropped, u.addFiles]);

  const doneCount = u.jobs.filter((j) => j.status === "done").length;
  const overall = useMemo(() => (u.jobs.length ? Math.round(u.jobs.reduce((sum, j) => sum + (j.status === "done" || j.status === "error" ? 100 : j.percent), 0) / u.jobs.length) : 0), [u.jobs]);

  const applyPreset = (id: string) => {
    const preset = catalog?.formatPresets.find((p) => p.id === id);
    if (!preset) { set((c) => ({ ...c, formatPresetId: "custom" })); return; }
    set((c) => ({ ...c, formatPresetId: id, resize: { ...preset.resize, fit: preset.resize.fit, backgroundStyle: preset.resize.backgroundStyle as BackgroundStyle }, fps: preset.fps, bitrate: preset.bitrate }));
  };
  const setStyle = (slot: number, id: string) => set((c) => ({ ...c, variations: { ...c.variations, styleIds: c.variations.styleIds.map((x, i) => (i === slot ? id : x)) } }));
  const setCount = (count: number) => set((c) => ({ ...c, variations: { ...c.variations, count, styleIds: Array.from({ length: count }, (_, i) => c.variations.styleIds[i] ?? c.variations.styleIds[0] ?? "clean") } }));

  return (
    <>
      {u.ffmpeg.phase === "missing" && (
        <Banner tone="warn" action={<button className="btn sm" onClick={() => void u.installFfmpeg()}>Установить FFmpeg</button>}>
          Для обработки нужен FFmpeg. Он скачивается один раз (около 110 МБ) и хранится в папке приложения.
        </Banner>
      )}
      {u.ffmpeg.phase === "error" && (
        <Banner tone="err" action={<button className="btn sm" onClick={() => void u.installFfmpeg()}>Повторить</button>}>{u.ffmpeg.message || "Не удалось подготовить FFmpeg."}</Banner>
      )}
      {u.ffmpeg.phase === "installing" && (
        <Banner tone="warn">
          {u.ffmpeg.message || "Устанавливаю FFmpeg…"}
          <div className="progress" role="progressbar" aria-valuenow={u.ffmpeg.percent}><div style={{ width: `${u.ffmpeg.percent}%` }} /></div>
        </Banner>
      )}
      <div className="cols">
        <div className="stack">
          <Card title="Файлы" aside={u.files.length ? <button className="btn sm ghost" disabled={locked} onClick={u.clearFiles}><IconTrash size={16} /> Очистить</button> : null}>
            <button className="dropzone" disabled={locked} onClick={() => void u.pickSources()}>
              <IconFolder />
              <span><b>Добавить видео и картинки</b><br /><span className="hint">или перетащите файлы в окно · {VIDEO_EXT.join(", ")}, {IMAGE_EXT.join(", ")}</span></span>
            </button>
            {u.files.length === 0 ? null : (
              <div className="list" style={{ marginTop: 12 }}>
                {u.files.map((f) => (
                  <div className="item" key={f.path}>
                    <div className="grow"><div className="name" title={f.path}>{f.name}</div><div className="hint">{f.info || (f.image ? "картинка" : "видео")}</div></div>
                    {!f.ok && <Pill tone="err">Ошибка</Pill>}
                    <button className="btn sm ghost" aria-label={`Убрать ${f.name}`} disabled={locked} onClick={() => u.removeFile(f.path)}><IconTrash size={16} /></button>
                  </div>
                ))}
              </div>
            )}
          </Card>

          <Card title="Мои пресеты">
            <PresetBar u={u} disabled={locked} />
          </Card>

          <Card title="Формат и экспорт">
            <Field label="Готовый формат">
              <select className="ctl" value={o.formatPresetId} disabled={locked || !catalog} onChange={(e) => applyPreset(e.target.value)}>
                {catalog?.formatPresets.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                <option value="custom">Свой размер</option>
              </select>
            </Field>
            <div className="grid2">
              <Field label="Ширина"><input className="ctl" type="number" min={2} max={8192} step={2} value={o.resize.width} disabled={locked || !customSize} onChange={(e) => set((c) => ({ ...c, resize: { ...c.resize, width: num(e.target.value, c.resize.width) } }))} /></Field>
              <Field label="Высота"><input className="ctl" type="number" min={2} max={8192} step={2} value={o.resize.height} disabled={locked || !customSize} onChange={(e) => set((c) => ({ ...c, resize: { ...c.resize, height: num(e.target.value, c.resize.height) } }))} /></Field>
            </div>
            <div className="field-label">Вписывание в кадр</div>
            <Segmented<FitMode> label="Вписывание" value={o.resize.fit} disabled={locked} onChange={(v) => set((c) => ({ ...c, resize: { ...c.resize, fit: v } }))}
              options={[{ value: "cover", label: "Заполнить (обрезка)" }, { value: "contain", label: "Целиком (с полями)" }]} />
            {o.resize.fit === "contain" && (
              <>
                <div className="field-label">Фон по краям</div>
                <Segmented<BackgroundStyle> label="Фон" value={o.resize.backgroundStyle} disabled={locked} onChange={(v) => set((c) => ({ ...c, resize: { ...c.resize, backgroundStyle: v } }))}
                  options={[{ value: "bars", label: "Чёрные поля" }, { value: "blur", label: "Размытие" }, { value: "solid", label: "Цвет" }]} />
                {o.resize.backgroundStyle === "solid" && (
                  <Field label="Цвет фона"><input className="ctl color" type="color" value={o.resize.backgroundColor} disabled={locked} onChange={(e) => set((c) => ({ ...c, resize: { ...c.resize, backgroundColor: e.target.value } }))} /></Field>
                )}
              </>
            )}
            <div className="field-label">Частота кадров</div>
            <Segmented<string> label="FPS" value={String(o.fps ?? 0)} disabled={locked} onChange={(v) => set((c) => ({ ...c, fps: Number(v) || null }))}
              options={[{ value: "0", label: "Как есть" }, ...(catalog?.fpsOptions ?? [25, 30, 50, 60]).map((f) => ({ value: String(f), label: String(f) }))]} />
            <div className="field-label">Качество видео</div>
            <Segmented<string> label="Качество" value={o.bitrate} disabled={locked} onChange={(v) => set((c) => ({ ...c, bitrate: v }))}
              options={(catalog?.bitrateOptions ?? []).map((b) => ({ value: b.value, label: b.label }))} />
            <Row title="Выровнять громкость" hint="Один уровень звука у всех результатов"><Switch label="Выровнять громкость" checked={o.audio.normalize} disabled={locked} onChange={(v) => set((c) => ({ ...c, audio: { ...c.audio, normalize: v } }))} /></Row>
            <div className="field-label">Метаданные</div>
            <Segmented<MetadataMode> label="Метаданные" value={o.metadata.mode} disabled={locked} onChange={(v) => set((c) => ({ ...c, metadata: { ...c.metadata, mode: v } }))}
              options={[{ value: "strip", label: "Удалить" }, { value: "export-date", label: "Дата экспорта" }, { value: "custom-date", label: "Своя дата" }]} />
            {o.metadata.mode === "custom-date" && <Field label="Дата создания"><input className="ctl" type="date" value={o.metadata.customDate} disabled={locked} onChange={(e) => set((c) => ({ ...c, metadata: { ...c.metadata, customDate: e.target.value } }))} /></Field>}
          </Card>

          <Card title="Вариации и стиль">
            <div className="field-label">Сколько вариаций из каждого файла</div>
            <Segmented<string> label="Вариации" value={String(o.variations.count)} disabled={locked} onChange={(v) => setCount(Number(v))}
              options={(catalog?.variationOptions ?? [1, 2, 3, 5]).map((n) => ({ value: String(n), label: String(n) }))} />
            {u.files.length > 1 && o.variations.count > 1 && (
              <>
                <div className="field-label">Как применить стили к нескольким файлам</div>
                <Segmented<UnikOptions["variations"]["mode"]> label="Режим" value={o.variations.mode} disabled={locked} onChange={(v) => set((c) => ({ ...c, variations: { ...c.variations, mode: v } }))}
                  options={[{ value: "all-variations", label: "Все вариации для каждого файла" }, { value: "preset-per-file", label: "По одному стилю на файл" }]} />
              </>
            )}
            <div className="grid2">
              {o.variations.styleIds.map((id, slot) => (
                <Field key={slot} label={o.variations.count > 1 ? `Стиль вариации ${slot + 1}` : "Стиль"} hint={catalog?.stylePresets.find((p) => p.id === id)?.hint}>
                  <select className="ctl" value={id} disabled={locked || !catalog} onChange={(e) => setStyle(slot, e.target.value)}>
                    {catalog?.stylePresets.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
                  </select>
                </Field>
              ))}
            </div>
            {o.variations.count === 1 && (
              <>
                <Row title="Настроить вручную" hint="Оттенок, насыщенность, резкость и скорость вместо готового стиля"><Switch label="Настроить вручную" checked={o.manual.enabled} disabled={locked} onChange={(v) => set((c) => ({ ...c, manual: { ...c.manual, enabled: v } }))} /></Row>
                {o.manual.enabled && (
                  <div className="grid2">
                    <Field label={`Оттенок: ${o.manual.hueShift}°`}><input type="range" min={-180} max={180} step={1} value={o.manual.hueShift} disabled={locked} onChange={(e) => set((c) => ({ ...c, manual: { ...c.manual, hueShift: Number(e.target.value) } }))} /></Field>
                    <Field label={`Насыщенность: ${o.manual.saturation.toFixed(2)}`}><input type="range" min={0} max={3} step={0.05} value={o.manual.saturation} disabled={locked} onChange={(e) => set((c) => ({ ...c, manual: { ...c.manual, saturation: Number(e.target.value) } }))} /></Field>
                    <Field label={`Резкость: ${o.manual.sharpness.toFixed(2)}`}><input type="range" min={0} max={2} step={0.05} value={o.manual.sharpness} disabled={locked} onChange={(e) => set((c) => ({ ...c, manual: { ...c.manual, sharpness: Number(e.target.value) } }))} /></Field>
                    <Field label={`Длительность: ${o.manual.speedOffsetMs > 0 ? "+" : ""}${o.manual.speedOffsetMs} мс`}><input type="range" min={-2000} max={3000} step={50} value={o.manual.speedOffsetMs} disabled={locked} onChange={(e) => set((c) => ({ ...c, manual: { ...c.manual, speedOffsetMs: Number(e.target.value) } }))} /></Field>
                  </div>
                )}
              </>
            )}
          </Card>

          <Card title="Плашка 18+">
            <Row title="Добавить плашку 18+" hint="Готовые шаблоны по странам, подбираются под соотношение сторон"><Switch label="Плашка 18+" checked={o.ageMark.enabled} disabled={locked} onChange={(v) => set((c) => ({ ...c, ageMark: { ...c.ageMark, enabled: v } }))} /></Row>
            {o.ageMark.enabled && (
              <>
                <Field label="Страна">
                  <select className="ctl" value={o.ageMark.geoId} disabled={locked || !catalog} onChange={(e) => set((c) => ({ ...c, ageMark: { ...c.ageMark, geoId: e.target.value } }))}>
                    <option value="">Выберите страну…</option>
                    {catalog?.ageMarkGeos.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
                  </select>
                </Field>
                <div className="field-label">Расположение</div>
                <Segmented<"top" | "bottom"> label="Расположение плашки" value={o.ageMark.position} disabled={locked} onChange={(v) => set((c) => ({ ...c, ageMark: { ...c.ageMark, position: v } }))}
                  options={[{ value: "top", label: "Сверху" }, { value: "bottom", label: "Снизу" }]} />
              </>
            )}
          </Card>

          <Card title="Дополнительно">
            <Row title="Заставка в начале" hint="Картинка на первые доли секунды"><Switch label="Заставка" checked={o.intro.enabled} disabled={locked} onChange={(v) => set((c) => ({ ...c, intro: { ...c.intro, enabled: v } }))} /></Row>
            {o.intro.enabled && (
              <>
                <Row title="Случайная из набора"><Switch label="Случайная заставка" checked={o.intro.random} disabled={locked} onChange={(v) => set((c) => ({ ...c, intro: { ...c.intro, random: v } }))} /></Row>
                {o.intro.random
                  ? <PathRow path={o.intro.library.length ? `Набор: ${o.intro.library.length} файл(ов)` : ""} placeholder="Набор картинок не выбран" disabled={locked} onPick={async () => { const l = await u.pickLibrary("Картинки для заставок", IMAGE_EXT); if (l.length) set((c) => ({ ...c, intro: { ...c.intro, library: l } })); }} onOpen={() => {}} />
                  : <PathRow path={o.intro.imagePath} placeholder="Картинка не выбрана" disabled={locked} onPick={async () => { const p = await u.pickOne("Картинка для заставки", IMAGE_EXT); if (p) set((c) => ({ ...c, intro: { ...c.intro, imagePath: p } })); }} onOpen={() => {}} />}
                <Field label={`Длительность заставки: ${o.intro.durationMs} мс`}><input type="range" min={100} max={3000} step={50} value={o.intro.durationMs} disabled={locked} onChange={(e) => set((c) => ({ ...c, intro: { ...c.intro, durationMs: Number(e.target.value) } }))} /></Field>
              </>
            )}
            <Row title="Видео-слой поверх" hint="Полупрозрачная анимация на весь кадр"><Switch label="Видео-слой" checked={o.overlay.enabled} disabled={locked} onChange={(v) => set((c) => ({ ...c, overlay: { ...c.overlay, enabled: v } }))} /></Row>
            {o.overlay.enabled && (
              <>
                <Row title="Случайный из набора"><Switch label="Случайный видео-слой" checked={o.overlay.random} disabled={locked} onChange={(v) => set((c) => ({ ...c, overlay: { ...c.overlay, random: v } }))} /></Row>
                {o.overlay.random
                  ? <PathRow path={o.overlay.library.length ? `Набор: ${o.overlay.library.length} файл(ов)` : ""} placeholder="Набор видео не выбран" disabled={locked} onPick={async () => { const l = await u.pickLibrary("Видео для слоя поверх", VIDEO_EXT); if (l.length) set((c) => ({ ...c, overlay: { ...c.overlay, library: l } })); }} onOpen={() => {}} />
                  : <PathRow path={o.overlay.videoPath} placeholder="Видео не выбрано" disabled={locked} onPick={async () => { const p = await u.pickOne("Видео для слоя поверх", VIDEO_EXT); if (p) set((c) => ({ ...c, overlay: { ...c.overlay, videoPath: p } })); }} onOpen={() => {}} />}
                <Field label={`Прозрачность слоя: ${Math.round(o.overlay.opacity * 100)}%`}><input type="range" min={0.05} max={1} step={0.05} value={o.overlay.opacity} disabled={locked} onChange={(e) => set((c) => ({ ...c, overlay: { ...c.overlay, opacity: Number(e.target.value) } }))} /></Field>
              </>
            )}
            <div className="field-label">Заменить звук</div>
            <PathRow path={o.audio.replacePath} placeholder="Оставить звук из видео" disabled={locked} onPick={async () => { const p = await u.pickOne("Новая звуковая дорожка", AUDIO_EXT); if (p) set((c) => ({ ...c, audio: { ...c.audio, replacePath: p } })); }} onOpen={() => set((c) => ({ ...c, audio: { ...c.audio, replacePath: "" } }))} />
            {o.audio.replacePath && <div className="hint" style={{ marginTop: 6 }}>Кнопка «Открыть» справа сбрасывает выбор.</div>}
          </Card>

          <Card title="Название файла">
            <Segmented<UnikOptions["naming"]["mode"]> label="Схема имени" value={o.naming.mode} disabled={locked} onChange={(v) => set((c) => ({ ...c, naming: { ...c.naming, mode: v } }))}
              options={[{ value: "structured", label: "ГЕО + формат + версия" }, { value: "source-random", label: "Исходное + случайный хвост" }]} />
            {o.naming.mode === "structured" ? (
              <div className="grid3">
                <Field label="ГЕО"><input className="ctl" value={o.naming.geo} placeholder="AU" disabled={locked} onChange={(e) => set((c) => ({ ...c, naming: { ...c.naming, geo: e.target.value.toUpperCase() } }))} /></Field>
                <Field label="Тип пресета"><input className="ctl" value={o.naming.presetToken} placeholder="instagram" disabled={locked} onChange={(e) => set((c) => ({ ...c, naming: { ...c.naming, presetToken: e.target.value } }))} /></Field>
                <Field label="Версия"><input className="ctl" value={o.naming.versionToken} placeholder="v1" disabled={locked} onChange={(e) => set((c) => ({ ...c, naming: { ...c.naming, versionToken: e.target.value } }))} /></Field>
              </div>
            ) : (
              <Field label="Хвост (пусто — случайный)"><input className="ctl" value={o.naming.randomTail} placeholder="Asdc56Dg" disabled={locked} onChange={(e) => set((c) => ({ ...c, naming: { ...c.naming, randomTail: e.target.value } }))} /></Field>
            )}
            <p className="statusline">Пример: <b>{previewName(o, firstFile, outputs)}</b>{outputs > 1 && <> … <b>{previewName(o, firstFile, outputs, outputs - 1)}</b></>}</p>
          </Card>
        </div>

        <div className="stack sticky">
          <Card title="Запуск">
            <p className="statusline" style={{ marginTop: 0 }}>
              {u.files.length ? <>Файлов: <b>{u.files.length}</b> · будет создано: <b>{outputs}</b></> : "Добавьте файлы, чтобы начать."}
            </p>
            {!ready && u.ffmpeg.phase !== "unknown" && <p className="hint">Сначала нужно установить FFmpeg.</p>}
            {problems.length > 0 && u.files.length > 0 && <ul className="problems">{problems.map((p) => <li key={p}>{p}</li>)}</ul>}
            <div className="actions">
              <button className="btn go" disabled={locked || !ready || problems.length > 0} onClick={() => void u.run()}>
                <IconDownload /> Создать{outputs ? ` · ${outputs}` : ""}
              </button>
              <button className="btn danger" disabled={!busy} onClick={s.stop}><IconStop /> Стоп</button>
            </div>
            <div className="field-label">Папка для результатов</div>
            <PathRow path={u.effectiveOutput()} placeholder="Папка не выбрана" disabled={locked} onPick={() => void u.pickOutput()} onOpen={u.openOutput} />
            {u.ffmpeg.phase === "ready" && u.ffmpeg.version && <p className="hint" style={{ marginTop: 10 }}>FFmpeg {u.ffmpeg.version}</p>}
          </Card>

          <Card title="Ход обработки" aside={u.jobs.length ? <span className="hint">{doneCount} из {u.jobs.length}</span> : null}>
            {u.jobs.length === 0 ? <Empty icon={<IconEmpty size={32} />} text={u.summary || "Результаты появятся здесь"} /> : (
              <>
                <div className="progress" role="progressbar" aria-valuenow={overall}><div style={{ width: `${overall}%` }} /></div>
                <div className="list" style={{ marginTop: 12 }}>
                  {u.jobs.map((j) => (
                    <div className="item" key={j.index}>
                      <div className="grow">
                        <div className="name" title={j.outputPath || j.label}>{j.outputPath ? baseName(j.outputPath) : j.label || `Файл ${j.index + 1}`}</div>
                        <div className="hint">{j.status === "error" ? j.message || "Ошибка" : j.status === "running" ? `Обработка… ${j.percent}%` : j.status === "done" ? `из ${j.label.split(" → ")[0] || "исходника"}` : "В очереди"}</div>
                      </div>
                      <Pill tone={j.status === "done" ? "ok" : j.status === "error" ? "err" : j.status === "running" ? "run" : ""}>{j.status === "done" ? "Готово" : j.status === "error" ? "Ошибка" : j.status === "running" ? `${j.percent}%` : "Ждёт"}</Pill>
                    </div>
                  ))}
                </div>
                {u.summary && <p className="statusline">{u.summary}</p>}
                {!busy && doneCount > 0 && <div className="row" style={{ marginTop: 10 }}><button className="btn sm" onClick={u.openOutput}><IconFolder size={16} /> Открыть папку</button></div>}
              </>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
