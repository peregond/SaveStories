import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";

// Exercise the real bridge without reading or writing a user's runtime/session.
const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-story-sequence-"));
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
delete process.env.SAVEME_MEDIA_MUXER;
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));

const {
  collectStorySequence,
  resolveStoryItemsFromScriptTexts,
  waitForMetadataStoryItems,
} = await import("./bridge.mjs");

function imageMetadata(id, username = "alice", takenAt = Number(id)) {
  return {
    id: `${id}_42`,
    user: { username },
    taken_at: takenAt,
    original_width: 720,
    original_height: 1280,
    image_versions2: {
      candidates: [{ url: `https://scontent.cdninstagram.com/story-${id}.jpg`, width: 720, height: 1280 }],
    },
  };
}

function anonymousMetadata(id) {
  const result = imageMetadata(id);
  delete result.user;
  return result;
}

function imageBytes(id) {
  const body = Buffer.alloc(1024, Number(id) % 256);
  body.set([0xff, 0xd8, 0xff, 0xe0]);
  return body;
}

function fakeClock(t) {
  let now = 100_000;
  t.mock.method(Date, "now", () => now);
  return async (duration) => { now += duration; };
}

async function viewerHarness(t, stories, scriptTexts = []) {
  await fs.rm(process.env.SAVESTORIES_MANIFESTS, { recursive: true, force: true });
  const destination = await fs.mkdtemp(path.join(runtimeRoot, "author-"));
  const waitForTimeout = fakeClock(t);
  const downloads = [];
  let index = 0;
  let advanceCount = 0;
  const current = () => stories[index];
  const advance = async () => {
    advanceCount += 1;
    index = Math.min(index + 1, stories.length - 1);
  };
  const context = {
    request: {
      async get(url) {
        downloads.push(url);
        const metadata = stories.find((entry) => entry.image_versions2.candidates[0].url === url);
        assert.ok(metadata, `Unexpected download URL: ${url}`);
        return {
          body: async () => imageBytes(metadata.id.split("_")[0]),
          headers: () => ({ "content-type": "image/jpeg" }),
        };
      },
    },
  };
  const nextButton = { isVisible: async () => true, click: advance };
  const page = {
    context: () => context,
    url: () => `https://www.instagram.com/stories/${current().user.username}/${current().id.split("_")[0]}/`,
    waitForTimeout,
    keyboard: { press: advance },
    mouse: { click: advance },
    locator(selector) {
      if (selector.includes("script")) return { allTextContents: async () => scriptTexts };
      return { count: async () => 1, nth: () => nextButton };
    },
    async evaluate(callback) {
      const source = callback.toString();
      if (source.includes("script")) return scriptTexts;
      if (source.includes("return hasDialog ||")) return true;
      if (source.includes("const active = candidates[0]")) return { x: 700, y: 500 };
      if (source.includes("return visible")) {
        return [{
          tag: "img",
          src: current().image_versions2.candidates[0].url,
          poster: "",
          width: 720,
          height: 1280,
          area: 720 * 1280,
          containsViewportCenter: true,
          inDialog: true,
          distanceToCenter: 0,
        }];
      }
      throw new Error(`Unexpected page evaluation: ${source}`);
    },
  };
  return { page, destination, downloads, advanceCount: () => advanceCount };
}

test("embedded Story data inherits its owner's username and rejects other or unidentified owners", () => {
  const scripts = [
    "not JSON",
    JSON.stringify({
      require: [["ScheduledServerJS", "handle", null, [{
        data: {
          reels: {
            target: { user: { username: "alice" }, items: [anonymousMetadata("111")] },
            unrelated: { user: { username: "bob" }, items: [anonymousMetadata("222")] },
            explicitOtherOwner: imageMetadata("333", "bob"),
            unidentifiedRecommendation: anonymousMetadata("444"),
          },
        },
      }]]],
    }),
  ];
  const resolved = resolveStoryItemsFromScriptTexts(scripts, "alice");
  assert.deepEqual(resolved.map((item) => item.itemId), ["111"]);
  assert.equal(resolved[0].username, "alice");
  assert.equal(resolved[0].pageUrl, "https://www.instagram.com/stories/alice/111/");
});

test("embedded profile and feed posts are not active Stories even when their owner matches", () => {
  const resolved = resolveStoryItemsFromScriptTexts([JSON.stringify({
    data: {
      profile: { user: { username: "alice" }, posts: [imageMetadata("444")] },
      feed: { items: [imageMetadata("555")] },
    },
  })], "alice");
  assert.deepEqual(resolved, []);
});

