import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";

// These scenarios use actual MP4 fixtures but no browser, Instagram session or network.
const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-blob-stories-"));
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
delete process.env.SAVEME_MEDIA_MUXER;
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));

const { collectStorySequence, waitForStoryMedia } = await import("./bridge.mjs");
const { inspectMp4 } = await import("./mp4_muxer.mjs");
const storyTag = Buffer.from(JSON.stringify({ vencode_tag: "ig_story_xpv_progressive" })).toString("base64url");
const videoUrl = (id) => `https://scontent.cdninstagram.com/story-${id}.mp4?efg=${storyTag}`;

function clockFor(t) {
  let milliseconds = 100_000;
  t.mock.method(Date, "now", () => milliseconds);
  return {
    now: () => milliseconds,
    wait: async (duration) => { milliseconds += duration; },
  };
}

function blobEvaluation(index, scriptTexts = []) {
  return async (callback) => {
    const source = callback.toString();
    if (source.includes("script")) return scriptTexts;
    if (source.includes("return hasDialog ||")) return true;
    if (source.includes("const active = candidates[0]")) return { x: 700, y: 500 };
    if (source.includes("return visible")) {
      return [{
        tag: "video",
        src: `blob:https://www.instagram.com/story-video-${index()}`,
        poster: "",
        width: 720,
        height: 1280,
        area: 720 * 1280,
        containsViewportCenter: true,
        inDialog: true,
        distanceToCenter: 0,
      }];
    }
    throw new Error(`Unexpected browser evaluation: ${source}`);
  };
}

test("a six-second Story wait can resolve the network media behind a blob video", async (t) => {
  const clock = clockFor(t);
  const sourceUrl = videoUrl("111");
  const pageUrl = "https://www.instagram.com/stories/alice/";
  const page = {
    url: () => pageUrl,
    evaluate: blobEvaluation(() => 0),
    waitForTimeout: clock.wait,
    context: () => ({ request: { get: async () => { throw new Error("An unidentified Story must not fetch an arbitrary media id"); } } }),
  };
  const media = await waitForStoryMedia(page, [{ sourceUrl, mediaType: "video", pageUrl, capturedAt: clock.now() / 1000 }], new Set(), 6, "alice", [], new Map());
  assert.ok(media, "Short advancement waits must leave time for network fallback when the DOM video uses blob:");
  assert.equal(media.sourceUrl, sourceUrl);
  assert.equal(media.mediaType, "video");
  assert.ok(clock.now() < 106_000, "The network candidate must be examined before the six-second deadline");
});

test("blob network fallback enriches a numeric Story URL with explicit silent-video metadata", async (t) => {
  const clock = clockFor(t);
  const sourceUrl = videoUrl("222");
  const pageUrl = "https://www.instagram.com/stories/alice/222/";
  const metadataRequests = [];
  const page = {
    url: () => pageUrl,
    evaluate: blobEvaluation(() => 0),
    waitForTimeout: clock.wait,
    context: () => ({
      cookies: async () => [],
      request: { get: async (url) => {
        metadataRequests.push(url);
        assert.equal(url, "https://www.instagram.com/api/v1/media/222/info/");
        return {
          ok: () => true,
          json: async () => ({ items: [{
            id: "222_42", user: { username: "alice" }, has_audio: false,
            video_versions: [{ url: sourceUrl, width: 720, height: 1280 }],
          }] }),
        };
      } },
    }),
  };
  const media = await waitForStoryMedia(page, [{ sourceUrl, mediaType: "video", pageUrl, capturedAt: clock.now() / 1000 }], new Set(), 6, "alice", [], new Map());
  assert.ok(media, "Numeric Story URLs must also reach fallback during advancement");
  assert.equal(media.itemId, "222");
  assert.equal(media.expectsAudio, false, "Known silent media must not acquire an unknown-audio failure");
  assert.equal(metadataRequests.length, 1);
});

test("blob video traversal saves the next video before another navigation with a stable author-only URL", async (t) => {
  await fs.rm(process.env.SAVESTORIES_MANIFESTS, { recursive: true, force: true });
  const destination = await fs.mkdtemp(path.join(runtimeRoot, "sequence-"));
  const clock = clockFor(t);
  const firstBody = await fs.readFile(new URL("./test_fixtures/audio/embedded-audio.mp4", import.meta.url));
  // A valid trailing free box makes the second MP4 distinct without corrupting media tracks.
  const secondBody = Buffer.concat([firstBody, Buffer.from([0, 0, 0, 12, 0x66, 0x72, 0x65, 0x65, 0, 0, 0, 2])]);
  const bodies = new Map([[videoUrl("111"), firstBody], [videoUrl("222"), secondBody]]);
  let index = 0;
  const downloads = [];
  const navigationDownloads = [];
  const pageUrl = () => `https://www.instagram.com/stories/${index === 2 ? "bob" : "alice"}/`;
  const networkCandidates = [{ sourceUrl: videoUrl("111"), mediaType: "video", pageUrl: pageUrl(), capturedAt: clock.now() / 1000 }];
  const advance = async () => {
    navigationDownloads.push(downloads.length);
    index = Math.min(index + 1, 2);
    if (index === 1) {
      networkCandidates.push({ sourceUrl: videoUrl("222"), mediaType: "video", pageUrl: pageUrl(), capturedAt: clock.now() / 1000 });
    }
  };
  const context = {
    request: { get: async (url) => {
      assert.ok(bodies.has(url), `Unexpected media request: ${url}`);
      downloads.push(url);
      return { body: async () => bodies.get(url), headers: () => ({ "content-type": "video/mp4" }) };
    } },
  };
  const nextButton = { isVisible: async () => true, click: advance };
  const page = {
    url: pageUrl,
    context: () => context,
    evaluate: blobEvaluation(() => index),
    waitForTimeout: clock.wait,
    keyboard: { press: advance },
    mouse: { click: advance },
    locator: () => ({ count: async () => 1, nth: () => nextButton }),
  };
  const result = await collectStorySequence(page, destination, "alice", [], networkCandidates, null, true, "video_only");
  assert.deepEqual(downloads, [...bodies.keys()], result.logs.join("\n"));
  assert.equal(result.items.length, 2, "Both available video Stories must be reported, despite blob sources and a URL with no item id");
  assert.deepEqual(navigationDownloads, [1, 2], "Do not press the next control again before resolving and saving the second Story");
  const names = (await fs.readdir(destination)).sort();
  assert.deepEqual(names, ["alice-001.mp4", "alice-002.mp4"]);
  for (const name of names) {
    const inspection = await inspectMp4(path.join(destination, name));
    assert.equal(inspection.hasVideo, true);
    assert.equal(inspection.hasAudio, true);
    assert.equal(inspection.mediaDataComplete, true);
  }
});
