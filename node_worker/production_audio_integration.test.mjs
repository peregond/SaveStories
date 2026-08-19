import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { inspectMp4 } from "./mp4_muxer.mjs";

// bridge.mjs normally discovers user-scoped runtime paths during module load.
// Keep imports hermetic while exercising the exact production download code.
const runtimeRoot = path.join(os.tmpdir(), `saveme-production-audio-${process.pid}`);
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
delete process.env.SAVEME_MEDIA_MUXER;

const {
  downloadMedia,
  fetchActiveStoryItemsForUsername,
  resolveStoryItemFromDict,
  resolveStoryItemsFromPayloads,
} = await import("./bridge.mjs");
const {
  downloadReelMedia,
  resolveReelItemFromDict,
  resolveReelItemsFromPayloads,
} = await import("./reels_downloader.mjs");

const FIXTURES = path.join(import.meta.dirname, "test_fixtures", "audio");
const VIDEO_ONLY = path.join(FIXTURES, "video-only.mp4");
const AUDIO_ONLY = path.join(FIXTURES, "audio-only.m4a");
const VIDEO_URL = "https://scontent-fra5-2.cdninstagram.com/v/t50.2886-16/story-video.mp4";
const AUDIO_URL = "https://scontent-fra5-2.cdninstagram.com/v/t39.12897-16/story-audio.m4a?quality=high";

function dashManifest(audioUrl = AUDIO_URL) {
  return `<MPD><Period>
    <AdaptationSet contentType="video" mimeType="video/mp4" codecs="avc1.640028">
      <Representation bandwidth="4000000"><BaseURL>${VIDEO_URL}</BaseURL></Representation>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2">
      <Representation bandwidth="128000"><BaseURL>${audioUrl.replaceAll("&", "&amp;")}</BaseURL></Representation>
    </AdaptationSet>
  </Period></MPD>`;
}

function videoMetadata(overrides = {}) {
  return {
    id: "1234567890_42",
    code: "REEL123",
    user: { username: "alice" },
    taken_at: 100,
    video_versions: [{ url: VIDEO_URL, width: 720, height: 1280, type: 101 }],
    ...overrides,
  };
}

async function temporaryDirectory(t, label) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), `saveme-${label}-`));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  return directory;
}

function fakeBrowserContext(videoBody, audioBody) {
  const calls = [];
  return {
    calls,
    request: {
      async get(url) {
        calls.push(url);
        if (url === VIDEO_URL) {
          return {
            body: async () => videoBody,
            headers: () => ({ "content-type": "video/mp4" }),
          };
        }
        if (url === AUDIO_URL) {
          return {
            body: async () => audioBody,
            headers: () => ({ "content-type": "audio/mp4" }),
          };
        }
        throw new Error(`unexpected media request: ${url}`);
      },
    },
  };
}

test("Stories metadata resolver extracts the DASH sidecar and preserves tri-state audio", () => {
  const withSidecar = resolveStoryItemFromDict(
    videoMetadata({ video_dash_manifest: dashManifest(), has_audio: false }),
    "alice",
  );
  assert.equal(withSidecar.audioSourceUrl, AUDIO_URL);
  assert.equal(withSidecar.expectsAudio, true, "a sidecar is definitive even if has_audio is stale");
  assert.equal(withSidecar.itemId, "1234567890");

  const explicitlySilent = resolveStoryItemFromDict(videoMetadata({ has_audio: false }), "alice");
  assert.equal(explicitlySilent.audioSourceUrl, null);
  assert.equal(explicitlySilent.expectsAudio, false);

  const unknown = resolveStoryItemFromDict(videoMetadata(), "alice");
  assert.equal(unknown.audioSourceUrl, null);
  assert.equal(unknown.expectsAudio, null);

  const fromCapturedPayload = resolveStoryItemsFromPayloads([
    {
      url: "https://www.instagram.com/api/v1/feed/reels_media/",
      captured_at: 101,
      payload: { reels: { alice: { items: [videoMetadata({ video_dash_manifest: dashManifest() })] } } },
    },
  ], "alice", 100);
  assert.equal(fromCapturedPayload.length, 1);
  assert.equal(fromCapturedPayload[0].audioSourceUrl, AUDIO_URL);
});

test("Reels metadata resolver extracts the DASH sidecar and preserves tri-state audio", () => {
  const withSidecar = resolveReelItemFromDict(
    videoMetadata({ video_dash_manifest: dashManifest(), has_audio: false }),
    "REEL123",
  );
  assert.equal(withSidecar.audioSourceUrl, AUDIO_URL);
  assert.equal(withSidecar.expectsAudio, true);

  const explicitlySilent = resolveReelItemFromDict(videoMetadata({ hasAudio: 0 }), "REEL123");
  assert.equal(explicitlySilent.audioSourceUrl, null);
  assert.equal(explicitlySilent.expectsAudio, false);

  const unknown = resolveReelItemFromDict(videoMetadata(), "REEL123");
  assert.equal(unknown.expectsAudio, null);

  const fromCapturedPayload = resolveReelItemsFromPayloads([
    {
      url: "https://www.instagram.com/api/v1/clips/item/",
      captured_at: 101,
      payload: { items: [videoMetadata({ video_dash_manifest: dashManifest() })] },
    },
  ], "REEL123", 100);
  assert.equal(fromCapturedPayload.length, 1);
  assert.equal(fromCapturedPayload[0].audioSourceUrl, AUDIO_URL);
});

