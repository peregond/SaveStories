import { describe, expect, it } from "vitest";
import {
  isToday, normalizeProfile, parseProfiles, parseReelLines, pluralProfiles, profileCounts, profileFromProgress, profileName, progressDetail, themeForHour, workerTimeoutSecs,
} from "./parse";

describe("profile parsing (WinUI rules)", () => {
  it("turns usernames and handles into profile urls", () => {
    expect(normalizeProfile("dian.vegas1")).toBe("https://www.instagram.com/dian.vegas1/");
    expect(normalizeProfile("@leftlanepapi,")).toBe("https://www.instagram.com/leftlanepapi/");
    expect(normalizeProfile("(*anna*)")).toBe("https://www.instagram.com/anna/");
  });
  it("accepts instagram urls, with or without scheme, and story links", () => {
    expect(normalizeProfile("https://www.instagram.com/stevensetu/?hl=en")).toBe("https://www.instagram.com/stevensetu/");
    expect(normalizeProfile("instagram.com/anna")).toBe("https://www.instagram.com/anna/");
    expect(normalizeProfile("https://www.instagram.com/stories/anna/3456/")).toBe("https://www.instagram.com/anna/");
    expect(normalizeProfile("https://m.instagram.com/bob/")).toBe("https://www.instagram.com/bob/");
  });
  it("rejects non-profile links", () => {
    for (const bad of [
      "https://www.instagram.com/reel/ABC/", "https://www.instagram.com/p/ABC/", "https://www.instagram.com/explore/",
      "https://www.instagram.com/stories/highlights/123/", "https://www.instagram.com/", "https://evilinstagram.com/anna/", "", "   ", "@@@",
    ]) {
      expect(normalizeProfile(bad), bad).toBeNull();
    }
  });
  it("splits on whitespace, commas and semicolons and dedupes case-insensitively", () => {
    expect(parseProfiles("Anna, bob;ANNA\nhttps://www.instagram.com/anna/ carl")).toEqual([
      "https://www.instagram.com/Anna/", "https://www.instagram.com/bob/", "https://www.instagram.com/carl/",
    ]);
    expect(parseProfiles(null)).toEqual([]);
  });
  it("extracts display names", () => {
    expect(profileName("https://www.instagram.com/dian.vegas1/")).toBe("dian.vegas1");
  });
});

describe("worker progress lines", () => {
  it("reads the profile and the error detail", () => {
    expect(profileFromProgress("batch_slot_1_done=https://www.instagram.com/anna/")).toBe("anna");
    expect(profileFromProgress("batch_slot_2_error=https://www.instagram.com/bob/ :: нет stories")).toBe("bob");
    expect(progressDetail("batch_slot_2_error=https://www.instagram.com/bob/ :: нет stories")).toBe("нет stories");
    expect(progressDetail("batch_slot_2_done=x")).toBe("");
    expect(profileFromProgress("plain")).toBe("plain");
  });
});

describe("reels lines", () => {
  it("keeps one entry per line, deduped", () => {
    expect(parseReelLines("a\n  b \nA\n\n")).toEqual(["a", "b"]);
  });
});

describe("helpers", () => {
  it("handles russian plural forms", () => {
    expect([1, 2, 5, 11, 21].map(pluralProfiles)).toEqual(["профиль", "профиля", "профилей", "профилей", "профиль"]);
  });
  it("picks a theme by hour", () => {
    expect([6, 7, 18, 19, 23].map(themeForHour)).toEqual(["dark", "light", "light", "dark", "dark"]);
  });
  it("computes worker timeouts like WinUI", () => {
    expect(workerTimeoutSecs("check_session", 1, true)).toBe(1200);
    expect(workerTimeoutSecs("download_profile_batch", 1, true)).toBe(30 * 60);
    expect(workerTimeoutSecs("download_profile_batch", 100, true)).toBe(170 * 60);
    expect(workerTimeoutSecs("download_profile_batch", 100, false)).toBe(320 * 60);
    expect(workerTimeoutSecs("download_profile_batch", 1000, false)).toBe(720 * 60);
  });
  it("knows when a date is today", () => {
    const now = new Date("2026-11-05T12:00:00");
    expect(isToday("2026-11-05T01:00:00", now)).toBe(true);
    expect(isToday("2026-11-04T23:59:00", now)).toBe(false);
    expect(isToday("", now)).toBe(false);
    expect(isToday("garbage", now)).toBe(false);
  });
});

describe("profileCounts", () => {
  it("reads found and saved from a per-profile progress line", () => {
    expect(profileCounts("batch_slot_2_profile=anna status=download_complete found=5 saved=3 playlist_items=5")).toEqual({ found: 5, saved: 3 });
  });
  it("is not confused by *_error= fields and ignores other lines", () => {
    expect(profileCounts("batch_slot_1_profile=bob status=x found=0 saved=0 api_discovery_error=true item_errors=2")).toEqual({ found: 0, saved: 0 });
    expect(profileCounts("batch_slot_1_done=https://www.instagram.com/anna/")).toBeNull();
    expect(profileCounts("saved=9")).toBeNull();
  });
});
