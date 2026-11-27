// End-to-end tests of the website (site-dist/) in a real browser.
//
//   cd srcjs && npm run build && npm run site   # builds the bundle and site-dist/
//   npm run e2e                                 # Chromium (uses installed Chrome if present)
//   BROWSER=webkit npm run e2e                  # WebKit, Safari's engine
//   SHOTS=dir npm run e2e                       # also save screenshots
//
// One PASS / FAIL / SKIP line per check; the exit code says whether all passed.

import { chromium, webkit } from "playwright";
import http from "node:http";
import { readFile, stat } from "node:fs/promises";
import { readFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fromObsidian } from "../src/extras/obsidian.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const site = path.join(root, "site-dist");
const fixture = path.join(root, "srcjs/test/fixtures/r-scene.excalidraw.md");
const engine = process.env.BROWSER === "webkit" ? "webkit" : "chromium";
const shots = process.env.SHOTS || "";
if (shots) mkdirSync(shots, { recursive: true });

// --- a static server for site-dist ---
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".webmanifest": "application/manifest+json",
  ".excalidrawlib": "application/json", ".txt": "text/plain", ".md": "text/markdown" };
const server = http.createServer(async (req, res) => {
  try {
    let file = path.join(site, decodeURIComponent(new URL(req.url, "http://x").pathname));
    if (!file.startsWith(site)) throw new Error("outside");
    if ((await stat(file)).isDirectory()) file = path.join(file, "index.html");
    res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream", "Cache-Control": "no-cache" });
    res.end(await readFile(file));
  } catch { res.writeHead(404).end("Not found"); }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = `http://127.0.0.1:${server.address().port}/`;

// --- checks ---
let failed = 0;
async function check(name, fn) {
  try {
    const r = await fn();
    if (r && r.skip) { console.log(`SKIP  ${name}: ${r.skip}`); return; }
    console.log(`PASS  ${name}${r && r !== true ? `: ${typeof r === "string" ? r : JSON.stringify(r)}` : ""}`);
  } catch (e) {
    failed++;
    console.log(`FAIL  ${name}: ${e.message.split("\n")[0]}`);
    if (shots) await page.screenshot({ path: path.join(shots, `FAIL-${name}.png`) }).catch(() => {});
  }
}
const expect = (ok, msg) => { if (!ok) throw new Error(msg); };

const browser = engine === "webkit" ? await webkit.launch()
  : await chromium.launch({ channel: "chrome" }).catch(() => chromium.launch());
console.log(`engine: ${engine} ${browser.version()}  site: ${url}`);
const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, acceptDownloads: true, colorScheme: "light" });
const page = await context.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !/favicon|Slow network|Permissions policy violation: unload/.test(m.text())) errors.push(m.text()); });

const ready = () => page.waitForFunction(() => window.scratchy?.ctrl?.api, null, { timeout: 30000 });
const scene = () => page.evaluate(() => window.scratchy.ctrl.getSceneData().elements.filter((e) => !e.isDeleted));
const openTab = async (tab) => {
  await page.evaluate((tab) => window.scratchy.ctrl.api.toggleSidebar({ name: "scratchy", tab, force: true }), tab);
  await page.waitForSelector(".exr-sidebar");
};
const sidebarButton = (text) => page.locator(".exr-sidebar button", { hasText: text }).first();
const download = async (text) => {
  const [d] = await Promise.all([page.waitForEvent("download"), sidebarButton(text).click()]);
  return { name: d.suggestedFilename(), text: readFileSync(await d.path(), "latin1") };
};

await check("loads", async () => {
  await page.goto(url);
  await ready();
  const v = await page.evaluate(() => window.scratchy.version);
  expect(await page.title() === "Untitled · scratchy", `title ${await page.title()}`);
  return `scratchy ${v}`;
});

await check("draws a rectangle with the mouse", async () => {
  await page.getByTitle(/^Rectangle/).first().click();
  const canvas = await page.locator(".ws-editor:not([hidden])").boundingBox();
  await page.mouse.move(canvas.x + canvas.width * .45, canvas.y + canvas.height * .4);
  await page.mouse.down();
  await page.mouse.move(canvas.x + canvas.width * .65, canvas.y + canvas.height * .6, { steps: 5 });
  await page.mouse.up();
  const els = await scene();
  expect(els.length === 1 && els[0].type === "rectangle", `scene: ${els.map((e) => e.type)}`);
  await page.waitForFunction(() => document.title.startsWith("• "));
});

await check("keeps the drawing after a reload", async () => {
  await page.waitForTimeout(800);
  await page.reload();
  await ready();
  const els = await scene();
  expect(els.length === 1, `${els.length} elements`);
});

