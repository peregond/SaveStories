// Язык интерфейса. Тексты в коде написаны по-русски и оборачиваются в t(): для английского ищется перевод в en.ts,
// если перевода нет — остаётся русский. Подстановки: t("Готово: {0} из {1}", [done, total]).
// Язык хранится в localStorage и применяется после перезагрузки окна: так его знают и константы уровня модуля.
import { EN } from "./en";

export type Lang = "ru" | "en";
const KEY = "saveme.lang";

function readLang(): Lang {
  try { return localStorage.getItem(KEY) === "en" ? "en" : "ru"; } catch { return "ru"; }
}

const lang: Lang = readLang();
if (typeof document !== "undefined") document.documentElement.lang = lang;

export const getLang = (): Lang => lang;

/** Запоминает язык; интерфейс переключается после перезагрузки окна. */
export function storeLang(next: Lang): void {
  try { localStorage.setItem(KEY, next); } catch { /* хранилище недоступно: останется прежний язык */ }
}

export function t(ru: string, vars?: readonly unknown[]): string {
  const template = lang === "en" ? EN[ru] ?? ru : ru;
  return vars?.length ? template.replace(/\{(\d+)\}/g, (_, index) => String(vars[Number(index)] ?? "")) : template;
}
