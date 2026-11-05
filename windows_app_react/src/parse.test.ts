import { describe, expect, it } from "vitest";
import { normalizeProfileLink, normalizeReelLink, parseBatchLinks, parseReelLinks, pluralProfiles, profileName } from "./parse";

describe("profile links", () => {
  it("turns usernames into profile urls", () => {
    expect(normalizeProfileLink("dian.vegas1")).toBe("https://www.instagram.com/dian.vegas1/");
    expect(normalizeProfileLink("@leftlanepapi,")).toBe("https://www.instagram.com/leftlanepapi/");
  });
  it("keeps full instagram urls untouched", () => {
    expect(normalizeProfileLink("https://www.instagram.com/stevensetu/")).toBe("https://www.instagram.com/stevensetu/");
  });
  it("splits on whitespace, commas and semicolons", () => {
    expect(parseBatchLinks("a, b;c\nd")).toHaveLength(4);
    expect(parseBatchLinks("  \n ")).toEqual([]);
  });
  it("extracts a display name", () => {
    expect(profileName("https://www.instagram.com/dian.vegas1/")).toBe("dian.vegas1");
  });
});

describe("reel links", () => {
  it("normalizes reel, reels and post links and drops the rest", () => {
    expect(normalizeReelLink("https://www.instagram.com/reel/ABC123/?igsh=x#frag")).toBe("https://www.instagram.com/reel/ABC123/?igsh=x");
    expect(normalizeReelLink("https://www.instagram.com/p/XYZ/extra")).toBe("https://www.instagram.com/p/XYZ/");
    expect(normalizeReelLink("https://www.instagram.com/someone/")).toBe("");
    expect(normalizeReelLink("https://example.com/reel/1/")).toBe("");
  });
  it("parses several links per line", () => {
    expect(parseReelLinks("https://www.instagram.com/reel/A/, https://www.instagram.com/reel/B/\nnoise")).toHaveLength(2);
  });
});

describe("plural", () => {
  it("handles russian forms", () => {
    expect([1, 2, 5, 11, 21].map(pluralProfiles)).toEqual(["профиль", "профиля", "профилей", "профилей", "профиль"]);
  });
});
