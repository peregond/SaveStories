import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";

const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-late-playlist-"));
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
delete process.env.SAVEME_MEDIA_MUXER;
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));

const { collectStorySequence } = await import("./bridge.mjs");
const { inspectMp4 } = await import("./mp4_muxer.mjs");

const videoUrl = (id) => `https://scontent.cdninstagram.com/late-story-${id}.mp4`;
const audioUrl = (id) => `https://scontent.cdninstagram.com/late-story-${id}.m4a`;
const metadata = (id, order) => ({
  id: `${id}_42`,
  user: { username: "alice" },
  taken_at: order,
  media_type: 2,
  has_audio: true,
  video_versions: [{ url: videoUrl(id), width: 720, height: 1280 }],
  video_dash_manifest: `<MPD><Period><AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2"><Representation bandwidth="128000"><BaseURL>${audioUrl(id)}</BaseURL></Representation></AdaptationSet></Period></MPD>`,
});

for (const initialDiscovery of ["singleton", "empty", "incomplete earlier audio"]) {
  test(`a complete playlist arriving after ${initialDiscovery} discovery saves videos before and after the current unread Story`, async (t) => {
    const destination = path.join(runtimeRoot, initialDiscovery, "alice");
    const baseBody = await fs.readFile(new URL("./test_fixtures/audio/embedded-audio.mp4", import.meta.url));
    const videoOnlyBody = await fs.readFile(new URL("./test_fixtures/audio/video-only.mp4", import.meta.url));
    const audioOnlyBody = await fs.readFile(new URL("./test_fixtures/audio/audio-only.m4a", import.meta.url));
    const retriesEarlierAudio = initialDiscovery === "incomplete earlier audio";
    const ids = ["111", "222", "333"];
    const rawItems = ids.map((id, index) => metadata(id, index + 1));
    // Distinct, valid MP4 files keep content deduplication meaningful.
    const bodies = new Map(ids.map((id, index) => [videoUrl(id), Buffer.concat([
      retriesEarlierAudio && index === 0 ? videoOnlyBody : baseBody,
      Buffer.from([0, 0, 0, 12, 0x66, 0x72, 0x65, 0x65, 0, 0, 0, index + 1]),
    ])]));
    const requests = [];
    const payloads = [];
    let now = 100_000;
    let owner = "alice";
    let fullPlaylistArrived = false;
    t.mock.method(Date, "now", () => now);
    const context = {
      request: { async get(url) {
        requests.push(url);
        if (retriesEarlierAudio && url === audioUrl("111")) {
          return { body: async () => audioOnlyBody, headers: () => ({ "content-type": "audio/mp4" }) };
        }
        assert.ok(bodies.has(url), `Unexpected metadata/audio request: ${url}`);
        return { body: async () => bodies.get(url), headers: () => ({ "content-type": "video/mp4" }) };
      } },
    };
    const advance = async () => { owner = "bob"; };
    const page = {
      context: () => context,
      url: () => `https://www.instagram.com/stories/${owner}/222/`,
      waitForTimeout: async (duration) => { now += duration; },
      keyboard: { press: advance }, mouse: { click: advance },
      locator: () => ({ count: async () => 1, nth: () => ({ isVisible: async () => true, click: advance }) }),
      async evaluate(callback) {
        const code = callback.toString();
        if (code.includes("script")) {
          const initialItems = initialDiscovery === "singleton" ? [rawItems[1]] :
            retriesEarlierAudio ? [{ ...rawItems[0], video_dash_manifest: null }] : [];
          const items = fullPlaylistArrived ? rawItems : initialItems;
          return [JSON.stringify({ data: { reel: { user: { username: "alice" }, items } } })];
        }
        if (code.includes("return hasDialog ||")) {
          if (!fullPlaylistArrived) {
            fullPlaylistArrived = true;
            payloads.push({
              url: "https://www.instagram.com/api/v1/feed/reels_media/",
              captured_at: now / 1000,
              payload: { reels: { "42": { user: { username: "alice" }, items: rawItems } } },
            });
          }
          return true;
        }
        if (code.includes("return visible")) return [{
          tag: "video", src: videoUrl("222"), poster: "", width: 720, height: 1280,
          area: 720 * 1280, containsViewportCenter: true, inDialog: true, distanceToCenter: 0,
        }];
        if (code.includes("const active = candidates[0]")) return { x: 700, y: 500 };
        throw new Error(`Unexpected page evaluation: ${code}`);
      },
    };

    const result = await collectStorySequence(page, destination, "alice", payloads, [], null, true, "video_only");

    assert.equal(fullPlaylistArrived, true);
    assert.equal(result.items.length, 3, result.logs.join("\n"));
    assert.deepEqual(new Set(result.items.map((item) => item.pageURL)), new Set(ids.map((id) => `https://www.instagram.com/stories/alice/${id}/`)));
    assert.equal(requests.length, retriesEarlierAudio ? 5 : 3, "Already saved current Story must not be downloaded again during playlist refresh");
    assert.deepEqual(new Set(requests), new Set([...ids.map(videoUrl), ...(retriesEarlierAudio ? [audioUrl("111")] : [])]));
    for (const item of result.items) {
      const inspection = await inspectMp4(item.localPath);
      assert.equal(inspection.hasVideo, true);
      assert.equal(inspection.hasAudio, true);
      assert.equal(inspection.mediaDataComplete, true);
    }
    assert.equal(result.logs.at(-1), "metadata_story_items=3", "Found count must include the complete late playlist");
  });
}
