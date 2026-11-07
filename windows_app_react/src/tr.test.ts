import { afterEach, describe, expect, it, vi } from "vitest";

async function load(lang: string | null) {
  vi.resetModules();
  vi.stubGlobal("localStorage", { getItem: () => lang, setItem: () => {} });
  return import("./i18n");
}

afterEach(() => vi.unstubAllGlobals());

describe("tr — перевод готовых сообщений", () => {
  it("в русском режиме ничего не меняет", async () => {
    const { tr } = await load(null);
    expect(tr("Сессия найдена.")).toBe("Сессия найдена.");
  });

  it("находит точные сообщения и шаблоны с подстановками", async () => {
    const { tr } = await load("en");
    expect(tr("Сессия найдена.")).toBe("Session found.");
    expect(tr("Не удалось создать папку браузеров: Отказано в доступе (os error 5)")).toBe("Could not create the browsers folder: Отказано в доступе (os error 5)");
    expect(tr("Команда worker превысила таймаут 20 мин.")).toBe("The worker command timed out after 20 min.");
    expect(tr("Для профиля dian.vegas1 сохранено файлов: 7.")).toBe("For profile dian.vegas1 files saved: 7.");
    expect(tr("Готово: 5 из 6, ошибок: 1.")).toBe("Done: 5 of 6, errors: 1.");
    expect(tr("Скачивание обновления 0.6.94: 40%")).toBe("Downloading update 0.6.94: 40%");
  });

  it("неизвестное сообщение и пустая строка остаются как есть", async () => {
    const { tr } = await load("en");
    expect(tr("Что-то совсем новое")).toBe("Что-то совсем новое");
    expect(tr("")).toBe("");
  });

  it("t() подставляет значения и в английском режиме", async () => {
    const { t } = await load("en");
    expect(t("Готово. Сохранено файлов: {0}.", [58])).toBe("Done. Files saved: 58.");
  });
});
