import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import * as MP4Box from "./vendor/mp4box/mp4box.all.mjs";

const VIDEO_SAMPLE_ENTRIES = new Set(["avc1", "avc2", "avc3", "avc4", "hvc1", "hvc2", "hev1", "hev2"]);
const AUDIO_SAMPLE_ENTRIES = new Set(["mp4a"]);

class Mp4MuxError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "Mp4MuxError";
    this.code = code;
  }
}

function asArrayBuffer(data) {
  if (data instanceof ArrayBuffer) return data;
  if (!ArrayBuffer.isView(data)) {
    throw new TypeError("MP4 input must be an ArrayBuffer or Uint8Array");
  }
  if (data.byteOffset === 0 && data.byteLength === data.buffer.byteLength) {
    return data.buffer;
  }
  return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
}

function parseMp4(data, keepMediaData = false) {
  const input = asArrayBuffer(data);
  input.fileStart = 0;
  const file = MP4Box.createFile(keepMediaData);
  let info = null;
  let parseError = null;
  file.onReady = (value) => { info = value; };
  file.onError = (...parts) => {
    parseError = new Mp4MuxError("invalid-mp4", parts.filter(Boolean).join(": ") || "Invalid MP4 file");
  };
  file.appendBuffer(input, true);
  file.flush();
  if (parseError) throw parseError;
  if (!info?.hasMoov) {
    throw new Mp4MuxError("invalid-mp4", "The input does not contain a complete MP4 movie box");
  }
  return { file, info, inputByteLength: input.byteLength };
}

function trackDurationSeconds(track) {
  const candidates = [
    track.movie_duration / track.movie_timescale,
    track.duration / track.timescale,
    track.samples_duration / track.timescale,
  ].filter(value => Number.isFinite(value) && value > 0);
  return candidates.length > 0 ? Math.min(...candidates) : 0;
}

function trackPresentationDurationSeconds(track, trak) {
  const editDuration = trak?.edts?.elst?.entries?.reduce(
    (total, entry) => total + Number(entry.segment_duration || 0),
    0,
  );
  if (Number.isFinite(editDuration) && editDuration > 0 && track.movie_timescale > 0) {
    return editDuration / track.movie_timescale;
  }
  const movieDuration = track.movie_duration / track.movie_timescale;
  return Number.isFinite(movieDuration) && movieDuration > 0
    ? movieDuration
    : trackDurationSeconds(track);
}

function trackPresentationStartSeconds(track, trak) {
  const entries = trak?.edts?.elst?.entries || [];
  let leadingEmptyDuration = 0;
  for (const entry of entries) {
    if (entry.media_time !== -1) break;
    leadingEmptyDuration += Number(entry.segment_duration || 0);
  }
  return track.movie_timescale > 0 ? leadingEmptyDuration / track.movie_timescale : 0;
}

function trackPresentationMediaStartSeconds(track, trak) {
  const firstMediaEdit = (trak?.edts?.elst?.entries || []).find(entry => entry.media_time >= 0);
  return track.timescale > 0 && firstMediaEdit
    ? firstMediaEdit.media_time / track.timescale
    : 0;
}

function trackSampleStatus(parsed, track) {
  const declaredSampleCount = Number.isInteger(track.nb_samples) ? track.nb_samples : 0;
  const sampleInfo = parsed.file.getTrackSamplesInfo(track.id) || [];
  let readableSampleCount = 0;

  if (declaredSampleCount <= 0 || sampleInfo.length !== declaredSampleCount) {
    return { readableSampleCount, sampleDataComplete: false };
  }

  for (let index = 0; index < sampleInfo.length; index += 1) {
    const sample = sampleInfo[index];
    const offset = Number(sample?.offset);
    const size = Number(sample?.size);
    const end = offset + size;
    if (
      !sample
      || !Number.isSafeInteger(offset)
      || offset < 0
      || !Number.isSafeInteger(size)
      || size <= 0
      || !Number.isSafeInteger(end)
      || end > parsed.inputByteLength
    ) {
      return { readableSampleCount, sampleDataComplete: false };
    }
    readableSampleCount += 1;
  }

  return { readableSampleCount, sampleDataComplete: true };
}

