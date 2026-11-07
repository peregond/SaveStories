import { describe, expect, it } from "vitest";
import { finishNotification, trayStatus } from "./notify";

describe("finishNotification", () => {
  it("называет раздел и повторяет итог", () => {
    expect(finishNotification("batch", { tone: "ok", text: "Готово. Сохранено файлов: 58." }, false))
      .toEqual({ title: "Выгрузка Stories", body: "Готово. Сохранено файлов: 58." });
  });
  it("помечает ошибку", () => {
    expect(finishNotification("unik", { tone: "err", text: "Нет FFmpeg" }, false)?.body).toBe("Ошибка. Нет FFmpeg");
  });
  it("молчит, если остановили вручную или итога нет", () => {
    expect(finishNotification("reels", { tone: "warn", text: "Выгрузка Reels остановлена." }, true)).toBeNull();
    expect(finishNotification("unik", { tone: "warn", text: "Обработка остановлена." }, false)).toBeNull();
    expect(finishNotification("reels", null, false)).toBeNull();
    expect(finishNotification("reels", { tone: "ok", text: "  " }, false)).toBeNull();
  });
  it("обрезает слишком длинный текст", () => {
    expect(finishNotification("batch", { tone: "ok", text: "x".repeat(500) }, false)?.body.length).toBe(220);
  });
});

describe("trayStatus", () => {
  it("показывает ход выгрузки", () => {
    expect(trayStatus("batch", 58, 122)).toBe("SaveMe — выгрузка: 58 из 122");
    expect(trayStatus("batch", 0, 0)).toBe("SaveMe — идёт выгрузка");
    expect(trayStatus("unik", 0, 0)).toBe("SaveMe — идёт обработка");
    expect(trayStatus(null, 0, 0)).toBe("SaveMe");
  });
});
