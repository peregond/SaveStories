import test from "node:test";
import assert from "node:assert/strict";

import {
  chooseDashAudioUrl,
  decodeXmlEntities,
  expectedAudioState,
  isTrustedInstagramMediaUrl,
  mergeResolvedMediaCandidate,
  storyIdFromUrl,
} from "./dash_media.mjs";

test("expectedAudioState preserves declared false and leaves missing metadata unknown", () => {
  assert.equal(expectedAudioState(true), true);
  assert.equal(expectedAudioState(1), true);
  assert.equal(expectedAudioState(false), false);
  assert.equal(expectedAudioState(0), false);
  assert.equal(expectedAudioState(undefined), null);
  assert.equal(expectedAudioState(false, "https://video.example/audio.mp4"), true);
});

test("mergeResolvedMediaCandidate keeps the richer duplicate audio metadata", () => {
  const partial = { itemId: "1", sourceUrl: "video-a", audioSourceUrl: null, expectsAudio: null };
  const rich = { itemId: "1", sourceUrl: "video-b", audioSourceUrl: "audio", expectsAudio: true };
  assert.deepEqual(mergeResolvedMediaCandidate(partial, rich), rich);
  assert.deepEqual(mergeResolvedMediaCandidate(rich, partial), rich);
  assert.equal(
    mergeResolvedMediaCandidate({ ...partial, expectsAudio: false }, partial).expectsAudio,
    false,
  );
});

test("decodeXmlEntities decodes named and numeric entities", () => {
  assert.equal(
    decodeXmlEntities("https://video.example/audio.mp4?a=1&amp;b=2&#38;c=3&#x26;d=4&quot;ok&quot;"),
    'https://video.example/audio.mp4?a=1&b=2&c=3&d=4"ok"',
  );
});

test("chooseDashAudioUrl prefers the highest-bandwidth AAC audio/mp4 representation", () => {
  const manifest = `
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011">
      <Period>
        <AdaptationSet contentType="video" mimeType="video/mp4" codecs="avc1.640028">
          <Representation bandwidth="5000000">
            <BaseURL>https://video.example/video.mp4?x=1&amp;y=2</BaseURL>
          </Representation>
        </AdaptationSet>
        <AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2">
          <Representation bandwidth="64000">
            <BaseURL>https://video.example/audio-low.mp4?x=1&amp;y=2</BaseURL>
          </Representation>
          <Representation bandwidth="128000">
            <BaseURL>https://video.example/audio-high.mp4?x=1&amp;y=2</BaseURL>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>`;

  assert.equal(
    chooseDashAudioUrl(manifest),
    "https://video.example/audio-high.mp4?x=1&y=2",
  );
});

test("chooseDashAudioUrl uses representation attributes and prefers AAC over non-AAC", () => {
  const manifest = `
    <mpd:MPD>
      <mpd:Period>
        <mpd:AdaptationSet contentType='audio'>
          <mpd:Representation mimeType='audio/webm' codecs='opus' bandwidth='256000'>
            <mpd:BaseURL>https://video.example/audio-opus.webm</mpd:BaseURL>
          </mpd:Representation>
          <mpd:Representation mimeType='audio/mp4' codecs='mp4a.40.5' bandwidth='96000'>
            <mpd:BaseURL><![CDATA[https://video.example/audio-aac.mp4?x=1&y=2]]></mpd:BaseURL>
          </mpd:Representation>
        </mpd:AdaptationSet>
      </mpd:Period>
    </mpd:MPD>`;

  assert.equal(
    chooseDashAudioUrl(manifest),
    "https://video.example/audio-aac.mp4?x=1&y=2",
  );
});

test("chooseDashAudioUrl supports an audio AdaptationSet with a direct BaseURL", () => {
  const manifest = `
    <MPD><Period>
      <AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2" bandwidth="128000">
        <BaseURL>https://video.example/direct-audio.mp4</BaseURL>
      </AdaptationSet>
    </Period></MPD>`;

  assert.equal(chooseDashAudioUrl(manifest), "https://video.example/direct-audio.mp4");
});

test("chooseDashAudioUrl falls back to an inherited AdaptationSet BaseURL", () => {
  const manifest = `
    <MPD><Period>
      <AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2">
        <BaseURL>https://video.example/inherited-audio.mp4</BaseURL>
        <Representation bandwidth="128000"><SegmentBase indexRange="0-100" /></Representation>
      </AdaptationSet>
    </Period></MPD>`;

  assert.equal(chooseDashAudioUrl(manifest), "https://video.example/inherited-audio.mp4");
});

test("chooseDashAudioUrl ignores video-only and malformed manifests", () => {
  const videoOnly = `
    <MPD><Period><AdaptationSet contentType="video" mimeType="video/mp4" codecs="avc1.4d401f">
      <Representation bandwidth="1000000"><BaseURL>https://video.example/video.mp4</BaseURL></Representation>
      <Representation mimeType="video/mp4" codecs="mp4a.40.2" bandwidth="9000000">
        <BaseURL>https://video.example/mislabeled-video.mp4</BaseURL>
      </Representation>
    </AdaptationSet></Period></MPD>`;

  assert.equal(chooseDashAudioUrl(videoOnly), null);
  assert.equal(chooseDashAudioUrl(""), null);
  assert.equal(chooseDashAudioUrl(null), null);
});

test("storyIdFromUrl extracts an active story id", () => {
  assert.equal(
    storyIdFromUrl("https://www.instagram.com/stories/alice/3731234567890123456/?source=profile"),
    "3731234567890123456",
  );
  assert.equal(storyIdFromUrl("/stories/bob/1234567890/"), "1234567890");
});

test("storyIdFromUrl rejects profile, highlight, and malformed story URLs", () => {
  assert.equal(storyIdFromUrl("https://www.instagram.com/alice/"), null);
  assert.equal(storyIdFromUrl("https://www.instagram.com/stories/highlights/1234567890/"), null);
  assert.equal(storyIdFromUrl("https://www.instagram.com/stories/alice/not-a-number/"), null);
  assert.equal(storyIdFromUrl(""), null);
});

test("isTrustedInstagramMediaUrl allows HTTPS Instagram CDNs only", () => {
  assert.equal(isTrustedInstagramMediaUrl("https://scontent-fra5-2.cdninstagram.com/audio.mp4"), true);
  assert.equal(isTrustedInstagramMediaUrl("https://scontent.xx.fbcdn.net/audio.mp4"), true);
  assert.equal(isTrustedInstagramMediaUrl("https://i.instagram.com/api/media"), true);
  assert.equal(isTrustedInstagramMediaUrl("http://scontent.xx.fbcdn.net/audio.mp4"), false);
  assert.equal(isTrustedInstagramMediaUrl("https://video.evil.example/audio.mp4"), false);
  assert.equal(isTrustedInstagramMediaUrl("not-a-url"), false);
});
