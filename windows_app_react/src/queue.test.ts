import { describe, expect, it } from "vitest";
import { restoreEntries, restoreNotice } from "./queue";

const e = (url: string, status: string, message = "") => ({ url, status, message });

describe("restoreEntries", () => {
  it("keeps finished profiles and makes interrupted ones runnable again", () => {
    const r = restoreEntries([e("a", "completed", "Сохранено 3"), e("b", "running"), e("c", "stopped"), e("d", "failed", "нет stories"), e("f", "pending")]);
    expect(r.entries.map((x) => x.status)).toEqual(["completed", "pending", "pending", "failed", "pending"]);
    expect(r.entries[0].message).toBe("Сохранено 3");
    expect(r.entries[1].message).toContain("Прервано");
    expect(r.interrupted).toBe(2);
    expect(r.toRun).toBe(4); // b, c, d (ошибочный повторяется), f
  });
  it("treats unknown statuses as pending", () => {
    expect(restoreEntries([e("a", "weird")]).entries[0].status).toBe("pending");
  });
  it("handles an empty queue", () => {
    expect(restoreEntries([])).toEqual({ entries: [], interrupted: 0, toRun: 0 });
  });
});

describe("restoreNotice", () => {
  it("is silent when nothing is left to do", () => {
    expect(restoreNotice(restoreEntries([e("a", "completed")]))).toBeNull();
  });
  it("tells what was restored and what to do", () => {
    const text = restoreNotice(restoreEntries([e("a", "running"), e("b", "completed")]))!;
    expect(text).toContain("2 профилей");
    expect(text).toContain("к выгрузке 1");
    expect(text).toContain("Прерванных выгрузкой: 1");
    expect(text).toContain("Скачать");
  });
});
