import type { ReactNode } from "react";

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

export function Switch({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return <button className="switch" role="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)} />;
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
