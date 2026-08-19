import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { inspectMp4, inspectMp4Buffer, muxMp4Tracks } from "./mp4_muxer.mjs";
import * as MP4Box from "./vendor/mp4box/mp4box.all.mjs";

const FIXTURES = path.join(import.meta.dirname, "test_fixtures", "audio");
const VIDEO_ONLY = path.join(FIXTURES, "video-only.mp4");
const AUDIO_ONLY = path.join(FIXTURES, "audio-only.m4a");
const EMBEDDED_AUDIO = path.join(FIXTURES, "embedded-audio.mp4");

async function temporaryDirectory(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-mp4-muxer-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  return directory;
}

async function createOffsetAudioFixture(outputPath, delayMilliseconds = 200) {
  const bytes = await fs.readFile(AUDIO_ONLY);
  const input = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  input.fileStart = 0;
  const source = MP4Box.createFile(true);
  let sourceInfo = null;
  source.onReady = (value) => { sourceInfo = value; };
  source.appendBuffer(input, true);
  source.flush();

  const audioInfo = sourceInfo.audioTracks[0];
  const sourceTrak = source.getTrackById(audioInfo.id);
  const entry = sourceTrak.mdia.minf.stbl.stsd.entries[0];
  const samples = source.getTrackSamplesInfo(audioInfo.id);
  const movieTimescale = 1000;
  const sourcePresentationDuration = sourceTrak.edts.elst.entries.reduce(
    (total, edit) => total + edit.segment_duration,
    0,
  );
  const outputDuration = delayMilliseconds + sourcePresentationDuration;

  const output = MP4Box.createFile();
  output.init({ brands: ["isom", "iso6", "mp41"], timescale: movieTimescale, duration: outputDuration });
  const outputId = output.addTrack({
    id: 1,
    type: entry.type,
    description_boxes: entry.boxes,
    duration: outputDuration,
    media_duration: samples.reduce((total, sample) => total + sample.duration, 0),
    timescale: audioInfo.timescale,
    language: "und",
    hdlr: "soun",
    channel_count: entry.channel_count,
    samplesize: entry.samplesize,
    samplerate: entry.samplerate,
  });
  const outputTrak = output.getTrackById(outputId);
  outputTrak.tkhd.duration = outputDuration;
  const edts = new MP4Box.BoxParser.box.edts();
  const elst = edts.addBox(new MP4Box.BoxParser.box.elst());
  elst.version = 0;
  elst.flags = 0;
  elst.entries = [
    { segment_duration: delayMilliseconds, media_time: -1, media_rate_integer: 1, media_rate_fraction: 0 },
    { ...sourceTrak.edts.elst.entries[0] },
  ];
  outputTrak.addBox(edts);
  const editIndex = outputTrak.boxes.indexOf(edts);
  outputTrak.boxes.splice(editIndex, 1);
  outputTrak.boxes.splice(1, 0, edts);

  const firstDts = samples[0].dts;
  for (let index = 0; index < samples.length; index += 1) {
    const sample = source.getTrackSample(audioInfo.id, index);
    output.addSample(outputId, sample.data, {
      duration: sample.duration,
      dts: sample.dts - firstDts,
      cts: sample.cts - firstDts,
      is_sync: sample.is_sync,
    });
  }
  await fs.writeFile(outputPath, Buffer.from(output.getBuffer().buffer));
}

test("inspectMp4 detects actual tracks instead of relying on URL metadata", async () => {
  const videoOnly = await inspectMp4(VIDEO_ONLY);
  const embedded = inspectMp4Buffer(await fs.readFile(EMBEDDED_AUDIO));
  assert.equal(videoOnly.hasVideo, true);
  assert.equal(videoOnly.hasAudio, false);
  assert.equal(embedded.hasVideo, true);
  assert.equal(embedded.hasAudio, true);
  assert.equal(embedded.mediaDataComplete, true);
  assert.match(embedded.videoTracks[0].codec, /^avc1\./);
  assert.match(embedded.audioTracks[0].codec, /^mp4a\./);
});

test("inspectMp4 detects a fast-start MP4 whose media payload is truncated", async () => {
  const complete = await fs.readFile(EMBEDDED_AUDIO);
  const truncated = complete.subarray(0, 2869);
  const inspected = inspectMp4Buffer(truncated);

  assert.equal(inspected.hasVideo, true, "the complete moov still declares video");
  assert.equal(inspected.hasAudio, true, "the complete moov still declares audio");
  assert.equal(inspected.mediaDataComplete, false, "missing mdat bytes must be detected");
  assert.ok(inspected.videoTracks.some(track => !track.sampleDataComplete));
  assert.ok(inspected.audioTracks.some(track => !track.sampleDataComplete));
});