test("embedded duplicate Story metadata preserves its DASH audio sidecar", () => {
  const videoUrl = "https://scontent.cdninstagram.com/story-video.mp4";
  const audioUrl = "https://scontent.cdninstagram.com/story-audio.m4a";
  const rich = {
    id: "555_42", user: { username: "alice" }, taken_at: 10,
    video_versions: [{ url: videoUrl, width: 720, height: 1280 }],
    has_audio: true,
    video_dash_manifest: `<MPD><Period><AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2"><Representation bandwidth="128000"><BaseURL>${audioUrl}</BaseURL></Representation></AdaptationSet></Period></MPD>`,
  };
  const partial = { ...rich, video_dash_manifest: undefined, has_audio: undefined };
  const resolved = resolveStoryItemsFromScriptTexts([
    JSON.stringify({ reel: { items: [rich] } }),
    JSON.stringify({ reel: { items: [partial] } }),
  ], "alice");
  assert.equal(resolved.length, 1);
  assert.equal(resolved[0].audioSourceUrl, audioUrl);
  assert.equal(resolved[0].expectsAudio, true);
});

test("Story metadata waiting combines embedded playlist entries with a singleton network response", async (t) => {
  const logs = [];
  const page = {
    waitForTimeout: fakeClock(t),
    locator: () => ({ allTextContents: async () => [JSON.stringify({ reel: { user: { username: "alice" }, items: [anonymousMetadata("222"), anonymousMetadata("333")] } })] }),
    evaluate: async () => [JSON.stringify({ reel: { user: { username: "alice" }, items: [anonymousMetadata("222"), anonymousMetadata("333")] } })],
  };
  const result = await waitForMetadataStoryItems(page, [
    { url: "https://www.instagram.com/api/v1/media/111/info/", captured_at: 100, payload: { items: [imageMetadata("111")] } },
  ], "alice", logs, 1);
  assert.deepEqual(result.map((item) => item.itemId), ["111", "222", "333"]);
});

test("a singleton prefetch preserves its saved file and continues to the next Story", async (t) => {
  const stories = [imageMetadata("111"), imageMetadata("222"), imageMetadata("333", "bob")];
  const { page, destination, downloads, advanceCount } = await viewerHarness(t, stories);
  const prefetched = [{
    itemId: "111", username: "alice", mediaType: "image", takenAt: 111,
    pageUrl: "https://www.instagram.com/stories/alice/111/",
    sourceUrl: stories[0].image_versions2.candidates[0].url,
    audioSourceUrl: null, expectsAudio: false,
  }];
  const result = await collectStorySequence(page, destination, "alice", [], [], null, true, "all", prefetched);
  assert.equal(result.items.length, 2, result.logs.join("\n"));
  assert.deepEqual(result.items.map((item) => item.pageURL), [
    "https://www.instagram.com/stories/alice/111/",
    "https://www.instagram.com/stories/alice/222/",
  ]);
  assert.deepEqual(downloads, stories.slice(0, 2).map((entry) => entry.image_versions2.candidates[0].url));
  assert.ok(advanceCount() >= 2);
  const names = (await fs.readdir(destination)).sort();
  assert.deepEqual(names, ["alice-001.jpg", "alice-002.jpg"]);
  assert.deepEqual(await fs.readFile(path.join(destination, names[0])), imageBytes("111"));
  assert.deepEqual(await fs.readFile(path.join(destination, names[1])), imageBytes("222"));
});

test("viewer traversal stops when Instagram advances to a different influencer", async (t) => {
  const stories = [imageMetadata("777"), imageMetadata("888", "bob")];
  const { page, destination, downloads } = await viewerHarness(t, stories);
  const result = await collectStorySequence(page, destination, "alice", [], [], null, false);
  assert.equal(result.items.length, 1, result.logs.join("\n"));
  assert.deepEqual(downloads, [stories[0].image_versions2.candidates[0].url]);
  assert.deepEqual(await fs.readdir(destination), ["alice-001.jpg"]);
});

test("a singleton playlist is supplemented from the per-user Story endpoint", async () => {
  const { fetchActiveStoryItemsForUsername } = await import("./bridge.mjs");
  const calls = [];
  const context = {
    cookies: async () => [],
    request: { async get(url) {
      calls.push(url);
      const entries = url.includes("reels_media") ? [imageMetadata("111")] : [imageMetadata("111"), imageMetadata("222"), imageMetadata("333")];
      return { ok: () => true, json: async () => ({ reel: { user: { username: "alice" }, items: entries } }) };
    } },
  };
  const items = await fetchActiveStoryItemsForUsername(context, "alice", [], "424242");
  assert.deepEqual(items.map((item) => item.itemId), ["111", "222", "333"]);
  assert.equal(calls.length, 2);
});

