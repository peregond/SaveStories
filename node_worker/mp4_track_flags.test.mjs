import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { clearTrackPreviewFlag } from "./mp4_track_flags.mjs";

function box(type, ...parts) {
  const body = Buffer.concat(parts);
  const head = Buffer.alloc(8);
  head.writeUInt32BE(8 + body.length, 0);
  head.write(type, 4, "latin1");
  return Buffer.concat([head, body]);
}
function tkhd(flags) {
  const body = Buffer.alloc(84);
  body.writeUIntBE(flags, 1, 3); // версия 0 + флаги
  body.writeUInt32BE(720 * 65536, 76);
  body.writeUInt32BE(1280 * 65536, 80);
  return box("tkhd", body);
}
const trak = (flags) => box("trak", tkhd(flags), box("mdia", Buffer.from("payload")));
const ftyp = box("ftyp", Buffer.from("isom\0\0\x02\0isomiso2avc1mp41"));
const mdat = box("mdat", Buffer.alloc(4096, 7));

async function withFile(bytes, run) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-flags-"));
  const file = path.join(dir, "clip.mp4");
  await fs.writeFile(file, bytes);
  try { return await run(file); } finally { await fs.rm(dir, { recursive: true, force: true }); }
}
function flagsOf(bytes) {
  const out = [];
  for (let i = bytes.indexOf("tkhd"); i >= 0; i = bytes.indexOf("tkhd", i + 4)) out.push(bytes.readUIntBE(i + 5, 3));
  return out;
}

test("clears the preview bit of every track and changes nothing else", async () => {
  const original = Buffer.concat([ftyp, box("moov", trak(7), trak(7)), mdat]);
  await withFile(original, async (file) => {
    assert.equal(await clearTrackPreviewFlag(file), 2);
    const patched = await fs.readFile(file);
    assert.deepEqual(flagsOf(patched), [3, 3]);
    assert.equal(patched.length, original.length);
    let differing = 0;
    for (let i = 0; i < original.length; i += 1) if (original[i] !== patched[i]) differing += 1;
    assert.equal(differing, 2);
  });
});

test("works when moov comes after mdat and leaves other flag bits alone", async () => {
  await withFile(Buffer.concat([ftyp, mdat, box("moov", trak(0x0f), trak(1))]), async (file) => {
    assert.equal(await clearTrackPreviewFlag(file), 1);
    assert.deepEqual(flagsOf(await fs.readFile(file)), [0x0b, 1]);
  });
});

test("is a no-op for files that already have flag 3 and for non-mp4 data", async () => {
  const clean = Buffer.concat([ftyp, box("moov", trak(3)), mdat]);
  await withFile(clean, async (file) => {
    assert.equal(await clearTrackPreviewFlag(file), 0);
    assert.deepEqual(await fs.readFile(file), clean);
  });
  const junk = Buffer.from("not an mp4 at all, just some bytes".repeat(10));
  await withFile(junk, async (file) => {
    assert.equal(await clearTrackPreviewFlag(file), 0);
    assert.deepEqual(await fs.readFile(file), junk);
  });
  await withFile(Buffer.alloc(0), async (file) => { assert.equal(await clearTrackPreviewFlag(file), 0); });
});

test("a truncated moov is left alone", async () => {
  const whole = Buffer.concat([ftyp, box("moov", trak(7))]);
  await withFile(whole.subarray(0, whole.length - 10), async (file) => {
    assert.equal(await clearTrackPreviewFlag(file), 0);
  });
});
