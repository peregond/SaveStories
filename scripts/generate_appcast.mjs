#!/usr/bin/env node

import { readFileSync, statSync, writeFileSync } from "node:fs";
import { createPrivateKey, sign } from "node:crypto";

function readArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) {
    return "";
  }
  return process.argv[index + 1] ?? "";
}

function requiredArg(name) {
  const value = readArg(name);
  if (!value) {
    throw new Error(`Missing required argument --${name}`);
  }
  return value;
}

function escapeXml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&apos;");
}

function wrapCdata(value) {
  return value.replaceAll("]]>", "]]]]><![CDATA[>");
}

const assetPath = requiredArg("asset");
const assetURL = requiredArg("asset-url");
const releaseURL = requiredArg("release-url");
const version = requiredArg("version");
const build = requiredArg("build");
const output = requiredArg("output");
const title = readArg("title") || `SaveStories ${version}`;
const mimeType = readArg("mime-type") || "application/octet-stream";
const privateKeyPath = readArg("private-key-path");
const notes = readArg("notes") || `Release ${version} опубликован в GitHub Releases.`;

const privateKeyPem = privateKeyPath
  ? readFileSync(privateKeyPath, "utf8")
  : process.env.UPDATE_SIGNING_PRIVATE_KEY;

if (!privateKeyPem) {
  throw new Error("Missing update signing key. Provide --private-key-path or UPDATE_SIGNING_PRIVATE_KEY.");
}

const assetBuffer = readFileSync(assetPath);
const privateKey = createPrivateKey(privateKeyPem);
const signature = sign(null, assetBuffer, privateKey).toString("base64");
const assetSize = statSync(assetPath).size;
const publishedAt = new Date().toUTCString();
const description = wrapCdata(notes);

const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SaveStories Updates</title>
    <link>${escapeXml(releaseURL)}</link>
    <description>Release feed for SaveStories macOS updates.</description>
    <language>ru</language>
    <item>
      <title>${escapeXml(title)}</title>
      <pubDate>${escapeXml(publishedAt)}</pubDate>
      <sparkle:version>${escapeXml(build)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXml(version)}</sparkle:shortVersionString>
      <description><![CDATA[${description}]]></description>
      <enclosure
        url="${escapeXml(assetURL)}"
        sparkle:os="macos"
        length="${assetSize}"
        type="${escapeXml(mimeType)}"
        sparkle:edSignature="${escapeXml(signature)}" />
    </item>
  </channel>
</rss>
`;

writeFileSync(output, xml, "utf8");