test("duplicate videos and failed downloads are not reported as absent videos", async () => {
  const { summarizeStoryDownload } = await import("./bridge.mjs");
  const duplicate = summarizeStoryDownload({ items: [], logs: ["metadata_story_items=3", "skipped_existing_source=https://example.test/video.mp4"] }, "alice", "video_only");
  assert.equal(duplicate.status, "download_duplicate");
  const failed = summarizeStoryDownload({ items: [], logs: ["metadata_story_items=3", "story_item_failed=111:403 Forbidden"] }, "alice", "video_only");
  assert.equal(failed.ok, false);
  assert.equal(failed.status, "download_error");
  assert.equal(failed.data.failedCount, "1");
  const filtered = summarizeStoryDownload({ items: [], logs: ["metadata_story_items=3", "skipped_by_media_filter=image"] }, "alice", "video_only");
  assert.equal(filtered.status, "download_filtered");
  const partial = summarizeStoryDownload({ items: [{ localPath: "saved.mp4" }], logs: ["metadata_story_items=3", "story_item_failed=222:403 Forbidden"] }, "alice", "video_only");
  assert.equal(partial.ok, true);
  assert.equal(partial.status, "download_partial");
  assert.equal(partial.data.savedCount, "1");
  assert.equal(partial.data.failedCount, "1");
});

test("viewer reuses one history index while persisting multiple Stories", async (t) => {
  const stories = [imageMetadata("111"), imageMetadata("222"), imageMetadata("333", "bob")];
  const { page, destination } = await viewerHarness(t, stories);
  const original = fs.readdir;
  let historyReads = 0;
  t.mock.method(fs, "readdir", async (directory, ...args) => {
    if (path.resolve(directory) === path.resolve(process.env.SAVESTORIES_MANIFESTS)) historyReads += 1;
    return await original(directory, ...args);
  });
  const result = await collectStorySequence(page, destination, "alice", [], [], null, false);
  assert.equal(result.items.length, 2, result.logs.join("\n"));
  assert.equal(historyReads, 1);
});

test("profile deadline preserves saved Stories and bounds the next media request", async (t) => {
  const stories = [imageMetadata("111"), imageMetadata("222"), imageMetadata("333", "bob")];
  const { page, destination } = await viewerHarness(t, stories);
  const deadline = Date.now() + 30_000;
  const originalGet = page.context().request.get;
  let nextTimeout;
  page.context().request.get = async (url, options) => {
    if (url.endsWith("story-222.jpg")) {
      nextTimeout = options.timeout;
      await page.waitForTimeout(options.timeout + 1);
      throw new Error("Timeout: media response stalled");
    }
    return await originalGet(url, options);
  };
  const result = await collectStorySequence(page, destination, "alice", [], [], null, false, "all", [], deadline);
  assert.equal(result.items.length, 1, result.logs.join("\n"));
  assert.ok(nextTimeout > 0 && nextTimeout < 30_000);
  assert.deepEqual(await fs.readFile(result.items[0].localPath), imageBytes("111"));
  assert.ok(result.logs.some((line) => line.startsWith("story_traversal_failed=")));
});

test("a failed prefetched Story can be recovered by the viewer", async (t) => {
  const stories = [imageMetadata("111"), imageMetadata("222", "bob")];
  const { page, destination } = await viewerHarness(t, stories);
  const originalGet = page.context().request.get;
  let attempts = 0;
  page.context().request.get = async (...args) => {
    if (++attempts === 1) throw new Error("403 Forbidden: temporary media URL");
    return await originalGet(...args);
  };
  const prefetched = [{
    itemId: "111", username: "alice", mediaType: "image", takenAt: 111,
    pageUrl: "https://www.instagram.com/stories/alice/111/",
    sourceUrl: stories[0].image_versions2.candidates[0].url,
    audioSourceUrl: null, expectsAudio: false,
  }];
  const result = await collectStorySequence(page, destination, "alice", [], [], null, true, "all", prefetched);
  assert.equal(result.items.length, 1, result.logs.join("\n"));
  assert.equal(attempts, 2);
  const { summarizeStoryDownload } = await import("./bridge.mjs");
  assert.equal(summarizeStoryDownload(result, "alice").data.failedCount, "0");
});
