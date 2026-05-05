import test from "node:test";
import assert from "node:assert/strict";

import {
  BatchJobTimeoutError,
  buildWorkerResponse,
  closePageAfterBatchTimeout,
  diagnosticCategory,
  shouldRetryError,
  validateDownloadedMedia,
  withRetry,
  withTimeout,
} from "./worker_utils.mjs";

test("withTimeout rejects with typed timeout error", async () => {
  await assert.rejects(
    () => withTimeout(new Promise(() => {}), 1, "too slow"),
    BatchJobTimeoutError,
  );
});

test("buildWorkerResponse keeps legacy data and adds structured batch fields", () => {
  const response = buildWorkerResponse(true, "batch_complete", "done", {
    data: {
      foundCount: "4",
      savedCount: "2",
      processedCount: "3",
      batchResults: JSON.stringify([
        { url: "alice", status: "completed", message: "ok", foundCount: 2, savedCount: 1 },
      ]),
    },
    items: [],
  });

  assert.equal(response.protocolVersion, 2);
  assert.deepEqual(response.counts, { found: 4, saved: 2, processed: 3, failed: 0 });
  assert.equal(response.batchResults.length, 1);
  assert.equal(response.batchResults[0].url, "alice");
  assert.equal(response.data.savedCount, "2");
  assert.equal(response.diagnostics.category, "ok");
});

test("diagnosticCategory classifies common user-facing failures", () => {
  assert.equal(diagnosticCategory("download_error", "Выгрузка профиля alice превысила лимит ожидания."), "timeout");
  assert.equal(diagnosticCategory("download_error", "Требуется вход в Instagram."), "session_required");
  assert.equal(diagnosticCategory("download_empty", "Не удалось получить active stories."), "media_not_found");
});

test("withRetry retries transient errors", async () => {
  let calls = 0;
  const result = await withRetry(
    async () => {
      calls += 1;
      if (calls < 2) throw new Error("network timeout");
      return "ok";
    },
    { attempts: 2, baseDelayMs: 1 },
  );

  assert.equal(result, "ok");
  assert.equal(calls, 2);
  assert.equal(shouldRetryError(new Error("socket hang up")), true);
  assert.equal(shouldRetryError(new Error("Downloaded media integrity check failed")), true);
});

test("validateDownloadedMedia accepts known media signatures and rejects tiny files", () => {
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(1024)]);
  const mp4 = Buffer.concat([Buffer.from("....ftypisom"), Buffer.alloc(1024)]);

  assert.doesNotThrow(() => validateDownloadedMedia(jpeg, "image", "image/jpeg"));
  assert.doesNotThrow(() => validateDownloadedMedia(mp4, "video", "video/mp4"));
  assert.throws(() => validateDownloadedMedia(Buffer.from("bad"), "image", ""));
});

test("closePageAfterBatchTimeout closes timed-out page and records log", async () => {
  const logs = [];
  const calls = [];
  const page = {
    async close(options) {
      calls.push(options);
    },
  };

  const closed = await closePageAfterBatchTimeout(
    new BatchJobTimeoutError("too slow"),
    page,
    2,
    "https://www.instagram.com/alice/",
    logs,
  );

  assert.equal(closed, true);
  assert.deepEqual(calls, [{ runBeforeUnload: false }]);
  assert.equal(logs[0], "batch_slot_2_timeout_page_closed=https://www.instagram.com/alice/");
});
