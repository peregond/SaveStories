// Поддельный GitHub Releases для проверки обновления на Windows-раннере: отдаёт «latest» с версией выше любой настоящей
// и тот же установщик, который проверяется. Запуск: node update_e2e_server.mjs --setup=<путь> --portfile=<файл>
import fs from "node:fs";
import http from "node:http";
import crypto from "node:crypto";
import path from "node:path";

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const setupPath = args.setup;
const bytes = fs.readFileSync(setupPath);
const digest = crypto.createHash("sha256").update(bytes).digest("hex");
const tag = "v99.0.0";
const assetName = `SaveMe-Windows-Setup-${tag}.exe`;
let port = 0;
const server = http.createServer((req, res) => {
  if (req.url === "/releases/latest") {
    const body = {
      tag_name: tag, name: `SaveMe ${tag} (проверка)`, body: "Проверка обновления на CI", html_url: "http://127.0.0.1/", published_at: new Date().toISOString(),
      assets: [{ name: assetName, browser_download_url: `http://127.0.0.1:${port}/dl/${assetName}`, size: bytes.length, digest: `sha256:${digest}` }],
    };
    res.writeHead(200, { "Content-Type": "application/json" }); res.end(JSON.stringify(body)); return;
  }
  if (req.url === `/dl/${assetName}`) {
    res.writeHead(200, { "Content-Type": "application/octet-stream", "Content-Length": bytes.length }); res.end(bytes); return;
  }
  res.writeHead(404); res.end();
});
server.listen(0, "127.0.0.1", () => {
  port = server.address().port;
  fs.writeFileSync(args.portfile, String(port));
  console.log(`Сервер релизов: http://127.0.0.1:${port}, ${path.basename(setupPath)}, sha256 ${digest}`);
});