function trackSummary(parsed, track) {
  const trak = parsed.file.getTrackById(track.id);
  const samples = parsed.file.getTrackSamplesInfo(track.id) || [];
  const firstDts = samples[0]?.dts || 0;
  const maximumSampleEnd = samples.reduce(
    (maximum, sample) => Math.max(maximum, sample.dts + sample.duration - firstDts),
    0,
  );
  const maximumSampleDuration = samples.reduce(
    (maximum, sample) => Math.max(maximum, sample.duration),
    0,
  );
  return {
    id: track.id,
    codec: track.codec,
    durationSeconds: trackPresentationDurationSeconds(track, trak),
    startTimeSeconds: trackPresentationStartSeconds(track, trak),
    mediaStartTimeSeconds: trackPresentationMediaStartSeconds(track, trak),
    sampleEndSeconds: track.timescale > 0 ? maximumSampleEnd / track.timescale : 0,
    maximumSampleDurationSeconds: track.timescale > 0 ? maximumSampleDuration / track.timescale : 0,
    sampleCount: track.nb_samples,
    timescale: track.timescale,
    ...trackSampleStatus(parsed, track),
  };
}

function summarize(parsed) {
  const { info } = parsed;
  const allTracks = [...info.videoTracks, ...info.audioTracks];
  const videoTracks = info.videoTracks.map(track => trackSummary(parsed, track));
  const audioTracks = info.audioTracks.map(track => trackSummary(parsed, track));
  const declaredDuration = info.duration / info.timescale;
  return {
    hasVideo: info.videoTracks.length > 0,
    hasAudio: info.audioTracks.length > 0,
    mediaDataComplete: allTracks.length > 0
      && [...videoTracks, ...audioTracks].every(track => track.sampleDataComplete),
    isFragmented: info.isFragmented,
    durationSeconds: declaredDuration > 0
      ? declaredDuration
      : Math.max(0, ...allTracks.map(trackDurationSeconds)),
    brands: [...info.brands],
    videoTracks,
    audioTracks,
  };
}

function inspectMp4Buffer(data) {
  return summarize(parseMp4(data, false));
}

async function inspectMp4(filePath) {
  return inspectMp4Buffer(await fs.readFile(filePath));
}

function selectedTrack(parsed, kind) {
  const info = kind === "video" ? parsed.info.videoTracks[0] : parsed.info.audioTracks[0];
  if (!info) {
    throw new Mp4MuxError(`missing-${kind}`, `The input does not contain a ${kind} track`);
  }
  const trak = parsed.file.getTrackById(info.id);
  if (!trak) {
    throw new Mp4MuxError(`missing-${kind}`, `Could not read ${kind} track #${info.id}`);
  }
  const entry = trak.mdia.minf.stbl.stsd.entries[0];
  const supportedEntries = kind === "video" ? VIDEO_SAMPLE_ENTRIES : AUDIO_SAMPLE_ENTRIES;
  if (!entry || !supportedEntries.has(entry.type)) {
    throw new Mp4MuxError(
      `unsupported-${kind}-codec`,
      `Unsupported ${kind} sample entry: ${entry?.type || info.codec || "unknown"}`,
    );
  }
  if (trak.samples.some(sample => sample.description_index !== 0)) {
    throw new Mp4MuxError("multiple-sample-descriptions", "Tracks with changing sample descriptions are not supported");
  }
  return { parsed, info, trak, entry, kind };
}

function timelineDurationSeconds(track) {
  return trackPresentationDurationSeconds(track.info, track.trak);
}

function cloneEditList(
  sourceTrak,
  sourceMovieTimescale,
  outputMovieTimescale,
  maximumDurationSeconds = null,
  firstDts = 0,
) {
  const sourceElst = sourceTrak.edts?.elst;
  if (!sourceElst?.entries?.length) return null;
  const edts = new MP4Box.BoxParser.box.edts();
  const elst = edts.addBox(new MP4Box.BoxParser.box.elst());
  elst.version = sourceElst.version;
  elst.flags = sourceElst.flags;
  let remainingDuration = maximumDurationSeconds == null
    ? Infinity
    : Math.round(maximumDurationSeconds * outputMovieTimescale);
  elst.entries = [];
  for (const entry of sourceElst.entries) {
    if (remainingDuration <= 0) break;
    const scaledDuration = Math.round(
      entry.segment_duration * outputMovieTimescale / sourceMovieTimescale,
    );
    const segmentDuration = Math.min(scaledDuration, remainingDuration);
    if (segmentDuration <= 0) continue;
    elst.entries.push({
      ...entry,
      segment_duration: segmentDuration,
      media_time: entry.media_time < 0 ? entry.media_time : Math.max(0, entry.media_time - firstDts),
    });
    remainingDuration -= segmentDuration;
  }
  if (elst.entries.length === 0) return null;
  return edts;
}

