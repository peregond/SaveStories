import test from "node:test";
import assert from "node:assert/strict";

import {
  extractUsername,
  isAudioOnlyVariant,
  isSeparateDashVideoUrl,
  isStoryMediaUrl,
  mediaVariantTag,
  mediaVariantScore,
  normalizeMediaUrl,
  sanitizeFilename,
  shouldRepairExistingMutedDashVideo,
  shouldSkipMediaVariant,
} from "./media_utils.mjs";

test("sanitizeFilename handles reserved names and empty values", () => {
  assert.equal(sanitizeFilename("CON"), "_CON");
  assert.equal(sanitizeFilename("  "), "story");
});

test("extractUsername supports profiles and stories URLs", () => {
  assert.equal(extractUsername("https://www.instagram.com/alice/"), "alice");
  assert.equal(extractUsername("https://www.instagram.com/stories/bob/123/"), "bob");
  assert.equal(extractUsername("@carol"), "carol");
});

test("normalizeMediaUrl strips byte range query params", () => {
  assert.equal(
    normalizeMediaUrl("https://video.example/media.mp4?bytestart=0&byteend=100&foo=bar"),
    "https://video.example/media.mp4?foo=bar",
  );
});

test("isStoryMediaUrl rejects avatars and unrelated hosts", () => {
  assert.equal(isStoryMediaUrl("https://scontent.cdninstagram.com/story.jpg"), true);
  assert.equal(isStoryMediaUrl("https://static.cdninstagram.com/avatar.jpg"), false);
  assert.equal(isStoryMediaUrl("https://example.com/story.jpg"), false);
});

test("variant helpers detect audio-only and clips variants", () => {
  const audioTag = Buffer.from(JSON.stringify({ vencode_tag: "iphone_xpv_audio" })).toString("base64url");
  const clipsTag = Buffer.from(JSON.stringify({ vencode_tag: "clips_dash_vp9-basic" })).toString("base64url");
  const storyTag = Buffer.from(JSON.stringify({ vencode_tag: "iphone_xpv_story" })).toString("base64url");
  const audioUrl = `https://video.cdninstagram.com/story.mp4?efg=${audioTag}`;
  const clipsUrl = `https://video.cdninstagram.com/story.mp4?efg=${clipsTag}`;
  const storyUrl = `https://video.cdninstagram.com/story.mp4?efg=${storyTag}`;

  assert.equal(isAudioOnlyVariant(audioUrl), true);
  assert.equal(mediaVariantTag(storyUrl), "iphone_xpv_story");
  assert.equal(shouldSkipMediaVariant(audioUrl), true);
  assert.equal(shouldSkipMediaVariant(clipsUrl), true);
  assert.equal(shouldSkipMediaVariant(storyUrl), false);
  assert.ok(mediaVariantScore(storyUrl, "video") > mediaVariantScore(audioUrl, "video"));
});

test("DASH helpers detect separate video variants", () => {
  const dashTag = Buffer.from(JSON.stringify({
    vencode_tag: "xpv_progressive.INSTAGRAM.STORY.C3.720.dash_baseline_1_v1",
  })).toString("base64url");
  const sourceUrl = `https://video.cdninstagram.com/story.mp4?efg=${dashTag}`;

  assert.equal(isSeparateDashVideoUrl(sourceUrl), true);
});

test("audioPresent controls repair and supersedes legacy audioMuxed", () => {
  const media = {
    sourceUrl: "https://video.cdninstagram.com/story.mp4",
    mediaType: "video",
    expectsAudio: true,
  };

  assert.equal(
    shouldRepairExistingMutedDashVideo({ audioPresent: true, audioMuxed: false }, media),
    false,
    "an embedded verified audio track must not be remuxed",
  );
  assert.equal(
    shouldRepairExistingMutedDashVideo({ audioPresent: false, audioMuxed: true }, media),
    true,
    "an explicitly missing audio track must be repaired even if a stale flag says it was muxed",
  );
  assert.equal(
    shouldRepairExistingMutedDashVideo({ audioPresent: null, audioMuxed: true }, media),
    true,
    "an unknown inspected state is fail-safe",
  );
});

test("legacy Windows audioMuxed false is repaired when the resolved video expects audio", () => {
  const media = {
    sourceUrl: "https://video.cdninstagram.com/story.mp4",
    mediaType: "video",
    expectsAudio: true,
  };

  assert.equal(shouldRepairExistingMutedDashVideo({ audioMuxed: false }, media), true);
  assert.equal(shouldRepairExistingMutedDashVideo({}, media), true);
  assert.equal(shouldRepairExistingMutedDashVideo({ audioMuxed: true }, media), false);
  assert.equal(
    shouldRepairExistingMutedDashVideo({ audioMuxed: false }, { ...media, expectsAudio: false }),
    false,
  );
  assert.equal(
    shouldRepairExistingMutedDashVideo({ audioMuxed: false }, { ...media, expectsAudio: null }),
    true,
    "unknown audio state must not preserve a potentially muted legacy download",
  );
  assert.equal(
    shouldRepairExistingMutedDashVideo(
      { audioMuxed: false },
      { ...media, mediaType: "image", expectsAudio: true },
    ),
    false,
  );
});

import { downloadedFileName, filenameDatePrefix, nextFileNumber } from "./media_utils.mjs";
import test2 from "node:test";
import assert2 from "node:assert/strict";

test2("file names are дд.мм.гг-аккаунт-номер", () => {
  const day = new Date(2026, 10, 6);
  assert2.equal(filenameDatePrefix(day), "06.11.26");
  assert2.equal(downloadedFileName("marco.vegas1", 2, ".mp4", { now: day }), "06.11.26-marco.vegas1-002.mp4");
  assert2.equal(downloadedFileName("alice", 12, ".jpg", { now: day }), "06.11.26-alice-012.jpg");
  assert2.equal(downloadedFileName("alice", 1, ".mp4", { kind: "reels", now: day }), "06.11.26-alice-reels-001.mp4");
  assert2.equal(filenameDatePrefix(new Date(2027, 0, 5)), "05.01.27");
});

test2("numbering restarts every day and is per account and kind", () => {
  const day = new Date(2026, 10, 6);
  const files = ["06.11.26-alice-001.mp4", "06.11.26-alice-007.jpg", "05.11.26-alice-099.mp4", "alice-050.mp4", "06.11.26-alice-reels-004.mp4", "06.11.26-bob-009.mp4"];
  assert2.equal(nextFileNumber(files, "alice", { now: day }), 8);
  assert2.equal(nextFileNumber(files, "alice", { kind: "reels", now: day }), 5);
  assert2.equal(nextFileNumber(files, "bob", { now: day }), 10);
  assert2.equal(nextFileNumber(files, "carol", { now: day }), 1);
  assert2.equal(nextFileNumber(files, "alice", { now: new Date(2026, 10, 7) }), 1);
  assert2.equal(nextFileNumber(["06X11X26-a.b-001.mp4"], "a.b", { now: day }), 1);
});
