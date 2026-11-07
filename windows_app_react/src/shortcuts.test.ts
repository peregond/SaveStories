import { describe, expect, it } from "vitest";
import { shortcutTarget } from "./App";

describe("shortcutTarget", () => {
  it("Ctrl+1…5 открывают разделы по порядку", () => {
    expect(["1", "2", "3", "4", "5"].map((k) => shortcutTarget(k, false))).toEqual(["stories", "reels", "unik", "sorting", "settings"]);
  });
  it("Ctrl+, — настройки, Ctrl+Shift+O — папка", () => {
    expect(shortcutTarget(",", false)).toBe("settings");
    expect(shortcutTarget("O", true)).toBe("folder");
    expect(shortcutTarget("o", true)).toBe("folder");
  });
  it("остальное не трогает", () => {
    expect(shortcutTarget("6", false)).toBeNull();
    expect(shortcutTarget("0", false)).toBeNull();
    expect(shortcutTarget("a", false)).toBeNull();
    expect(shortcutTarget("1", true)).toBeNull();
  });
});
