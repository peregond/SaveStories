import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";

const runtimeRoot = await fs.mkdtemp(path.join(os.tmpdir(), "saveme-profile-identity-"));
process.env.SAVESTORIES_APP_SUPPORT = runtimeRoot;
process.env.SAVESTORIES_DEFAULT_DOWNLOADS = path.join(runtimeRoot, "downloads");
process.env.SAVESTORIES_MANIFESTS = path.join(runtimeRoot, "manifests");
process.env.SAVESTORIES_LOGS = path.join(runtimeRoot, "logs");
after(() => fs.rm(runtimeRoot, { recursive: true, force: true }));

const { extractProfileUserIdFromScriptTexts, extractProfileUserIdFromPayloads } = await import("./bridge.mjs");

function assertIdentity(payload, expected) {
  assert.equal(extractProfileUserIdFromPayloads([{ payload }], "alice"), expected);
  assert.equal(extractProfileUserIdFromScriptTexts([JSON.stringify(payload)], "alice"), expected);
}

test("profile identity survives fields separated by long descriptions and nested objects", () => {
  const profile = {
    id: "17841400000000000", pk: "424242",
    biography: "description ".repeat(300),
    profile_info: { flags: { is_business: false } },
    username: "alice",
  };
  assertIdentity({ require: [["RelayPrefetchedStreamCache", { data: { user: profile } }]] }, "424242");
  assertIdentity({ data: { user: { username: "alice", profile_info: profile.profile_info, biography: profile.biography, pk: "424242" } } }, "424242");
});

test("numeric id-only and user_id-only user nodes are recognized", () => {
  assertIdentity({ data: { user: { id: "424242", username: "alice" } } }, "424242");
  assertIdentity({ data: { user: { username: "alice", id: 424242 } } }, "424242");
  assertIdentity({ data: { user: { user_id: "424242", username: "Alice" } } }, "424242");
});

test("profile identity requires the exact expected username and skips unrelated recommendations", () => {
  assertIdentity({ data: {
    recommended: { pk: "111111", username: "bob" },
    misleading: { id: "222222", username: "al!ice" },
    profile: { user_id: "424242", username: "ALICE" },
  } }, "424242");
  assertIdentity({ data: { user: { id: "424242", username: "alice.extra" } } }, null);
});

test("media identifiers are never accepted as profile identifiers", () => {
  for (const media of [
    { id: "999999", username: "alice", media_type: 2 },
    { pk: "999999", username: "alice", video_versions: [] },
    { id: "999999", username: "alice", __typename: "XDTMediaDict" },
  ]) {
    assertIdentity({ data: { media } }, null);
    assertIdentity({ data: { media: { ...media, owner: { id: "424242", username: "alice" } } } }, "424242");
  }
});

test("non-numeric and rounded numeric profile identifiers are rejected", () => {
  assertIdentity({ user: { username: "alice", pk: "not-an-id", id: "VXNlcjo0MjQyNDI=" } }, null);
  assertIdentity({ user: { username: "alice", id: Number.MAX_SAFE_INTEGER + 2 } }, null);
});

test("JSON-looking biography text cannot impersonate a different profile record", () => {
  const payload = { user: { username: "bob", id: "999999", biography: JSON.stringify({ username: "alice", id: "123123" }) } };
  const json = JSON.stringify(payload);
  assertIdentity(payload, null);
  assert.equal(extractProfileUserIdFromScriptTexts([`<script type="application/json">${json}</script>`], "alice"), null);
});

test("escaped JSON and HTML script wrappers retain exact profile matching", () => {
  const profile = { id: "424242", biography: "long biography ".repeat(200), details: { account: "creator" }, username: "alice" };
  const json = JSON.stringify({ data: { user: profile } });
  assert.equal(extractProfileUserIdFromScriptTexts([json.replaceAll('"', '\\"')], "alice"), "424242");
  assert.equal(extractProfileUserIdFromScriptTexts([JSON.stringify(json)], "alice"), "424242");
  assert.equal(extractProfileUserIdFromScriptTexts([`<html><script type="application/json">${json}</script></html>`], "alice"), "424242");
  assert.equal(extractProfileUserIdFromScriptTexts([`window.__PROFILE__ = ${JSON.stringify({ id: "424242", username: "alice" })};`], "alice"), "424242");
  assert.equal(extractProfileUserIdFromScriptTexts([`window.__MEDIA__ = ${JSON.stringify({ id: "999999", username: "alice", media_type: 2 })};`], "alice"), null);
});
