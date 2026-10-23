import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";
import { inspectMp4 } from "./mp4_muxer.mjs";

const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-story-identity-"));
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
delete process.env.SAVEME_MEDIA_MUXER;
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));

const { enrichStoryMediaCandidate, collectStorySequence } = await import("./bridge.mjs");
const VIDEO_URL = "https://scontent.cdninstagram.com/story-video.mp4?version=1";
const AUDIO_URL = "https://scontent.cdninstagram.com/story-audio.m4a";
const POSTER_URL = "https://scontent.cdninstagram.com/story-poster.jpg";
const ROOT_URL = "https://www.instagram.com/stories/alice/";

function rawMetadata(id = "111", overrides = {}) {
  return {
    id: `${id}_42`, user: { username: "alice" }, media_type: 2,
    video_versions: [{ url: VIDEO_URL, width: 720, height: 1280 }],
    image_versions2: { candidates: [{ url: POSTER_URL, width: 720, height: 1280 }] },
    has_audio: true,
    video_dash_manifest: `<MPD><Period><AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2"><Representation bandwidth="128000"><BaseURL>${AUDIO_URL}</BaseURL></Representation></AdaptationSet></Period></MPD>`,
    ...overrides,
  };
}

function captured(...items) {
  return [{
    url: "https://www.instagram.com/api/v1/feed/reels_media/",
    captured_at: 100,
    payload: { reels: { "42": { user: { username: "alice" }, items } } },
  }];
}

function candidate(overrides = {}) {
  return {
    sourceUrl: VIDEO_URL,
    mediaType: "video",
    pageUrl: ROOT_URL,
    posterUrl: POSTER_URL,
    width: 720, height: 1280,
    ...overrides,
  };
}

function metadataHarness(scriptTexts = [], infoPayload = null) {
  const requests = [];
  const context = {
    cookies: async () => [],
    request: {
      async get(url) {
        requests.push(url);
        assert.ok(infoPayload, `Unexpected metadata request: ${url}`);
        return { ok: () => true, json: async () => infoPayload };
      },
    },
  };
  const page = {
    url: () => ROOT_URL,
    context: () => context,
    evaluate: async () => scriptTexts,
    locator: () => ({ allTextContents: async () => scriptTexts }),
    content: async () => scriptTexts.join("\n"),
  };
  return { page, requests };
}

function assertIdentifiedVideo(result, id) {
  assert.equal(result.itemId, id);
  assert.equal(result.username, "alice");
  assert.equal(result.audioSourceUrl, AUDIO_URL);
  assert.equal(result.expectsAudio, true);
  assert.equal(result.pageUrl, `https://www.instagram.com/stories/alice/${id}/`);
}

test("root Story URL is identified by captured video metadata after byte-range normalization", async () => {
  const { page, requests } = metadataHarness();
  const playback = candidate({ sourceUrl: `${VIDEO_URL}&bytestart=0&byteend=999` });
  const result = await enrichStoryMediaCandidate(page, playback, "alice", [], new Map(), Infinity, captured(rawMetadata()));
  assertIdentifiedVideo(result, "111");
  assert.deepEqual(requests, [], "Complete captured audio metadata must not need another API lookup");
});

test("root Story URL can match its poster when the playback variant differs from metadata", async () => {
  const { page } = metadataHarness();
  const playback = candidate({ sourceUrl: "https://scontent.cdninstagram.com/another-playback-variant.mp4" });
  const result = await enrichStoryMediaCandidate(page, playback, "alice", [], new Map(), Infinity, captured(rawMetadata("222")));
  assertIdentifiedVideo(result, "222");
});

test("a root Story uses its matched numeric id to fetch missing DASH audio metadata", async () => {
  const incomplete = rawMetadata("333", { video_dash_manifest: null });
  const { page, requests } = metadataHarness([], { items: [rawMetadata("333")] });
  const result = await enrichStoryMediaCandidate(page, candidate(), "alice", [], new Map(), Infinity, captured(incomplete));
  assertIdentifiedVideo(result, "333");
  assert.deepEqual(requests, ["https://www.instagram.com/api/v1/media/333/info/"]);
});

