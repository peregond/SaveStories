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

test("DASH helpers detect separate video and repair only unverified manifests", () => {
  const dashTag = Buffer.from(JSON.stringify({
    vencode_tag: "xpv_progressive.INSTAGRAM.STORY.C3.720.dash_baseline_1_v1",
  })).toString("base64url");
  const sourceUrl = `https://video.cdninstagram.com/story.mp4?efg=${dashTag}`;
  const media = { sourceUrl, mediaType: "video", expectsAudio: true };

  assert.equal(isSeparateDashVideoUrl(sourceUrl), true);
  assert.equal(shouldRepairExistingMutedDashVideo({ audioMuxed: false }, media), true);
  assert.equal(shouldRepairExistingMutedDashVideo({}, media), true);
  assert.equal(shouldRepairExistingMutedDashVideo({ audioMuxed: true }, media), false);
  assert.equal(shouldRepairExistingMutedDashVideo({}, { ...media, expectsAudio: false }), false);
});
