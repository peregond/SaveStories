import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";
import { inspectMp4Buffer } from "./mp4_muxer.mjs";

// Exercise the production persistence loop without touching the user's history,
// Instagram session, or downloads directory.
const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-story-persistence-"));
const manifestsDirectory = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = manifestsDirectory;
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
delete process.env.SAVEME_MEDIA_MUXER;

const { persistStoryItems } = await import("./bridge.mjs");
const videoBody = await fs.readFile(new URL("./test_fixtures/audio/video-only.mp4", import.meta.url));
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));

function videoItem(id, sourceUrl = `https://scontent.cdninstagram.com/story-${id}.mp4`) {
  return {
    itemId: id,
    username: "alice",
    pageUrl: `https://www.instagram.com/stories/alice/${id}/`,
    sourceUrl,
    audioSourceUrl: null,
    expectsAudio: false,
    mediaType: "video",
    takenAt: 100,
  };
}

function fakeBrowserContext(responses) {
  const calls = [];
  return {
    calls,
    request: {
      async get(url) {
        calls.push(url);
        const response = responses.get(url);
        if (response instanceof Error) throw response;
        assert.ok(response, `Unexpected download request: ${url}`);
        return {
          body: async () => response.body,
          headers: () => ({ "content-type": response.contentType }),
        };
      },
    },
  };
}

async function newCase(label) {
  // Tests run serially because the imported worker binds its manifest root once.
  await fs.rm(manifestsDirectory, { recursive: true, force: true });
  await fs.mkdir(manifestsDirectory, { recursive: true });
  return await fs.mkdtemp(path.join(runtimeRoot, `${label}-`));
}

async function seedManifest(name, sourceURL, localPath, body = videoBody) {
  await fs.writeFile(path.join(manifestsDirectory, `${name}.json`), JSON.stringify({
    id: name,
    sourceURL,
    localPath,
    mediaType: "video",
    sha256: createHash("sha256").update(body).digest("hex"),
    audioPresent: false,
    audioMuxed: false,
  }));
}

test("Stories restore a missing file despite a manifest for the same source URL", async () => {
  const root = await newCase("missing-source");
  const destination = path.join(root, "alice");
  const item = videoItem("1001");
  await seedManifest("missing", item.sourceUrl, path.join(destination, "alice-001.mp4"));
  const context = fakeBrowserContext(new Map([[item.sourceUrl, { body: videoBody, contentType: "video/mp4" }]]));

  const result = await persistStoryItems([item], destination, "alice", context, "video_only");

  assert.equal(result.items.length, 1, result.logs.join("\n"));
  assert.deepEqual(context.calls, [item.sourceUrl]);
  assert.deepEqual(await fs.readFile(result.items[0].localPath), videoBody);
});

test("Stories restore a missing file when only an old content-hash manifest matches", async () => {
  const root = await newCase("missing-hash");
  const destination = path.join(root, "alice");
  const item = videoItem("1002");
  await seedManifest("expired-url", "https://scontent.cdninstagram.com/old-signed-url.mp4", path.join(destination, "alice-001.mp4"));
  const context = fakeBrowserContext(new Map([[item.sourceUrl, { body: videoBody, contentType: "video/mp4" }]]));

  const result = await persistStoryItems([item], destination, "alice", context, "video_only");

  assert.equal(result.items.length, 1, result.logs.join("\n"));
  assert.deepEqual(await fs.readFile(result.items[0].localPath), videoBody);
  assert.equal(result.logs.some((entry) => entry.startsWith("skipped_existing_hash=")), false);
});

test("Stories save into a new destination even when the same video exists elsewhere", async () => {
  const root = await newCase("new-destination");
  const firstDestination = path.join(root, "first", "alice");
  const secondDestination = path.join(root, "second", "alice");
  const item = videoItem("1003");
  const context = fakeBrowserContext(new Map([[item.sourceUrl, { body: videoBody, contentType: "video/mp4" }]]));

  const first = await persistStoryItems([item], firstDestination, "alice", context, "video_only");
  const second = await persistStoryItems([item], secondDestination, "alice", context, "video_only");

  assert.equal(first.items.length, 1, first.logs.join("\n"));
  assert.equal(second.items.length, 1, second.logs.join("\n"));
  assert.equal(path.dirname(second.items[0].localPath), secondDestination);
  assert.deepEqual(await fs.readFile(first.items[0].localPath), videoBody);
  assert.deepEqual(await fs.readFile(second.items[0].localPath), videoBody);

  const repeated = await persistStoryItems([item], firstDestination, "alice", context, "video_only");
  assert.equal(repeated.items.length, 0, "A real existing file in the requested folder is still a duplicate");
  assert.equal(context.calls.length, 2, "The repeated download must not issue a third media request");
});

