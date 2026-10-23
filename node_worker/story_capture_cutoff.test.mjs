import assert from "node:assert/strict";
import test from "node:test";
import { enrichStoryMediaCandidate } from "./bridge.mjs";

const SOURCE = "https://scontent.cdninstagram.com/reused-story-video.mp4";
const POSTER = "https://scontent.cdninstagram.com/reused-story-poster.jpg";
const AUDIO = "https://scontent.cdninstagram.com/story-audio.m4a";
const CUTOFF = 200;

function captured(id, capturedAt, isStory = true) {
  const item = {
    id, user: { username: "alice" }, media_type: 2, has_audio: true,
    video_versions: [{ url: SOURCE, width: 720, height: 1280 }],
    image_versions2: { candidates: [{ url: POSTER, width: 720, height: 1280 }] },
    video_dash_manifest: `<MPD><Period><AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2"><Representation bandwidth="128000"><BaseURL>${AUDIO}</BaseURL></Representation></AdaptationSet></Period></MPD>`,
  };
  return {
    url: isStory ? "https://www.instagram.com/api/v1/feed/reels_media/" : "https://www.instagram.com/api/v1/feed/user/42/",
    captured_at: capturedAt,
    payload: isStory ? { reel: { user: { username: "alice" }, items: [item] } } : { items: [item] },
  };
}

async function enrich(payloads) {
  const requests = [];
  const page = {
    evaluate: async () => [],
    context: () => ({
      cookies: async () => [],
      request: { get: async (url) => { requests.push(url); throw new Error(`Unexpected API request: ${url}`); } },
    }),
  };
  const candidate = {
    sourceUrl: SOURCE, posterUrl: POSTER, mediaType: "video",
    pageUrl: "https://www.instagram.com/stories/alice/",
  };
  const result = await enrichStoryMediaCandidate(page, candidate, "alice", [], new Map(), Infinity, payloads, CUTOFF);
  assert.deepEqual(requests, [], "Captured metadata must not trigger a wrong or redundant media-info request");
  return result;
}

test("a portrait profile post captured before Story navigation cannot identify root-URL playback", async () => {
  const result = await enrich([captured("888", 100, false)]);
  assert.equal(result.itemId, undefined);
  assert.equal(result.pageUrl, "https://www.instagram.com/stories/alice/");
  assert.equal(result.audioSourceUrl, undefined);
});

test("current Story metadata wins over an older profile post reusing the same video and poster", async () => {
  const result = await enrich([captured("888", 100, false), captured("111", 250)]);
  assert.equal(result.itemId, "111");
  assert.equal(result.pageUrl, "https://www.instagram.com/stories/alice/111/");
  assert.equal(result.audioSourceUrl, AUDIO);
});

test("metadata captured after Story navigation still identifies root-URL video with audio", async () => {
  const result = await enrich([captured("111", 250)]);
  assert.equal(result.itemId, "111");
  assert.equal(result.pageUrl, "https://www.instagram.com/stories/alice/111/");
  assert.equal(result.audioSourceUrl, AUDIO);
});