test("embedded Story data identifies root-URL playback and preserves its audio sidecar", async () => {
  const scripts = [JSON.stringify({ require: [["ScheduledServerJS", "handle", null, [{
    data: { reel: { user: { username: "alice" }, items: [rawMetadata("444")] } },
  }]]] })];
  const { page, requests } = metadataHarness(scripts);
  const result = await enrichStoryMediaCandidate(page, candidate(), "alice", [], new Map(), Infinity, []);
  assertIdentifiedVideo(result, "444");
  assert.deepEqual(requests, []);
});

test("numeric-id metadata cache can identify the same video under a root Story URL", async () => {
  const { page, requests } = metadataHarness();
  const cache = new Map([["777", {
    itemId: "777", username: "alice", mediaType: "video",
    pageUrl: "https://www.instagram.com/stories/alice/777/",
    sourceUrl: VIDEO_URL, audioSourceUrl: AUDIO_URL, expectsAudio: true,
  }]]);
  const result = await enrichStoryMediaCandidate(page, candidate(), "alice", [], cache, Infinity, []);
  assertIdentifiedVideo(result, "777");
  assert.deepEqual(requests, []);
});

test("unrelated owners and unidentified root-URL playback never request media/undefined", async () => {
  const { page, requests } = metadataHarness();
  const payloads = captured(rawMetadata("555", { user: { username: "bob" } }));
  const result = await enrichStoryMediaCandidate(page, candidate(), "alice", [], new Map(), Infinity, payloads);
  assert.notEqual(result?.itemId, "555");
  assert.notEqual(result?.username, "bob");
  assert.deepEqual(requests, []);
});

test("root-URL traversal uses metadata arriving after initial discovery to save a video with audio", async (t) => {
  await fs.rm(process.env.SAVESTORIES_MANIFESTS, { recursive: true, force: true });
  const destination = path.join(runtimeRoot, "late-capture", "alice");
  const videoBody = await fs.readFile(new URL("./test_fixtures/audio/video-only.mp4", import.meta.url));
  const audioBody = await fs.readFile(new URL("./test_fixtures/audio/audio-only.m4a", import.meta.url));
  let now = 100_000;
  t.mock.method(Date, "now", () => now);
  let owner = "alice";
  let metadataArrived = false;
  const payloads = [];
  const requests = [];
  const context = {
    cookies: async () => [],
    request: { async get(url) {
      requests.push(url);
      if (url === VIDEO_URL) return { body: async () => videoBody, headers: () => ({ "content-type": "video/mp4" }) };
      if (url === AUDIO_URL) return { body: async () => audioBody, headers: () => ({ "content-type": "audio/mp4" }) };
      throw new Error(`Unexpected media request: ${url}`);
    } },
  };
  const advance = async () => { owner = "bob"; };
  const page = {
    context: () => context,
    url: () => `https://www.instagram.com/stories/${owner}/`,
    waitForTimeout: async (duration) => { now += duration; },
    keyboard: { press: advance }, mouse: { click: advance },
    locator: () => ({ count: async () => 1, nth: () => ({ isVisible: async () => true, click: advance }), allTextContents: async () => [] }),
    content: async () => "",
    async evaluate(callback) {
      const code = callback.toString();
      if (code.includes("script")) return [];
      if (code.includes("return hasDialog ||")) {
        if (!metadataArrived) {
          payloads.push(...captured(rawMetadata("666")));
          metadataArrived = true;
        }
        return true;
      }
      if (code.includes("const active = candidates[0]")) return { x: 700, y: 500 };
      if (code.includes("return visible")) return [{
        tag: "video", src: VIDEO_URL, poster: POSTER_URL, width: 720, height: 1280,
        area: 720 * 1280, containsViewportCenter: true, inDialog: true, distanceToCenter: 0,
      }];
      throw new Error(`Unexpected page evaluation: ${code}`);
    },
  };

  const result = await collectStorySequence(page, destination, "alice", payloads, [], null, true, "video_only");

  assert.equal(metadataArrived, true);
  assert.equal(result.items.length, 1, result.logs.join("\n"));
  assert.equal(result.items[0].pageURL, "https://www.instagram.com/stories/alice/666/");
  const inspection = await inspectMp4(result.items[0].localPath);
  assert.equal(inspection.hasVideo, true);
  assert.equal(inspection.hasAudio, true);
  assert.equal(inspection.mediaDataComplete, true);
  assert.deepEqual(requests, [VIDEO_URL, AUDIO_URL]);
});
