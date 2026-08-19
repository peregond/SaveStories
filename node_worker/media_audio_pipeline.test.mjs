import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  muxWithFallback,
  publishTemporaryFile,
  saveVideoWithAudio,
} from "./media_audio_pipeline.mjs";
import { inspectMp4 } from "./mp4_muxer.mjs";

const FIXTURES = path.join(import.meta.dirname, "test_fixtures", "audio");
const VIDEO_ONLY = path.join(FIXTURES, "video-only.mp4");
const AUDIO_ONLY = path.join(FIXTURES, "audio-only.m4a");
const EMBEDDED_AUDIO = path.join(FIXTURES, "embedded-audio.mp4");

async function temporaryDirectory(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-audio-pipeline-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  return directory;
}

async function assertOnlyFinalFile(directory, filename) {
  assert.deepEqual(await fs.readdir(directory), [filename]);
}

test("embedded audio is verified and published without fetching or muxing a sidecar", async (t) => {
  const directory = await temporaryDirectory(t);
  const localPath = path.join(directory, "story.mp4");
  const videoBody = await fs.readFile(EMBEDDED_AUDIO);
  let fetchCount = 0;

  const result = await saveVideoWithAudio({
    videoBody,
    localPath,
    audioSourceUrl: "https://video.example/separate-audio.m4a",
    expectsAudio: true,
    fetchAudio: async () => {
      fetchCount += 1;
      throw new Error("embedded audio must bypass sidecar download");
    },
  });

  assert.deepEqual(result, {
    contentLength: videoBody.length,
    audioMuxed: false,
    audioPresent: true,
    muxer: "embedded",
  });
  assert.equal(fetchCount, 0);
  assert.deepEqual(await fs.readFile(localPath), videoBody);
  assert.equal((await inspectMp4(localPath)).hasAudio, true);
  await assertOnlyFinalFile(directory, "story.mp4");
});

test("publish falls back without overwriting when the destination volume rejects hard links", async (t) => {
  const directory = await temporaryDirectory(t);
  const temporaryPath = path.join(directory, "validated.tmp");
  const localPath = path.join(directory, "story.mp4");
  await fs.writeFile(temporaryPath, "validated media");
  const operations = {
    link: async () => {
      const error = new Error("hard links unsupported");
      error.code = "ENOTSUP";
      throw error;
    },
    copyFile: fs.copyFile.bind(fs),
    unlink: fs.unlink.bind(fs),
  };

  await publishTemporaryFile(temporaryPath, localPath, operations);
  assert.equal(await fs.readFile(localPath, "utf8"), "validated media");
  await assert.rejects(fs.access(temporaryPath), { code: "ENOENT" });

  await fs.writeFile(temporaryPath, "replacement");
  await assert.rejects(
    publishTemporaryFile(temporaryPath, localPath, operations),
    /уже существует/,
  );
  assert.equal(await fs.readFile(localPath, "utf8"), "validated media");
});

test("truncated embedded MP4 is rejected without publishing a misleading audio manifest", async (t) => {
  const directory = await temporaryDirectory(t);
  const localPath = path.join(directory, "must-not-exist.mp4");
  const complete = await fs.readFile(EMBEDDED_AUDIO);
  const truncated = complete.subarray(0, 2869);

  await assert.rejects(
    saveVideoWithAudio({
      videoBody: truncated,
      localPath,
      audioSourceUrl: "https://video.example/separate-audio.m4a",
      expectsAudio: true,
      fetchAudio: async () => {
        throw new Error("an incomplete primary video must fail before sidecar download");
      },
    }),
    /неполный/,
  );

  await assert.rejects(fs.access(localPath), { code: "ENOENT" });
  assert.deepEqual(await fs.readdir(directory), []);
});