test("muxMp4Tracks copies H.264 and AAC tracks and trims audio to the video duration", async (t) => {
  const directory = await temporaryDirectory(t);
  const outputPath = path.join(directory, "muxed.mp4");
  const result = await muxMp4Tracks({
    videoPath: VIDEO_ONLY,
    audioPath: AUDIO_ONLY,
    outputPath,
  });
  const inspected = await inspectMp4(outputPath);
  assert.equal(result.muxed, true);
  assert.equal(inspected.hasVideo, true);
  assert.equal(inspected.hasAudio, true);
  assert.match(result.video.codec, /^avc1\./);
  assert.match(result.audio.codec, /^mp4a\./);
  assert.ok(inspected.audioTracks[0].durationSeconds <= inspected.videoTracks[0].durationSeconds + 0.001);
  assert.ok(
    inspected.audioTracks[0].startTimeSeconds
      + inspected.audioTracks[0].sampleEndSeconds
      - inspected.audioTracks[0].mediaStartTimeSeconds
      <= inspected.videoTracks[0].durationSeconds
        + inspected.audioTracks[0].maximumSampleDurationSeconds
        + 0.001,
    "demuxed audio packets must end no later than one complete AAC frame after video",
  );
});

test("muxMp4Tracks preserves a delayed audio presentation timeline", async (t) => {
  const directory = await temporaryDirectory(t);
  const audioPath = path.join(directory, "offset-audio.m4a");
  const outputPath = path.join(directory, "offset-output.mp4");
  await createOffsetAudioFixture(audioPath);

  const sourceAudio = await inspectMp4(audioPath);
  assert.equal(sourceAudio.audioTracks[0].startTimeSeconds, 0.2);
  await muxMp4Tracks({ videoPath: VIDEO_ONLY, audioPath, outputPath });
  const output = await inspectMp4(outputPath);
  assert.equal(output.audioTracks[0].startTimeSeconds, 0.2);
  assert.ok(output.audioTracks[0].durationSeconds <= output.videoTracks[0].durationSeconds + 0.001);
  const actualAudioEnd = output.audioTracks[0].startTimeSeconds
    + output.audioTracks[0].sampleEndSeconds
    - output.audioTracks[0].mediaStartTimeSeconds;
  const allowedAudioEnd = output.videoTracks[0].durationSeconds
    + output.audioTracks[0].maximumSampleDurationSeconds
    + 0.001;
  assert.ok(
    actualAudioEnd <= allowedAudioEnd,
    `a delayed sidecar ends at ${actualAudioEnd}s, beyond the ${allowedAudioEnd}s frame boundary`,
  );
});

test("muxMp4Tracks rejects a sidecar whose audio begins after the video ends", async (t) => {
  const directory = await temporaryDirectory(t);
  const audioPath = path.join(directory, "audio-after-video.m4a");
  const outputPath = path.join(directory, "must-not-exist.mp4");
  await createOffsetAudioFixture(audioPath, 500);

  await assert.rejects(
    muxMp4Tracks({ videoPath: VIDEO_ONLY, audioPath, outputPath }),
    error => error?.code === "invalid-audio-duration",
  );
  await assert.rejects(fs.access(outputPath), { code: "ENOENT" });
});

test("muxMp4Tracks skips duplicate mux when the downloaded video already has audio", async (t) => {
  const directory = await temporaryDirectory(t);
  const outputPath = path.join(directory, "must-not-exist.mp4");
  const result = await muxMp4Tracks({
    videoPath: EMBEDDED_AUDIO,
    audioPath: path.join(directory, "sidecar-was-not-downloaded.m4a"),
    outputPath,
  });
  assert.equal(result.muxed, false);
  assert.equal(result.reason, "video-already-has-audio");
  await assert.rejects(fs.access(outputPath), { code: "ENOENT" });
});

test("muxMp4Tracks fails without an AAC sidecar and leaves no muted output", async (t) => {
  const directory = await temporaryDirectory(t);
  const outputPath = path.join(directory, "must-not-exist.mp4");
  await assert.rejects(
    muxMp4Tracks({ videoPath: VIDEO_ONLY, audioPath: VIDEO_ONLY, outputPath }),
    error => error?.code === "missing-audio",
  );
  await assert.rejects(fs.access(outputPath), { code: "ENOENT" });
});

test("muxMp4Tracks never overwrites an existing output", async (t) => {
  const directory = await temporaryDirectory(t);
  const outputPath = path.join(directory, "existing.mp4");
  await fs.writeFile(outputPath, "sentinel");
  await assert.rejects(
    muxMp4Tracks({ videoPath: VIDEO_ONLY, audioPath: AUDIO_ONLY, outputPath }),
    error => error?.code === "output-exists",
  );
  assert.equal(await fs.readFile(outputPath, "utf8"), "sentinel");
});
