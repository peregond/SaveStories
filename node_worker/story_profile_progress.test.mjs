import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";

const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-profile-progress-"));
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));
const { buildProfileProgressLines } = await import("./bridge.mjs");

test("profile progress exposes discovery stages and final counts before the whole batch finishes", () => {
  const lines = buildProfileProgressLines({
    username: "alice", status: "download_complete", data: { foundCount: "3", savedCount: "2" },
    logs: [
      "story_profile_id_source=alice:page",
      "story_reels_media_status=alice:403",
      "story_feed_items=alice:1",
      "opened=https://www.instagram.com/stories/alice/",
      "metadata_story_items=1", "metadata_story_items=3",
      "saved=C:/Users/user/Private/alice-001.mp4",
      "skipped_existing_source=https://scontent.cdninstagram.com/video.mp4?signature=PRIVATE_SIGNATURE",
    ],
  }, "https://www.instagram.com/alice/", 2);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^batch_slot_2_profile=alice /);
  for (const field of ["status=download_complete", "found=3", "saved=2", "profile_id=page", "api_playlist=403", "feed_items=1", "viewer=story_without_id", "metadata_items=3", "duplicates=1"]) {
    assert.ok(lines[0].includes(field), `Missing diagnostic field: ${field}`);
  }
  assert.doesNotMatch(lines[0], /https?:|signature|PRIVATE_SIGNATURE|Private|C:\//);
});

test("audio and traversal failures are summarized without forwarding payloads or signed media URLs", () => {
  const [line] = buildProfileProgressLines({
    username: "alice", status: "download_error", data: { foundCount: "1", savedCount: "0" },
    logs: [
      "opened=https://www.instagram.com/stories/alice/?token=PRIVATE_TOKEN",
      "story_profile_info_status=alice:429",
      "story_feed_fallback_error=alice:request failed https://scontent.cdninstagram.com/a.mp4?sig=PRIVATE_SIGNATURE Cookie: PRIVATE_COOKIE",
      "story_item_failed=undefined:Instagram отдал видео без звука, а отдельную аудиодорожку получить не удалось. https://scontent.cdninstagram.com/a.mp4?sig=PRIVATE_SIGNATURE",
      "story_traversal_failed=timeout Authorization: Bearer PRIVATE_AUTHORIZATION",
    ],
  }, "https://www.instagram.com/alice/", 1);
  for (const field of ["status=download_error", "found=1", "saved=0", "viewer=story_without_id", "api_profile=429", "api_fallback_error=true", "item_errors=1", "audio_errors=1", "traversal_errors=1"]) {
    assert.ok(line.includes(field), `Missing diagnostic field: ${field}`);
  }
  assert.doesNotMatch(line, /https?:|PRIVATE_|Cookie|Authorization|Bearer|undefined/);
});

test("numeric viewer identity is reported without publishing its URL or unrelated profile diagnostics", () => {
  const [line] = buildProfileProgressLines({
    status: "download_partial", data: { foundCount: "4", savedCount: "3" },
    logs: [
      "opened=https://www.instagram.com/stories/alice/1234567890/?token=PRIVATE_TOKEN",
      "story_reels_media_items=alice:4",
      "story_feed_status=bob:403",
      "story_feed_items=alice:4\nPRIVATE_INJECTION",
    ],
  }, "https://www.instagram.com/alice/", 3);
  assert.match(line, /viewer=story_with_id/);
  assert.match(line, /playlist_items=4/);
  assert.doesNotMatch(line, /1234567890|bob|api_fallback|feed_items|PRIVATE_|[\r\n]/);
});

test("malformed or absent results produce a bounded single-line summary with a trusted profile name", () => {
  const [line] = buildProfileProgressLines({
    username: "alice\nPRIVATE_USERNAME_PAYLOAD", status: "download_error\nPRIVATE_STATUS_PAYLOAD",
    data: { foundCount: "-1", savedCount: "NaN" },
    logs: [null, { token: "PRIVATE_OBJECT_PAYLOAD" }, "story_feed_status=alice:403\nPRIVATE_LOG_PAYLOAD"],
  }, "https://www.instagram.com/alice/", "1\nPRIVATE_SLOT_PAYLOAD");
  assert.equal(line, "batch_slot_0_profile=alice status=unknown found=0 saved=0");
  assert.deepEqual(buildProfileProgressLines(null, "https://www.instagram.com/alice/", 1), [
    "batch_slot_1_profile=alice status=unknown found=0 saved=0",
  ]);
});