function distinctVideoBody(label) {
  // An additional free box changes the content hash without changing the valid
  // fixture's tracks, sample offsets, or media data.
  const payload = Buffer.from(label);
  const freeBox = Buffer.alloc(8 + payload.length);
  freeBox.writeUInt32BE(freeBox.length);
  freeBox.write("free", 4, "ascii");
  payload.copy(freeBox, 8);
  const body = Buffer.concat([videoBody, freeBox]);
  const inspection = inspectMp4Buffer(body);
  assert.equal(inspection.hasVideo, true);
  assert.equal(inspection.mediaDataComplete, true);
  return body;
}

test("one failed Story preserves successful files and does not stop later Stories", async () => {
  const root = await newCase("partial-failure");
  const destination = path.join(root, "alice");
  const first = videoItem("2001");
  const broken = videoItem("2002");
  const later = videoItem("2003");
  const laterBody = distinctVideoBody("later-story");
  const context = fakeBrowserContext(new Map([
    [first.sourceUrl, { body: videoBody, contentType: "video/mp4" }],
    [broken.sourceUrl, new Error("403 Forbidden: Story media unavailable")],
    [later.sourceUrl, { body: laterBody, contentType: "video/mp4" }],
  ]));

  const result = await persistStoryItems([first, broken, later], destination, "alice", context, "video_only");

  assert.equal(result.items.length, 2, result.logs.join("\n"));
  assert.deepEqual(context.calls, [first.sourceUrl, broken.sourceUrl, later.sourceUrl]);
  assert.deepEqual(await fs.readFile(result.items[0].localPath), videoBody);
  assert.deepEqual(await fs.readFile(result.items[1].localPath), laterBody);
  assert.ok(result.logs.some((entry) => entry.startsWith("story_item_failed=2002:")), result.logs.join("\n"));
  const manifestNames = await fs.readdir(manifestsDirectory);
  const savedStoryIds = await Promise.all(manifestNames.map(async (name) => JSON.parse(await fs.readFile(path.join(manifestsDirectory, name), "utf8")).storyId));
  assert.deepEqual(savedStoryIds.sort(), ["2001", "2003"]);
});

test("a failed manifest write preserves its published video and reserves a new filename for later Stories", async (t) => {
  const root = await newCase("manifest-failure");
  const destination = path.join(root, "alice");
  const first = videoItem("3001");
  const later = videoItem("3002");
  const laterBody = distinctVideoBody("after-manifest-failure");
  const context = fakeBrowserContext(new Map([
    [first.sourceUrl, { body: videoBody, contentType: "video/mp4" }],
    [later.sourceUrl, { body: laterBody, contentType: "video/mp4" }],
  ]));
  const originalWriteFile = fs.writeFile;
  let manifestWriteFailed = false;
  t.mock.method(fs, "writeFile", async (...args) => {
    const filename = String(args[0]);
    if (!manifestWriteFailed && path.dirname(filename) === manifestsDirectory && filename.endsWith(".json")) {
      manifestWriteFailed = true;
      throw new Error("EACCES: manifest directory temporarily unavailable");
    }
    return await originalWriteFile(...args);
  });

  const result = await persistStoryItems([first, later], destination, "alice", context, "video_only");

  assert.equal(manifestWriteFailed, true, "The fault must occur after the first video has been published");
  assert.equal(result.items.length, 1, result.logs.join("\n"));
  assert.deepEqual(context.calls, [first.sourceUrl, later.sourceUrl]);
  const firstPublishedPath = path.join(destination, "alice-001.mp4");
  assert.deepEqual(await fs.readFile(firstPublishedPath), videoBody, "The earlier video must survive its manifest error");
  assert.notEqual(result.items[0].localPath, firstPublishedPath, "Later media must not reuse the published video's filename");
  assert.deepEqual(await fs.readFile(result.items[0].localPath), laterBody);
  assert.ok(result.logs.some((entry) => entry.startsWith("story_item_failed=3001:")), result.logs.join("\n"));
  const manifestNames = await fs.readdir(manifestsDirectory);
  assert.equal(manifestNames.length, 1);
  const manifest = JSON.parse(await fs.readFile(path.join(manifestsDirectory, manifestNames[0]), "utf8"));
  assert.equal(manifest.storyId, "3002");
  assert.equal(manifest.localPath, result.items[0].localPath);
});
