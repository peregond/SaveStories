import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";
import { inspectMp4, inspectMp4Buffer } from "./mp4_muxer.mjs";

const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-story-navigation-"));
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
delete process.env.SAVEME_MEDIA_MUXER;
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));

const { downloadProfileWithPage } = await import("./bridge.mjs");
const PROFILE_URL = "https://www.instagram.com/alice/";
const STORY_ROOT_URL = "https://www.instagram.com/stories/alice/";

function uniqueCompleteVideo(body, id) {
  const payload = Buffer.from(`story-${id}`);
  const freeBox = Buffer.alloc(8 + payload.length);
  freeBox.writeUInt32BE(freeBox.length);
  freeBox.write("free", 4, "ascii");
  payload.copy(freeBox, 8);
  const variant = Buffer.concat([body, freeBox]);
  const inspection = inspectMp4Buffer(variant);
  assert.equal(inspection.hasAudio, true);
  assert.equal(inspection.mediaDataComplete, true);
  return variant;
}

test("profile API rate limiting still reaches the full Story playlist by direct root navigation", async (t) => {
  const fixture = await fs.readFile(new URL("./test_fixtures/audio/embedded-audio.mp4", import.meta.url));
  const ids = ["811", "822", "833"];
  const mediaBodies = new Map(ids.map((id) => [
    `https://scontent.cdninstagram.com/story-${id}.mp4`, uniqueCompleteVideo(fixture, id),
  ]));
  const metadata = ids.map((id) => ({
    id: `${id}_42`, user: { username: "alice" }, media_type: 2, taken_at: Number(id),
    has_audio: true,
    video_versions: [{ url: `https://scontent.cdninstagram.com/story-${id}.mp4`, width: 720, height: 1280 }],
  }));
  let now = 100_000;
  t.mock.method(Date, "now", () => now);
  let currentUrl = "about:blank";
  let mode = "profile";
  let ringClicks = 0;
  const navigations = [];
  const requests = [];
  const scripts = () => mode === "full-story" ? [JSON.stringify({
    require: [["ScheduledServerJS", "handle", null, [{
      data: { reel: { user: { username: "alice" }, items: metadata } },
    }]]],
  })] : [];
  const advance = async () => { currentUrl = "https://www.instagram.com/stories/bob/"; };
  const context = {
    cookies: async () => [{ name: "sessionid", value: "test-session", domain: ".instagram.com" }],
    storageState: async () => ({ cookies: [], origins: [] }),
    request: { async get(url) {
      requests.push(url);
      if (url.includes("/users/web_profile_info/")) return { ok: () => false, status: () => 429 };
      const body = mediaBodies.get(url);
      assert.ok(body, `Unexpected media request: ${url}`);
      return { body: async () => body, headers: () => ({ "content-type": "video/mp4" }) };
    } },
  };
  const page = {
    on: () => {},
    context: () => context,
    url: () => currentUrl,
    async goto(url) {
      navigations.push(url);
      currentUrl = url;
      mode = url === STORY_ROOT_URL ? "full-story" : "profile";
    },
    waitForTimeout: async (duration) => { now += duration; },
    content: async () => "<html><title>Instagram</title></html>",
    keyboard: { press: advance }, mouse: { click: advance },
    locator(selector) {
      if (selector === "script") return { allTextContents: async () => scripts() };
      if (selector.startsWith("a[href=\"/stories/") || selector.startsWith("header ")) {
        return { first: () => ({ count: async () => 1, click: async () => {
          // The profile ring is a SPA transition: it exposes only the current
          // unread item, whereas a direct navigation embeds the complete reel.
          ringClicks += 1;
          mode = "spa-story";
          currentUrl = STORY_ROOT_URL;
        } }) };
      }
      if (selector.includes("has-text")) return { first: () => ({ count: async () => 0 }) };
      return { count: async () => 1, nth: () => ({ isVisible: async () => true, click: advance }) };
    },
    async evaluate(callback) {
      const code = callback.toString();
      if (code.includes("script")) return scripts();
      if (code.includes("return hasDialog ||")) return true;
      if (code.includes("const active = candidates[0]")) return { x: 700, y: 500 };
      if (code.includes("return visible")) return [{
        tag: "video", src: metadata[0].video_versions[0].url, poster: "",
        width: 720, height: 1280, area: 720 * 1280,
        containsViewportCenter: true, inDialog: true, distanceToCenter: 0,
      }];
      throw new Error(`Unexpected page evaluation: ${code}`);
    },
  };

  const result = await downloadProfileWithPage(page, PROFILE_URL, path.join(runtimeRoot, "downloads"), "video_only");

  assert.deepEqual(navigations, [PROFILE_URL, STORY_ROOT_URL]);
  assert.equal(ringClicks, 0, "The incomplete profile-ring SPA transition must not be used for initial discovery");
  assert.ok(requests.some((url) => url.includes("/users/web_profile_info/")));
  assert.ok(result.logs.includes("story_profile_info_status=alice:429"), result.logs.join("\n"));
  assert.equal(result.status, "download_complete", result.logs.join("\n"));
  assert.equal(result.data.savedCount, "3");
  assert.equal(result.items.length, 3, result.logs.join("\n"));
  assert.deepEqual(result.items.map((item) => item.pageURL), ids.map((id) => `${STORY_ROOT_URL}${id}/`));
  for (const item of result.items) {
    const inspection = await inspectMp4(item.localPath);
    assert.equal(inspection.hasVideo, true);
    assert.equal(inspection.hasAudio, true);
    assert.equal(inspection.mediaDataComplete, true);
  }
  assert.equal(requests.filter((url) => mediaBodies.has(url)).length, 3);
});
