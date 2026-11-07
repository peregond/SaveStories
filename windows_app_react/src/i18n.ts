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

// Сообщения, пришедшие из Rust и воркера по-русски (с подстановками вроде «{0}»): ищем перевод по шаблону из словаря.
interface Pattern { re: RegExp; en: string; order: number[] }
let patterns: Pattern[] | null = null;

function compilePatterns(): Pattern[] {
  const list: Pattern[] = [];
  for (const [ru, en] of Object.entries(EN)) {
    if (!/\{\d+\}/.test(ru)) continue;
    const order: number[] = [];
    const source = ru.split(/(\{\d+\})/).map((part) => {
      const slot = /^\{(\d+)\}$/.exec(part);
      if (slot) { order.push(Number(slot[1])); return "([\\s\\S]*?)"; }
      return part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }).join("");
    list.push({ re: new RegExp(`^${source}$`), en, order });
  }
  // Сначала более конкретные шаблоны (с большим числом постоянных символов): «…из {1}, ошибок: {2}.» раньше «…из {1}.»
  const literal = (entry: Pattern) => entry.re.source.replace(/\(\[\\s\\S\]\*\?\)/g, "").length;
  return list.sort((a, b) => literal(b) - literal(a));
}

/** Перевод готового русского сообщения (например, ответа воркера). Нет перевода — исходный текст. */
export function tr(message: string): string {
  if (lang !== "en" || !message) return message;
  const exact = EN[message];
  if (exact) return exact;
  patterns ??= compilePatterns();
  for (const { re, en, order } of patterns) {
    const match = re.exec(message);
    if (!match) continue;
    const values: string[] = [];
    order.forEach((slot, index) => { values[slot] = match[index + 1] ?? ""; });
    return en.replace(/\{(\d+)\}/g, (_, slot) => values[Number(slot)] ?? "");
  }
  return message;
}
