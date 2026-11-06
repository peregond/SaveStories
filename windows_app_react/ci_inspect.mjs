// Проверка установленного приложения через отладочный порт WebView2 (CDP). Запускается из ci_inspect.ps1 встроенным Node.
// Жёсткие проверки (код выхода 1): интерфейс загрузился, все экраны открываются, очередь сохраняется и восстанавливается.
// Остальное (вид, Mica, тайминги) — только отчёт в JSON и скриншоты.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const { playwright, out, phase, port = "9222" } = args;
const { chromium } = await import(pathToFileURL(playwright).href);
fs.mkdirSync(out, { recursive: true });

const result = { phase, checks: [], info: {} };
const check = (name, ok, detail = "") => {
  result.checks.push({ name, ok, detail });
  console.log(`${ok ? "OK  " : "FAIL"} ${name}${detail ? " — " + detail : ""}`);
};
const finish = (code) => {
  fs.writeFileSync(path.join(out, `ui-${phase}.json`), JSON.stringify(result, null, 2));
  process.exit(code);
};

async function connect() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (r.ok) return await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
    } catch { /* окно ещё поднимается */ }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("Отладочный порт WebView2 не открылся за 60 с");
}

try {
  const browser = await connect();
  const pages = browser.contexts().flatMap((c) => c.pages());
  const page = pages.find((p) => /tauri\.localhost|localhost/.test(p.url())) ?? pages[0];
  check("Страница приложения найдена", !!page, page?.url());
  await page.waitForSelector(".card", { timeout: 40000 });
  check("Интерфейс загрузился", true);

  result.info = await page.evaluate(() => ({
    glass: document.documentElement.dataset.glass, theme: document.documentElement.dataset.theme, hidden: document.documentElement.dataset.hidden,
    width: window.innerWidth, height: window.innerHeight, dpr: window.devicePixelRatio, ua: navigator.userAgent,
    version: document.querySelector(".sidebar-foot")?.textContent?.trim(),
    jsHeapMB: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576 * 10) / 10 : null,
    domNodes: document.getElementsByTagName("*").length,
    loadMs: Math.round(performance.getEntriesByType("navigation")[0]?.domContentLoadedEventEnd ?? 0),
  }));
  console.log("Информация:", JSON.stringify(result.info));
  check("Версия показана", /Версия\s+\d+\.\d+\.\d+/.test(result.info.version ?? ""), result.info.version);

  const shot = (name) => page.screenshot({ path: path.join(out, `${phase}-${name}.png`) });

  if (phase === "first") {
    // Все экраны открываются
    for (const [label, selector, slug] of [["Stories", "textarea", "stories"], ["Reels", "textarea", "reels"], ["Сортировка", ".rules", "sorting"], ["Настройки", ".kv", "settings"]]) {
      await page.getByRole("button", { name: label, exact: true }).first().click();
      try { await page.waitForSelector(selector, { timeout: 8000 }); check(`Экран «${label}» открывается`, true); }
      catch (e) { check(`Экран «${label}» открывается`, false, String(e).slice(0, 120)); }
      await page.waitForTimeout(400);
      await shot(slug);
    }
    // Очередь: добавить профили через интерфейс
    await page.getByRole("button", { name: "Stories", exact: true }).first().click();
    await page.fill('textarea[aria-label="Список профилей"]', "ci_user1\nci_user2");
    await page.getByRole("button", { name: "В очередь", exact: true }).first().click();
    await page.waitForTimeout(1500); // сохранение очереди идёт с задержкой 500 мс
    const names = await page.$$eval(".item .name", (els) => els.map((e) => e.textContent));
    check("Профили появились в очереди", names.includes("ci_user1") && names.includes("ci_user2"), names.join(", "));
    await shot("queue-added");
    // Ничего не должно вылезать за границы карточек (строки очереди выходили за карточку в 0.6.89).
    const overflow = await page.evaluate(() => {
      const out = [];
      for (const card of document.querySelectorAll(".card")) {
        const cr = card.getBoundingClientRect();
        for (const el of card.querySelectorAll("*")) {
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.right > cr.right + 1 && getComputedStyle(el).position !== "absolute") out.push(`${el.tagName}.${String(el.className).slice(0, 24)} +${Math.round(r.right - cr.right)}px`);
        }
      }
      return out.slice(0, 5);
    });
    check("Ничего не вылезает за границы карточек", overflow.length === 0, overflow.join("; "));
  } else if (phase.startsWith("ping")) {
    // Короткая проверка «интерфейс живой»: переключаем экраны и ждём отрисовки (после сворачивания/разворачивания, с флагами).
    for (const [label, selector] of [["Настройки", ".kv"], ["Stories", "textarea"]]) {
      await page.getByRole("button", { name: label, exact: true }).first().click();
      try { await page.waitForSelector(selector, { timeout: 8000 }); check(`Интерфейс отвечает: «${label}»`, true); }
      catch (e) { check(`Интерфейс отвечает: «${label}»`, false, String(e).slice(0, 120)); }
    }
    await shot("ping");
  } else {
    // После перезапуска очередь должна вернуться с диска
    const banner = await page.$$eval(".banner", (els) => els.map((e) => e.textContent));
    check("Показано сообщение о восстановленной очереди", banner.some((t) => t?.includes("Восстановлена очередь")), banner.join(" | "));
    const names = await page.$$eval(".item .name", (els) => els.map((e) => e.textContent));
    check("Очередь восстановлена после перезапуска", names.includes("ci_user1") && names.includes("ci_user2"), names.join(", "));
    await shot("restored");
  }
  await browser.close().catch(() => {});
  finish(result.checks.every((c) => c.ok) ? 0 : 1);
} catch (e) {
  check("Сценарий выполнен без исключений", false, String(e).slice(0, 300));
  finish(1);
}