test("metadata resolvers keep richer duplicates and search generic payloads after unrelated preferred responses", () => {
  const partial = videoMetadata({ has_audio: true });
  const rich = videoMetadata({ video_dash_manifest: dashManifest(), has_audio: true });

  const stories = resolveStoryItemsFromPayloads([
    {
      url: "https://www.instagram.com/api/v1/stories/status/",
      captured_at: 101,
      payload: { status: "ok", items: [partial] },
    },
    {
      url: "https://www.instagram.com/graphql/query/",
      captured_at: 102,
      payload: { data: { target: rich } },
    },
  ], "alice", 100);
  assert.equal(stories.length, 1);
  assert.equal(stories[0].audioSourceUrl, AUDIO_URL);
  assert.equal(stories[0].expectsAudio, true);

  const reels = resolveReelItemsFromPayloads([
    {
      url: "https://www.instagram.com/api/v1/feed/reels_tray/",
      captured_at: 101,
      payload: { tray: [{ code: "UNRELATED" }] },
    },
    {
      url: "https://www.instagram.com/graphql/query/",
      captured_at: 102,
      payload: { data: { partial, target: rich } },
    },
  ], "REEL123", 100);
  assert.equal(reels.length, 1);
  assert.equal(reels[0].audioSourceUrl, AUDIO_URL);
  assert.equal(reels[0].expectsAudio, true);
});

test("Stories discovery fetches the active feed without relying on the profile story ring", async () => {
  const calls = [];
  const logs = [];
  const browserContext = {
    async cookies() {
      return [{ name: "csrftoken", value: "csrf-test" }];
    },
    request: {
      async get(url, options) {
        calls.push({ url, options });
        if (url.includes("/users/web_profile_info/")) {
          return {
            ok: () => true,
            status: () => 200,
            json: async () => ({ data: { user: { id: "424242", username: "alice" } } }),
          };
        }
        if (url.endsWith("/feed/user/424242/story/")) {
          return {
            ok: () => true,
            status: () => 200,
            json: async () => ({ reel: { items: [videoMetadata({ video_dash_manifest: dashManifest(), has_audio: true })] } }),
          };
        }
        throw new Error(`unexpected API request: ${url}`);
      },
    },
  };

  const stories = await fetchActiveStoryItemsForUsername(browserContext, "alice", logs);

  assert.equal(stories.length, 1);
  assert.equal(stories[0].itemId, "1234567890");
  assert.equal(stories[0].audioSourceUrl, AUDIO_URL);
  assert.deepEqual(calls.map((call) => call.url), [
    "https://www.instagram.com/api/v1/users/web_profile_info/?username=alice",
    "https://www.instagram.com/api/v1/feed/user/424242/story/",
  ]);
  assert.equal(calls[0].options.headers["X-CSRFToken"], "csrf-test");
  assert.ok(logs.includes("story_feed_items=alice:1"));
});

test("Stories bridge downloadMedia uses the audio pipeline and propagates audioPresent", async (t) => {
  const directory = await temporaryDirectory(t, "story-production-audio");
  const videoBody = await fs.readFile(VIDEO_ONLY);
  const audioBody = await fs.readFile(AUDIO_ONLY);
  const browserContext = fakeBrowserContext(videoBody, audioBody);

  const result = await downloadMedia(
    VIDEO_URL,
    directory,
    "video",
    "alice",
    1,
    browserContext,
    "https://www.instagram.com/stories/alice/1234567890/",
    AUDIO_URL,
    true,
  );

  assert.equal(result.audioMuxed, true);
  assert.equal(result.audioPresent, true);
  assert.equal(result.muxer, "javascript");
  assert.deepEqual(browserContext.calls, [VIDEO_URL, AUDIO_URL]);
  const inspection = await inspectMp4(result.localPath);
  assert.equal(inspection.hasVideo, true);
  assert.equal(inspection.hasAudio, true);
  assert.equal(inspection.videoTracks.length, 1);
  assert.equal(inspection.audioTracks.length, 1);
  assert.deepEqual(await fs.readdir(directory), ["alice-001.mp4"]);
});

test("Reels download uses the audio pipeline and propagates audioPresent", async (t) => {
  const directory = await temporaryDirectory(t, "reel-production-audio");
  const videoBody = await fs.readFile(VIDEO_ONLY);
  const audioBody = await fs.readFile(AUDIO_ONLY);
  const browserContext = fakeBrowserContext(videoBody, audioBody);

  const result = await downloadReelMedia(
    VIDEO_URL,
    directory,
    "video",
    "alice",
    1,
    browserContext,
    "https://www.instagram.com/reel/REEL123/",
    AUDIO_URL,
    true,
    null,
  );

  assert.equal(result.audioMuxed, true);
  assert.equal(result.audioPresent, true);
  assert.equal(result.muxer, "javascript");
  assert.deepEqual(browserContext.calls, [VIDEO_URL, AUDIO_URL]);
  const inspection = await inspectMp4(result.localPath);
  assert.equal(inspection.hasVideo, true);
  assert.equal(inspection.hasAudio, true);
  assert.equal(inspection.videoTracks.length, 1);
  assert.equal(inspection.audioTracks.length, 1);
  assert.deepEqual(await fs.readdir(directory), ["alice-reels-001.mp4"]);
});
