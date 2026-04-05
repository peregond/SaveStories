import test from "node:test";
import assert from "node:assert/strict";

import {
  extractReelShortcode,
  normalizeReelUrl,
  splitReelInputs,
} from "./reels_downloader.mjs";

test("splitReelInputs supports commas and new lines", () => {
  assert.deepEqual(
    splitReelInputs([
      "https://www.instagram.com/reel/AAA111/, https://www.instagram.com/reel/BBB222/\nhttps://www.instagram.com/p/CCC333/",
    ]),
    [
      "https://www.instagram.com/reel/AAA111/",
      "https://www.instagram.com/reel/BBB222/",
      "https://www.instagram.com/p/CCC333/",
    ],
  );
});

test("normalizeReelUrl strips hashes and normalizes known instagram media paths", () => {
  assert.equal(
    normalizeReelUrl("https://www.instagram.com/reel/DMabc123/?utm_source=ig_web_copy_link#fragment"),
    "https://www.instagram.com/reel/DMabc123/?utm_source=ig_web_copy_link",
  );
  assert.equal(
    normalizeReelUrl("https://www.instagram.com/p/XYZ999"),
    "https://www.instagram.com/p/XYZ999/",
  );
});

test("extractReelShortcode supports reel and post urls", () => {
  assert.equal(extractReelShortcode("https://www.instagram.com/reel/DMabc123/"), "DMabc123");
  assert.equal(extractReelShortcode("https://www.instagram.com/p/CODE456/"), "CODE456");
  assert.equal(extractReelShortcode("https://www.instagram.com/alice/"), "");
});
