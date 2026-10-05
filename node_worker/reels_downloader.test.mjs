import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  downloadReelsCommand,
  extractReelShortcode,
  normalizeReelUrl,
  splitReelInputs,
  resolveReelItemFromDict,
  resolveReelItemsFromPayloads,
  resolveReelItemsFromScriptTexts,
} from "./reels_downloader.mjs";

test("splitReelInputs supports commas and new lines", () => {
  assert.deepEqual(
    splitReelInputs([
      "https://www.instagram.com/reel/AAA111/, https://www.instagram.com/reel/BBB222/\nhttps://www.instagram.com/p/CCC333/",
    ]),
    [
      "https://www.instagram.com/reel/AAA111/",
      "https://www.instagram.com/reel/BBB222/",
      "https://www.instagram.com/p/CCC333/",
    ],
  );
});

test("normalizeReelUrl strips hashes and normalizes known instagram media paths", () => {
  assert.equal(
    normalizeReelUrl("https://www.instagram.com/reel/DMabc123/?utm_source=ig_web_copy_link#fragment"),
    "https://www.instagram.com/reel/DMabc123/?utm_source=ig_web_copy_link",
  );
  assert.equal(
    normalizeReelUrl("https://www.instagram.com/p/XYZ999"),
    "https://www.instagram.com/p/XYZ999/",
  );
});

test("extractReelShortcode supports reel and post urls", () => {
  assert.equal(extractReelShortcode("https://www.instagram.com/reel/DMabc123/"), "DMabc123");
  assert.equal(extractReelShortcode("https://www.instagram.com/p/CODE456/"), "CODE456");
  assert.equal(extractReelShortcode("https://www.instagram.com/alice/"), "");
});


const videoUrl = 'https://scontent.cdninstagram.com/reel.mp4';
const imageUrl = 'https://scontent.cdninstagram.com/preview.jpg';
const reel = {
  id: '123_456', code: 'TARGET', user: { username: 'alice' }, media_type: 2,
  video_versions: [{ url: videoUrl, width: 720, height: 1280 }], has_audio: false,
};

test('unidentified images and videos cannot inherit the requested Reel shortcode', () => {
  const anonymousImage = { id: 'preview', image_versions2: { candidates: [{ url: imageUrl }] } };
  const anonymousVideo = { ...reel, code: undefined };
  assert.equal(resolveReelItemFromDict(anonymousImage, 'TARGET'), null);
  assert.equal(resolveReelItemFromDict(anonymousVideo, 'TARGET'), null);
  assert.equal(resolveReelItemFromDict({ ...reel, code: 'OTHER' }, 'TARGET'), null);
  const items = resolveReelItemsFromPayloads([{ payload: { preview: anonymousImage, recommendations: [{ ...reel, code: 'OTHER' }], target: reel } }], 'TARGET');
  assert.equal(items.length, 1);
  assert.equal(items[0].sourceUrl, videoUrl);
});

test('preloaded Relay JSON resolves the target video and author without network metadata', () => {
  const scripts = [
    'invalid json',
    JSON.stringify({ require: [['ScheduledServerJS', 'handle', null, [{ data: { media: reel } }]]] }),
    JSON.stringify({ recommendations: [{ ...reel, code: 'OTHER' }] }),
  ];
  const items = resolveReelItemsFromScriptTexts(scripts, 'TARGET');
  assert.equal(items.length, 1);
  assert.equal(items[0].shortcode, 'TARGET');
  assert.equal(items[0].username, 'alice');
  assert.equal(items[0].mediaType, 'video');
});

test('GraphQL video_url is accepted and incomplete video metadata cannot become a thumbnail', () => {
  const graph = resolveReelItemFromDict({ shortcode: 'TARGET', is_video: true, video_url: videoUrl, owner: { username: 'alice' } }, 'TARGET');
  assert.equal(graph.mediaType, 'video');
  assert.equal(graph.sourceUrl, videoUrl);
  assert.equal(resolveReelItemFromDict({ code: 'TARGET', media_type: 2, image_versions2: { candidates: [{ url: imageUrl }] } }, 'TARGET'), null);
});