function directEditList(duration) {
  const edts = new MP4Box.BoxParser.box.edts();
  const elst = edts.addBox(new MP4Box.BoxParser.box.elst());
  elst.version = 0;
  elst.flags = 0;
  elst.entries = [{
    segment_duration: duration,
    media_time: 0,
    media_rate_integer: 1,
    media_rate_fraction: 0,
  }];
  return edts;
}

function maximumReferencedMediaEnd(edits, movieTimescale, mediaTimescale) {
  let maximumEnd = 0;
  for (const edit of edits?.elst?.entries || []) {
    if (edit.media_time < 0 || edit.segment_duration <= 0) continue;
    const rate = Number(edit.media_rate_integer ?? 1)
      + Number(edit.media_rate_fraction ?? 0) / 65_536;
    const mediaSpan = Math.ceil(
      edit.segment_duration * mediaTimescale / movieTimescale * (rate > 0 ? rate : 1),
    );
    maximumEnd = Math.max(maximumEnd, edit.media_time + mediaSpan);
  }
  return maximumEnd;
}

function addTrack(output, source, id, outputMovieTimescale, maximumDurationSeconds = null) {
  const { parsed, info, trak, entry, kind } = source;
  const sourceSamples = parsed.file.getTrackSamplesInfo(info.id);
  const firstDts = sourceSamples[0]?.dts || 0;
  const sourceTimelineDuration = timelineDurationSeconds(source);
  const timelineDuration = maximumDurationSeconds == null
    ? sourceTimelineDuration
    : Math.min(sourceTimelineDuration, maximumDurationSeconds);
  const movieDuration = Math.round(timelineDuration * outputMovieTimescale);
  const clonedEdits = cloneEditList(
    trak,
    info.movie_timescale,
    outputMovieTimescale,
    maximumDurationSeconds == null ? null : timelineDuration,
    firstDts,
  );
  const edits = clonedEdits
    || (maximumDurationSeconds == null ? null : directEditList(movieDuration));
  const maximumMediaEnd = maximumDurationSeconds == null
    ? Infinity
    : clonedEdits
      ? maximumReferencedMediaEnd(clonedEdits, outputMovieTimescale, info.timescale)
      : Math.ceil(timelineDuration * info.timescale);
  let sampleCountToWrite = 0;
  while (
    sampleCountToWrite < sourceSamples.length
    && sourceSamples[sampleCountToWrite].dts - firstDts < maximumMediaEnd
  ) {
    sampleCountToWrite += 1;
  }
  const mediaDuration = sourceSamples
    .slice(0, sampleCountToWrite)
    .reduce((total, sample) => total + sample.duration, 0);
  if (!(movieDuration > 0) || !(mediaDuration > 0)) {
    throw new Mp4MuxError(`invalid-${kind}-duration`, `The ${kind} track has no usable duration`);
  }

  const outputId = output.addTrack({
    id,
    type: entry.type,
    description_boxes: entry.boxes,
    duration: movieDuration,
    media_duration: mediaDuration,
    timescale: info.timescale,
    language: trak.mdia.mdhd.languageString || info.language || "und",
    layer: info.layer,
    hdlr: kind === "video" ? "vide" : "soun",
    name: info.name,
    width: entry.width,
    height: entry.height,
    channel_count: entry.channel_count,
    samplesize: entry.samplesize,
    samplerate: entry.samplerate,
  });
  if (!outputId) {
    throw new Mp4MuxError(`unsupported-${kind}-codec`, `Could not create ${entry.type} output track`);
  }

  const outputTrak = output.getTrackById(outputId);
  outputTrak.tkhd.matrix = Int32Array.from(trak.tkhd.matrix);
  outputTrak.tkhd.width = trak.tkhd.width;
  outputTrak.tkhd.height = trak.tkhd.height;
  outputTrak.tkhd.volume = trak.tkhd.volume;
  outputTrak.tkhd.alternate_group = trak.tkhd.alternate_group;
  outputTrak.tkhd.duration = movieDuration;

  if (edits) {
    outputTrak.addBox(edits);
    const appendedIndex = outputTrak.boxes.indexOf(edits);
    outputTrak.boxes.splice(appendedIndex, 1);
    outputTrak.boxes.splice(1, 0, edits);
  }

  let samplesWritten = 0;
  let writtenDuration = 0;
  for (let index = 0; index < sampleCountToWrite; index += 1) {
    const sample = parsed.file.getTrackSample(info.id, index);
    if (!sample || sample.alreadyRead !== sample.size) {
      throw new Mp4MuxError("incomplete-sample", `Could not read ${kind} sample ${index}`);
    }
    const duration = sample.duration;
    output.addSample(outputId, sample.data, {
      duration,
      dts: sample.dts - firstDts,
      cts: sample.cts - firstDts,
      is_sync: sample.is_sync,
      is_leading: sample.is_leading,
      depends_on: sample.depends_on,
      is_depended_on: sample.is_depended_on,
      has_redundancy: sample.has_redundancy,
      degradation_priority: sample.degradation_priority,
      subsamples: sample.subsamples,
    });
    samplesWritten += 1;
    writtenDuration += duration;
  }
  if (samplesWritten === 0) {
    throw new Mp4MuxError(`missing-${kind}-samples`, `The ${kind} track contains no readable samples`);
  }
  outputTrak.mdia.mdhd.duration = writtenDuration;
  return { codec: info.codec, samplesWritten, timelineDuration };
}

