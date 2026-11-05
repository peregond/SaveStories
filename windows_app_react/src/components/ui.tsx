import { useEffect, type ReactNode } from "react";

export function Card({ title, aside, children }: { title?: string; aside?: ReactNode; children: ReactNode }) {
  return (
    <section className="card">
      {title && <h2 className="card-title">{title}{aside}</h2>}
      {children}
    </section>
  );
}

export function Segmented<T extends string>({ value, onChange, options, label, disabled }: {
  value: T; onChange: (v: T) => void; options: { value: T; label: string }[]; label: string; disabled?: boolean;
}) {
  return (
    <div className="seg" role="radiogroup" aria-label={label}>
      {options.map((o) => (
        <button key={o.value} role="radio" aria-checked={value === o.value} disabled={disabled} onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  );
}

export function Switch({ checked, onChange, label, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return <button className="switch" role="switch" aria-checked={checked} aria-label={label} disabled={disabled} onClick={() => onChange(!checked)} />;
}

export function Empty({ icon, text }: { icon: ReactNode; text: string }) {
  return <div className="empty">{icon}<span>{text}</span></div>;
}

export function Banner({ tone, children, onClose, action }: { tone: "ok" | "err" | "warn"; children: ReactNode; onClose?: () => void; action?: ReactNode }) {
  return (
    <div className={`banner ${tone}`} role={tone === "err" ? "alert" : "status"}>
      <span className="grow">{children}</span>
      {action}
      {onClose && <button className="btn sm ghost" aria-label="Закрыть" onClick={onClose}>✕</button>}
    </div>
  );
}

export function Pill({ tone, children }: { tone: "" | "ok" | "run" | "err" | "warn"; children: ReactNode }) {
  return <span className={`pill ${tone}`}><i />{children}</span>;
}

/** Подпись шага/раздела: «1. УКАЖИ, ГДЕ…». */
export function StepTitle({ children }: { children: ReactNode }) {
  return <div className="step-title">{children}</div>;
}

export function Dialog({ title, children, primary, secondary, onPrimary, onSecondary }: {
  title: string; children: ReactNode; primary: string; secondary: string; onPrimary: () => void; onSecondary: () => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onSecondary(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onSecondary]);
  return (
    <div className="scrim" onMouseDown={(e) => { if (e.target === e.currentTarget) onSecondary(); }}>
      <div className="dialog" role="dialog" aria-modal="true" aria-label={title}>
        <h2>{title}</h2>
        <div className="dialog-body">{children}</div>
        <div className="row dialog-actions">
          <button className="btn" onClick={onSecondary}>{secondary}</button>
          <button className="btn go" style={{ height: 38, fontSize: 14 }} autoFocus onClick={onPrimary}>{primary}</button>
        </div>
      </div>
    </div>
  );
}

/** Строка «путь + кнопки» для выбора папок. */
export function PathRow({ path, placeholder, onPick, onOpen, disabled }: {
  path: string; placeholder: string; onPick: () => void; onOpen: () => void; disabled?: boolean;
}) {
  return (
    <div className="pathbox">
      <span title={path} className={path ? "" : "dim"}>{path || placeholder}</span>
      <button className="btn sm" disabled={disabled} onClick={onPick}>Выбрать</button>
      <button className="btn sm ghost" disabled={!path} onClick={onOpen}>Открыть</button>
    </div>
  );
}