test('thumbnail metadata cannot replace the matching video with the same id', () => {
  const thumbnail = { id: reel.id, code: reel.code, image_versions2: { candidates: [{ url: imageUrl }] } };
  for (const entries of [[reel, thumbnail], [thumbnail, reel]]) {
    const [result] = resolveReelItemsFromPayloads([{ payload: entries }], 'TARGET');
    assert.equal(result.mediaType, 'video');
    assert.equal(result.sourceUrl, videoUrl);
  }
});

async function commandHarness(t, metadata = reel, body = null) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'saveme-reels-test-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const videoBody = body ?? await fs.readFile(new URL('./test_fixtures/audio/video-only.mp4', import.meta.url));
  const calls = [];
  const context = {
    request: { async get(url) { calls.push(url); return { body: async () => videoBody, headers: () => ({ 'content-type': 'video/mp4' }) }; } },
    async newPage() {
      let url;
      return {
        goto: async (value) => { url = value; }, url: () => url,
        context: () => context, close: async () => {}, waitForTimeout: async () => {},
        evaluate: async () => [JSON.stringify({ data: { media: metadata } })],
      };
    },
  };
  return {
    root, calls,
    deps: {
      defaultDownloads: path.join(root, 'downloads'), manifestsDirectory: path.join(root, 'manifests'),
      launchContext: async () => ({ context, close: async () => {} }),
      prepareBackgroundWindow: async () => {}, installJsonCapture: () => [],
      ensureLoggedIn: async () => {}, persistSessionState: async () => {},
    },
  };
}

const targetUrl = 'https://www.instagram.com/reel/TARGET/';

test('command downloads preloaded video into the author folder and detects a real repeat', async (t) => {
  const { root, calls, deps } = await commandHarness(t);
  const result = await downloadReelsCommand([targetUrl], null, true, deps);
  assert.equal(result.status, 'download_complete', result.logs.join('\n'));
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].localPath, path.join(root, 'downloads', 'alice', 'alice-reels-001.mp4'));
  assert.deepEqual(await fs.readFile(result.items[0].localPath), await fs.readFile(new URL('./test_fixtures/audio/video-only.mp4', import.meta.url)));
  const again = await downloadReelsCommand([targetUrl], null, true, deps);
  assert.equal(again.status, 'download_duplicate');
  assert.equal(calls.length, 1);
});

test('missing files and a new destination are downloaded instead of skipped by old manifests', async (t) => {
  const { root, deps } = await commandHarness(t);
  const first = await downloadReelsCommand([targetUrl], null, true, deps);
  await fs.rm(first.items[0].localPath);
  const restored = await downloadReelsCommand([targetUrl], null, true, deps);
  assert.equal(restored.status, 'download_complete');
  const elsewhere = await downloadReelsCommand([targetUrl], path.join(root, 'elsewhere'), true, deps);
  assert.equal(elsewhere.status, 'download_complete');
  assert.equal(elsewhere.items[0].localPath, path.join(root, 'elsewhere', 'alice', 'alice-reels-001.mp4'));
  const originalDestination = await downloadReelsCommand([targetUrl], null, true, deps);
  assert.equal(originalDestination.status, 'download_duplicate');
});

test('different authors with identical bytes each receive their own file', async (t) => {
  const { deps } = await commandHarness(t);
  await downloadReelsCommand([targetUrl], null, true, deps);
  const originalLaunch = deps.launchContext;
  deps.launchContext = async () => {
    const session = await originalLaunch();
    const originalNewPage = session.context.newPage;
    session.context.newPage = async () => {
      const page = await originalNewPage();
      page.evaluate = async () => [JSON.stringify({ media: { ...reel, user: { username: 'bob' } } })];
      return page;
    };
    return session;
  };
  const bob = await downloadReelsCommand([targetUrl], null, true, deps);
  assert.equal(bob.status, 'download_complete');
  assert.equal(path.basename(path.dirname(bob.items[0].localPath)), 'bob');
});

test('failed video validation leaves no empty author folder', async (t) => {
  const { root, deps } = await commandHarness(t, reel, Buffer.alloc(100));
  const result = await downloadReelsCommand([targetUrl], null, true, deps);
  assert.equal(result.ok, false);
  assert.equal(result.data.failedCount, '1');
  await assert.rejects(fs.stat(path.join(root, 'downloads', 'alice')), { code: 'ENOENT' });
});