async function muxMp4Tracks({ videoPath, audioPath, outputPath }) {
  if (!videoPath || !audioPath || !outputPath) {
    throw new TypeError("videoPath, audioPath and outputPath are required");
  }
  const resolvedVideoPath = path.resolve(videoPath);
  const resolvedAudioPath = path.resolve(audioPath);
  const resolvedOutputPath = path.resolve(outputPath);
  if (resolvedOutputPath === resolvedVideoPath || resolvedOutputPath === resolvedAudioPath) {
    throw new Mp4MuxError("unsafe-output-path", "The mux output must differ from both input paths");
  }

  const videoBytes = await fs.readFile(resolvedVideoPath);
  const parsedVideo = parseMp4(videoBytes, true);
  const videoInspection = summarize(parsedVideo);
  if (videoInspection.hasAudio) {
    if (!videoInspection.mediaDataComplete) {
      throw new Mp4MuxError("incomplete-sample", "The input contains incomplete video or audio samples");
    }
    return {
      muxed: false,
      reason: "video-already-has-audio",
      outputPath: resolvedVideoPath,
      inspection: videoInspection,
    };
  }

  const video = selectedTrack(parsedVideo, "video");
  const audioBytes = await fs.readFile(resolvedAudioPath);
  const audio = selectedTrack(parseMp4(audioBytes, true), "audio");
  const movieTimescale = video.info.movie_timescale || 1000;
  const videoDuration = timelineDurationSeconds(video);
  const output = MP4Box.createFile();
  output.init({
    brands: ["isom", "iso6", "mp41"],
    timescale: movieTimescale,
    duration: Math.round(videoDuration * movieTimescale),
  });
  const videoResult = addTrack(output, video, 1, movieTimescale);
  const audioResult = addTrack(output, audio, 2, movieTimescale, videoDuration);
  const outputBytes = Buffer.from(output.getBuffer().buffer);
  const outputInspection = inspectMp4Buffer(outputBytes);
  if (!outputInspection.hasVideo || !outputInspection.hasAudio) {
    throw new Mp4MuxError("invalid-output", "Muxed MP4 is missing a video or audio track");
  }

  await fs.mkdir(path.dirname(resolvedOutputPath), { recursive: true });
  try {
    await fs.access(resolvedOutputPath);
    throw new Mp4MuxError("output-exists", `Refusing to replace existing output: ${resolvedOutputPath}`);
  } catch (error) {
    if (error instanceof Mp4MuxError) throw error;
    if (error?.code !== "ENOENT") throw error;
  }

  const temporaryPath = path.join(
    path.dirname(resolvedOutputPath),
    `.${path.basename(resolvedOutputPath)}.${process.pid}.${randomUUID()}.tmp`,
  );
  try {
    await fs.writeFile(temporaryPath, outputBytes, { flag: "wx" });
    await fs.rename(temporaryPath, resolvedOutputPath);
  } finally {
    await fs.rm(temporaryPath, { force: true });
  }

  return {
    muxed: true,
    outputPath: resolvedOutputPath,
    bytes: outputBytes.length,
    durationSeconds: videoDuration,
    video: videoResult,
    audio: audioResult,
    inspection: outputInspection,
  };
}

export {
  Mp4MuxError,
  inspectMp4,
  inspectMp4Buffer,
  muxMp4Tracks,
};