test("video-only MP4 plus AAC sidecar is muxed by the JavaScript fallback", async (t) => {
  const directory = await temporaryDirectory(t);
  const localPath = path.join(directory, "reel.mp4");
  const videoBody = await fs.readFile(VIDEO_ONLY);
  const audioBody = await fs.readFile(AUDIO_ONLY);
  const progress = [];
  let validated = false;

  const result = await saveVideoWithAudio({
    videoBody,
    localPath,
    audioSourceUrl: "https://video.example/audio.m4a",
    expectsAudio: true,
    fetchAudio: async (url) => {
      assert.equal(url, "https://video.example/audio.m4a");
      return { body: audioBody, contentType: "audio/mp4" };
    },
    validateAudio: (body, contentType) => {
      validated = true;
      assert.deepEqual(body, audioBody);
      assert.equal(contentType, "audio/mp4");
    },
    emitProgress: (message) => progress.push(message),
  });

  const inspection = await inspectMp4(localPath);
  assert.equal(validated, true);
  assert.equal(result.audioMuxed, true);
  assert.equal(result.audioPresent, true);
  assert.equal(result.muxer, "javascript");
  assert.equal(result.contentLength, (await fs.stat(localPath)).size);
  assert.equal(inspection.hasVideo, true);
  assert.equal(inspection.hasAudio, true);
  assert.ok(progress.some((message) => message.startsWith("dash_audio_muxed=reel.mp4:javascript")));
  await assertOnlyFinalFile(directory, "reel.mp4");
});

test("invalid native mux output is removed and recovered by the JavaScript muxer", async (t) => {
  const directory = await temporaryDirectory(t);
  const outputPath = path.join(directory, "recovered.mp4");
  const progress = [];

  const muxer = await muxWithFallback({
    videoPath: VIDEO_ONLY,
    audioPath: AUDIO_ONLY,
    outputPath,
    externalMuxerPath: "/fake/native-muxer",
    emitProgress: (message) => progress.push(message),
    runExternal: async (_executable, videoPath, _audioPath, nativeOutputPath) => {
      await fs.copyFile(videoPath, nativeOutputPath);
    },
  });

  const inspected = await inspectMp4(outputPath);
  assert.equal(muxer, "javascript");
  assert.equal(inspected.hasVideo, true);
  assert.equal(inspected.hasAudio, true);
  assert.equal(inspected.mediaDataComplete, true);
  assert.ok(progress.some(message => message.startsWith("native_audio_muxer_fallback=")));
});

test("expected or unknown audio without a sidecar fails without publishing muted output", async (t) => {
  const videoBody = await fs.readFile(VIDEO_ONLY);

  for (const [label, expectsAudio] of [["expected", true], ["unknown", null]]) {
    await t.test(label, async () => {
      const directory = await fs.mkdtemp(path.join(os.tmpdir(), `saveme-audio-${label}-`));
      t.after(() => fs.rm(directory, { recursive: true, force: true }));
      const localPath = path.join(directory, "must-not-exist.mp4");

      await assert.rejects(
        saveVideoWithAudio({ videoBody, localPath, expectsAudio }),
        /без звука/,
      );
      await assert.rejects(fs.access(localPath), { code: "ENOENT" });
      assert.deepEqual(await fs.readdir(directory), [], "temporary inputs must also be removed");
    });
  }
});

test("explicitly silent video is published only when expectsAudio is false", async (t) => {
  const directory = await temporaryDirectory(t);
  const localPath = path.join(directory, "silent.mp4");
  const videoBody = await fs.readFile(VIDEO_ONLY);

  const result = await saveVideoWithAudio({
    videoBody,
    localPath,
    expectsAudio: false,
  });

  assert.equal(result.audioMuxed, false);
  assert.equal(result.audioPresent, false);
  assert.equal(result.muxer, null);
  assert.deepEqual(await fs.readFile(localPath), videoBody);
  assert.equal((await inspectMp4(localPath)).hasAudio, false);
  await assertOnlyFinalFile(directory, "silent.mp4");
});
