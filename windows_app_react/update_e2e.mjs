// Ведёт установленное приложение через весь путь обновления по отладочному порту WebView2 (CDP):
// проверка → скачивание → установка (приложение закрывается, установщик ставит и запускает новое).
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const { playwright, out, phase, port = "9222" } = args;
const { chromium } = await import(pathToFileURL(playwright).href);
fs.mkdirSync(out, { recursive: true });
const result = { phase, checks: [] };
const check = (name, ok, detail = "") => { result.checks.push({ name, ok, detail }); console.log(`${ok ? "OK  " : "FAIL"} ${name}${detail ? " — " + detail : ""}`); };
const finish = (code) => { fs.writeFileSync(path.join(out, `update-${phase}.json`), JSON.stringify(result, null, 2)); process.exit(code); };

async function connect() {
  for (let i = 0; i < 90; i++) {
    try { const r = await fetch(`http://127.0.0.1:${port}/json/version`); if (r.ok) return await chromium.connectOverCDP(`http://127.0.0.1:${port}`); } catch { /* ещё запускается */ }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("Отладочный порт WebView2 не открылся за 90 с");
}

try {
  const browser = await connect();
  const pages = browser.contexts().flatMap((c) => c.pages());
  const page = pages.find((p) => /tauri\.localhost|localhost/.test(p.url())) ?? pages[0];
  await page.waitForSelector(".card", { timeout: 40000 });
  check("Интерфейс загрузился", true);
  const version = await page.evaluate(() => document.querySelector(".sidebar-foot")?.textContent?.trim());
  console.log("Версия в интерфейсе:", version);

  if (phase === "update") {
    const invoke = (cmd, a) => page.evaluate(([c, x]) => window.__TAURI_INTERNALS__.invoke(c, x), [cmd, a]);
    const info = await invoke("app_info");
    check("Автоустановка доступна (есть unins000.exe)", info.autoUpdate === true, JSON.stringify({ autoUpdate: info.autoUpdate, version: info.version }));
    const found = await invoke("update_check");
    check("Найдено обновление", found.status === "update_available", `${found.status} ${found.release?.version ?? ""}`);
    await invoke("update_prepare", { release: found.release });
    check("Обновление скачано, SHA-256 и подпись проверены", true);
    await invoke("update_install");
    check("Установщик запущен", true);
  }
  await browser.close().catch(() => {});
  finish(result.checks.every((c) => c.ok) ? 0 : 1);
} catch (e) {
  check("Сценарий выполнен без исключений", false, String(e).slice(0, 400));
  finish(1);
}
