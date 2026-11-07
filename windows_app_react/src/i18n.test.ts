import { describe, expect, it } from "vitest";
import { EN } from "./en";

// Исходники читаются как текст средствами Vite: так тест не зависит от типов Node.
const modules = (import.meta as unknown as { glob: (pattern: string[], options: { query: string; import: string; eager: boolean }) => Record<string, string> })
  .glob(["./**/*.ts", "./**/*.tsx", "!./**/*.test.ts", "!./**/*.test.tsx", "!./en.ts", "!./i18n.ts"], { query: "?raw", import: "default", eager: true });

/** Ключи из вызовов t("…") в коде. */
function usedKeys(): { file: string; key: string }[] {
  const found: { file: string; key: string }[] = [];
  const call = /\bt\(\s*("(?:\\.|[^"\\])*")/g;
  for (const [file, text] of Object.entries(modules)) {
    for (const match of text.matchAll(call)) found.push({ file, key: JSON.parse(match[1]) as string });
  }
  return found;
}

const placeholders = (text: string) => [...text.matchAll(/\{(\d+)\}/g)].map((m) => m[1]).sort();

describe("английский интерфейс", () => {
  const keys = usedKeys().filter(({ key }) => /[А-Яа-яЁё]/.test(key));

  it("нашёл тексты в коде", () => {
    expect(keys.length).toBeGreaterThan(300);
  });

  it("у каждого русского текста есть перевод", () => {
    const missing = keys.filter(({ key }) => !(key in EN)).map(({ file, key }) => `${file}: ${key}`);
    expect(missing).toEqual([]);
  });

  it("подстановки {0}, {1}… в переводе те же, что в оригинале", () => {
    const broken = Object.entries(EN).filter(([ru, en]) => placeholders(ru).join() !== placeholders(en).join()).map(([ru]) => ru);
    expect(broken).toEqual([]);
  });

  it("перевод не пустой и не остался русским", () => {
    const bad = Object.entries(EN).filter(([ru, en]) => !en.trim() || (/[А-Яа-яЁё]/.test(en) && !/«На перенос»|На перенос|Перенос|Исходники|Уникализатор/.test(en))).map(([ru]) => ru);
    expect(bad).toEqual([]);
  });
});