await check("adds a sticker library to Excalidraw's library", async () => {
  await openTab("stickers");
  await page.locator(".exr-item", { hasText: "Stick Figures" }).locator("button").click();
  await page.waitForSelector(".library-unit", { timeout: 10000 });
  return `${await page.locator(".library-unit").count()} stickers`;
});

await check("adds an Open Peeps person", async () => {
  await openTab("people");
  await sidebarButton("Add person").click();
  await page.waitForFunction(() => window.scratchy.ctrl.getSceneData().elements.some((e) => e.type === "image"), null, { timeout: 10000 });
});

await check("applies the chalkboard preset", async () => {
  await page.evaluate(() => window.scratchy.ctrl.api.updateScene({ appState: { selectedElementIds: {} } }));
  await openTab("style");
  await sidebarButton("chalkboard").click();
  const bg = await page.evaluate(() => window.scratchy.ctrl.api.getAppState().viewBackgroundColor);
  expect(bg === "#2f3d33", bg);
  const rough = (await scene()).find((e) => e.type === "rectangle").roughness;
  expect(rough === 2, `roughness ${rough}`);
});

await check("converts Mermaid", async () => {
  await openTab("mermaid");
  const before = (await scene()).length;
  await sidebarButton("Add to drawing").click();
  await page.waitForFunction((n) => window.scratchy.ctrl.getSceneData().elements.length > n, before, { timeout: 20000 });
  return `${(await scene()).length - before} elements`;
});

await check("exports PNG and SVG", async () => {
  await openTab("export");
  const png = await download("PNG");
  expect(png.name.endsWith(".png") && png.text.startsWith("\x89PNG"), png.name);
  const svg = await download("SVG");
  expect(svg.name.endsWith(".svg") && svg.text.includes("<svg"), svg.name);
});

await check("exports a self-drawing SVG", async () => {
  await openTab("export");
  const a = await download("Animated SVG");
  const frames = (a.text.match(/@keyframes/g) || []).length;
  expect(frames > 5 && a.text.includes("prefers-reduced-motion"), `${frames} keyframes`);
  return `${frames} keyframes`;
});

await check("saves Obsidian .excalidraw.md that reads back", async () => {
  await openTab("export");
  const md = await download("Obsidian .md");
  const back = JSON.parse(fromObsidian(md.text));
  const n = (await scene()).length;
  expect(back.elements.filter((e) => !e.isDeleted).length === n, `${back.elements.length} vs ${n}`);
});

await check("opens an .excalidraw.md written by R (dropped on the canvas)", async () => {
  const text = readFileSync(fixture, "utf8");
  await page.evaluate((text) => {
    const dt = new DataTransfer();
    dt.items.add(new File([text], "plan.excalidraw.md", { type: "text/markdown" }));
    document.querySelector("#app canvas").dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: dt }));
  }, text);
  await page.waitForFunction(() => document.title.startsWith("plan ·"), null, { timeout: 10000 });
  const texts = (await scene()).filter((e) => e.type === "text").map((e) => e.text);
  expect(texts.includes("Ünïcode ✓ text"), texts.join("|"));
});

await check("works offline once loaded", async () => {
  const sw = await page.evaluate(() => navigator.serviceWorker?.ready.then(() => true).catch(() => false));
  if (!sw) return { skip: "no service worker in this browser" };
  // Wait for the worker to finish caching everything in the background.
  const want = await page.evaluate(async () => {
    const src = await (await fetch("sw.js")).text();
    return JSON.parse(src.match(/const CORE = (\[.*?\]);/)[1]).length + JSON.parse(src.match(/const REST = (\[.*?\]);/)[1]).length;
  });
  await page.waitForFunction(async (want) => {
    const keys = await caches.keys();
    const c = keys.length && (await caches.open(keys.find((k) => k.startsWith("scratchy-"))));
    return c && (await c.keys()).length >= want;
  }, want, { timeout: 60000, polling: 500 });
  await context.setOffline(true);
  try {
    await page.reload();
    await ready();
    const els = await page.evaluate(() => window.scratchy.ctrl.mermaid("flowchart LR\n  a --> b").then((x) => x.length));
    expect(els > 0, "Mermaid added nothing");
  } finally {
    await context.setOffline(false);
  }
});

await check("no errors in the page", async () => {
  expect(!errors.length, errors.slice(0, 3).join(" | "));
});

if (shots) await page.screenshot({ path: path.join(shots, `${engine}-final.png`) });
await browser.close();
server.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exit(failed ? 1 : 0);
