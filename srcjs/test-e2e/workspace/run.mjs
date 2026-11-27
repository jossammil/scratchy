// Real-browser acceptance checks for workspace persistence and recovery.
import { chromium, webkit } from "playwright";
import http from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const site = path.resolve(fileURLToPath(new URL("../../../site-dist/", import.meta.url)));
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".webmanifest": "application/manifest+json" };
const server = http.createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    if (pathname === "/seed.html") { res.writeHead(200, { "Content-Type": "text/html" }); res.end("<!doctype html><title>Workspace fixture</title>"); return; }
    let file = path.resolve(site, `.${pathname}`);
    if (!file.startsWith(site)) throw new Error("outside test site");
    if ((await stat(file)).isDirectory()) file = path.join(file, "index.html");
    res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream", "Cache-Control": "no-cache" }); res.end(await readFile(file));
  } catch { res.writeHead(404).end(); }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
const engine = process.env.BROWSER === "webkit" ? "webkit" : "chromium";
const browser = engine === "webkit" ? await webkit.launch() : await chromium.launch({ channel: "chrome" }).catch(() => chromium.launch());
const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, acceptDownloads: true });
const page = await context.newPage(), errors = [];
context.on("page", (p) => p.on("pageerror", (error) => errors.push(error.message)));
page.on("pageerror", (error) => errors.push(error.message));
const expect = (condition, message) => { if (!condition) throw new Error(message); };
const ready = async (p = page) => { await p.waitForFunction(() => window.scratchy?.ctrl?.api, null, { timeout: 30000 }); };
const scene = () => page.evaluate(() => window.scratchy.ctrl.getSceneData().elements.filter((e) => !e.isDeleted));
const add = async (id, p = page) => {
  await p.evaluate(async (id) => { await window.scratchy.ctrl.add({ elements: [{ id, type: "rectangle", x: 30, y: 30, width: 100, height: 60, strokeColor: "#1e1e1e", backgroundColor: "#a5d8ff", seed: 1, version: 1 }] }); }, id);
  await p.waitForFunction((id) => window.scratchy.ctrl.api.getSceneElements().some((e) => e.id === id), id);
};
let failed = 0, first, second, archiveBytes;
async function check(name, fn) { try { const result = await fn(); console.log(`PASS  ${name}${result ? `: ${result}` : ""}`); } catch (error) { failed++; console.log(`FAIL  ${name}: ${error.stack}`); } }

try {
  console.log(`workspace engine: ${engine} ${browser.version()}`);
  await check("a blocked upgrade explains how to continue and preserves the old database", async () => {
    const c = await browser.newContext(), holding = await c.newPage(), waiting = await c.newPage();
    await holding.goto(`${url}seed.html`);
    await holding.evaluate(async () => {
      await new Promise((resolve) => { const r = indexedDB.open("scratchy", 1); r.onupgradeneeded = () => r.result.createObjectStore("kv"); r.onsuccess = () => { window.heldDatabase = r.result; const tx = r.result.transaction("kv", "readwrite"); tx.objectStore("kv").put("Keep this original", "evidence"); tx.oncomplete = resolve; }; });
    });
    await waiting.goto(url, { waitUntil: "commit" });
    await waiting.locator(".ws-notice").getByText("Close other Scratchy windows to finish upgrading", { exact: false }).waitFor();
    await holding.evaluate(() => window.heldDatabase.close()); await ready(waiting);
    expect(await waiting.locator("#ws-retry").isHidden(), "blocked-upgrade error remained after recovery");
    const evidence = await waiting.evaluate(async () => new Promise((resolve) => { const r = indexedDB.open("scratchy"); r.onsuccess = () => { const db = r.result, value = db.transaction("kv").objectStore("kv").get("evidence"); value.onsuccess = () => { db.close(); resolve(value.result); }; }; }));
    expect(evidence === "Keep this original", "legacy keys changed"); await c.close();
  });
  await check("version-one migration keeps the name, image and original keys exactly once", async () => {
    await page.goto(`${url}seed.html`);
    await page.evaluate(async () => {
      const scene = { type: "excalidraw", version: 2, elements: [{ id: "legacy-image", type: "image", x: 20, y: 20, width: 100, height: 100, fileId: "pixel", status: "saved", scale: [1, 1], customData: { provenance: "legacy" } }], appState: { viewBackgroundColor: "#ffffff" }, files: { pixel: { id: "pixel", mimeType: "image/png", created: 123, dataURL: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jX1sAAAAASUVORK5CYII=" } } };
      await new Promise((resolve, reject) => { const r = indexedDB.open("scratchy", 1); r.onupgradeneeded = () => r.result.createObjectStore("kv"); r.onerror = () => reject(r.error); r.onsuccess = () => { const db = r.result, tx = db.transaction("kv", "readwrite"); tx.objectStore("kv").put(JSON.stringify(scene), "scene"); tx.objectStore("kv").put("Legacy.excalidraw", "name"); tx.objectStore("kv").put("dark", "theme"); tx.oncomplete = () => { db.close(); resolve(); }; }; });
    });
    await page.goto(url); await ready();
    first = await page.evaluate(() => window.scratchy.workspace.activeId);
    expect(first === "legacy-drawing", first);
    expect((await page.title()).includes("Legacy"), "filename missing");
    expect((await scene())[0].customData.provenance === "legacy", "customData lost");
    const before = await page.evaluate(async () => (await window.scratchy.workspace.store.dump()).assets.length);
    expect(before === 1, `assets ${before}`);
    await page.reload(); await ready();
    expect(await page.evaluate(async () => (await window.scratchy.workspace.store.list()).boards.length) === 1, "migration duplicated a board");
    expect(await page.evaluate(() => window.scratchy.workspace.theme) === "dark", "theme lost");
  });
  await check("rapid switches keep drawings, Undo, viewport and backgrounds isolated", async () => {
    await add("only-A");
    second = await page.evaluate(async () => (await window.scratchy.workspace.createBoard(undefined, { title: "Board B" })).id);
    await add("only-B");
    await page.evaluate(() => window.scratchy.ctrl.set({ background: "#fff3bf" }));
    await page.waitForFunction(() => window.scratchy.ctrl.api.getAppState().viewBackgroundColor === "#fff3bf");
    // Finish/cancel the insertion's animated pan before simulating a settled viewport.
    await page.evaluate(() => { window.scratchy.ctrl.api.scrollToContent([], { animate: false }); window.scratchy.ctrl.api.updateScene({ appState: { scrollX: 33, scrollY: 44, zoom: { value: 1.2 } } }); });
    await page.waitForFunction(() => window.scratchy.ctrl.api.getAppState().zoom.value === 1.2);
    await page.evaluate(() => window.scratchy.workspace.flush());
    await page.evaluate((id) => window.scratchy.workspace.switchTo(id), first);
    expect((await scene()).some((e) => e.id === "only-A") && !(await scene()).some((e) => e.id === "only-B"), "A was overwritten");
    await page.evaluate((id) => window.scratchy.workspace.switchTo(id), second);
    const view = await page.evaluate(() => window.scratchy.ctrl.api.getAppState());
    expect(view.viewBackgroundColor === "#fff3bf" && view.zoom.value === 1.2, `background or zoom changed: ${view.viewBackgroundColor}, ${view.zoom.value}`);
    const canvas = page.locator('.ws-editor:not([hidden]) .excalidraw');
    await canvas.click({ position: { x: 550, y: 450 } });
    await page.keyboard.press(`${process.platform === "darwin" ? "Meta" : "Control"}+z`);
    await page.waitForFunction(() => !window.scratchy.ctrl.api.getSceneElements().some((e) => e.id === "only-B"));
    expect(!(await scene()).some((e) => e.id === "only-A"), "Undo revealed A in B");
    await page.keyboard.press(`${process.platform === "darwin" ? "Meta" : "Control"}+Shift+z`);
    await page.waitForFunction(() => window.scratchy.ctrl.api.getSceneElements().some((e) => e.id === "only-B"));
    await page.evaluate(() => window.scratchy.workspace.flushAll());
  });
  await check("close and reopen keeps content; a duplicate has no writable file handle", async () => {
    await page.evaluate((id) => window.scratchy.workspace.closeBoard(id), first);
    expect(!await page.evaluate((id) => window.scratchy.workspace.sessions.has(id), first), "closed editor retained");
    await page.evaluate((id) => window.scratchy.workspace.switchTo(id), first);
    expect((await scene()).some((e) => e.id === "only-A"), "closed board lost");
    await page.evaluate(async (id) => { const w = window.scratchy.workspace; w.active.handle = { createWritable() { throw new Error("Original handle must not be used"); } }; await w.boardAction("duplicate", id); }, first);
    expect(await page.evaluate(() => window.scratchy.workspace.active.handle) === null, "duplicate inherited handle");
    await page.evaluate((id) => { window.scratchy.workspace.sessions.get(id).handle = null; }, first);
  });
  await check("renaming keeps the mounted session and Undo; file-save fallback captures the right board", async () => {
    const previous = await page.evaluate(() => { window.sameController = window.scratchy.ctrl; return window.scratchy.workspace.activeId; });
    page.once("dialog", (d) => d.accept("Renamed copy"));
    await page.locator("#ws-actions").selectOption("rename");
    await page.waitForFunction(() => window.scratchy.workspace.active.board.title === "Renamed copy");
    expect(await page.evaluate(() => window.sameController === window.scratchy.ctrl), "rename remounted the editor");
    await page.evaluate(() => { window.originalPicker = window.showSaveFilePicker; window.showSaveFilePicker = undefined; });
    const [download] = await Promise.all([page.waitForEvent("download"), page.evaluate(() => window.scratchy.workspace.saveFile())]);
    expect(download.suggestedFilename() === "Renamed copy.excalidraw", download.suggestedFilename());
    expect((await readFile(await download.path(), "utf8")).includes("only-A"), "saved the wrong board");
    await page.evaluate(() => { if (window.originalPicker) window.showSaveFilePicker = window.originalPicker; });
    expect(await page.evaluate(() => window.scratchy.workspace.activeId) === previous, "save changed active board");
  });
  await check("ordinary image drops insert into the active board without creating a board", async () => {
    const count = await page.evaluate(() => window.scratchy.workspace.boards.size);
    await page.evaluate(() => {
      const data = new DataTransfer();
      const bytes = Uint8Array.from(atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jX1sAAAAASUVORK5CYII="), (c) => c.charCodeAt(0));
      data.items.add(new File([bytes], "ordinary.png", { type: "image/png" }));
      document.querySelector('.ws-editor:not([hidden]) canvas').dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: data, clientX: 300, clientY: 250 }));
    });
    await page.waitForFunction(() => window.scratchy.ctrl.api.getSceneElements().filter((e) => e.type === "image").length >= 2);
    expect(await page.evaluate(() => window.scratchy.workspace.boards.size) === count, "ordinary image became a board");
  });
  await check("folders, pins and label search work through the collection UI", async () => {
    await page.evaluate(async (id) => { const w = window.scratchy.workspace; const parent = await w.store.folder("Research"), child = await w.store.folder("Methods", parent.id); await w.store.patch(id, { folderId: child.id, pinned: true }); await w.switchTo(id); await w.active.ctrl.add({ elements: [{ id: "search-label", type: "text", x: 120, y: 150, width: 150, height: 25, text: "Café retry policy", originalText: "Café retry policy", fontSize: 20, fontFamily: 5 }] }); await w.flush(); await w.refresh(); }, first);
    await page.getByRole("button", { name: "All boards", exact: true }).first().click();
    await page.getByRole("searchbox", { name: "Search boards" }).fill("retry cafe");
    await page.waitForFunction(() => document.querySelectorAll("#ws-results article").length === 1);
    expect((await page.locator("#ws-results").innerText()).includes("Café retry policy"), "label snippet missing");
    await page.locator("#ws-search").press("Enter");
    expect(await page.evaluate(() => window.scratchy.workspace.activeId) === first, "search opened wrong board");
    await page.evaluate(async () => { const w = window.scratchy.workspace; const f = w.folders.find((f) => f.title === "Methods"); await w.store.deleteFolder(f.id); await w.refresh(); });
    expect(await page.evaluate((id) => { const w = window.scratchy.workspace; return w.boards.get(id).folderId === w.folders.find((f) => f.title === "Research").id; }, first), "folder deletion deleted or orphaned content");
  });
  await check("history previews and restores; clear preserves the previous drawing", async () => {
    await page.evaluate(async () => { const w = window.scratchy.workspace; await w.flush(); await w.store.checkpoint(w.activeId); });
    await add("later-edit"); await page.evaluate(() => window.scratchy.workspace.flush());
    const versionId = await page.evaluate(async () => (await window.scratchy.workspace.store.history(window.scratchy.workspace.activeId))[0].id);
    await page.evaluate(() => window.scratchy.workspace.showHistory(window.scratchy.workspace.activeId));
    await page.locator("#ws-versions button").first().click();
    await page.waitForFunction(() => window.scratchy.workspace.preview?.api);
    expect(await page.locator("#ws-preview").isVisible(), "preview missing");
    await page.getByRole("button", { name: "Restore this version", exact: true }).click();
    await page.waitForFunction(() => !document.querySelector("#ws-history").open);
    expect(!(await scene()).some((e) => e.id === "later-edit"), "restore did not replace content");
    expect(await page.evaluate(async () => (await window.scratchy.workspace.store.history(window.scratchy.workspace.activeId)).length) >= 2, "restore discarded previous current version");
    await page.evaluate(() => window.scratchy.ctrl.reset());
    await page.waitForFunction(() => !window.scratchy.ctrl.api.getSceneElements().length);
    await page.evaluate(() => window.scratchy.workspace.flush());
    const versions = await page.evaluate(async () => window.scratchy.workspace.store.history(window.scratchy.workspace.activeId));
    expect(versions.some((v) => v.id === versionId), "earlier history disappeared");
    await page.evaluate(({ first, versionId }) => window.scratchy.workspace.restoreVersion(first, versionId), { first, versionId });
  });
  await check("trash restores content and expiry releases unreferenced assets", async () => {
    await page.evaluate((id) => window.scratchy.workspace.boardAction("trash", id), second);
    expect(await page.evaluate(async (id) => Boolean((await window.scratchy.workspace.store.board(id)).board.deletedAt), second), "not trashed");
    await page.evaluate((id) => window.scratchy.workspace.boardAction("restore", id), second);
    expect((await scene()).some((e) => e.id === "only-B"), "restored board lost content");
    await page.evaluate(async () => { const w = window.scratchy.workspace, before = (await w.store.dump()).assets.length; const disposable = await w.store.create({ type: "excalidraw", elements: [{ id: "disposable-image", type: "image", fileId: "unique" }], files: { unique: { id: "unique", mimeType: "image/png", dataURL: "data:image/png;base64,dW5pcXVl" } }, appState: {} }, { title: "Expiry fixture" }); await w.store.trash(disposable.id); await w.store.expire(Date.now() + 31 * 86400000); if (await w.store.board(disposable.id)) throw new Error("expired board survived"); if ((await w.store.dump()).assets.length !== before) throw new Error("expired image was retained"); });
  });
  await check("a full ZIP restores a fresh browser and reimport is idempotent", async () => {
    const [download, bytes] = await Promise.all([page.waitForEvent("download"), page.evaluate(async () => { const blob = await window.scratchy.workspace.backup(); return Array.from(new Uint8Array(await blob.arrayBuffer())); })]);
    archiveBytes = bytes;
    expect(download.suggestedFilename().endsWith(".zip"), "not a ZIP download");
    const freshContext = await browser.newContext(); const fresh = await freshContext.newPage();
    await fresh.goto(url); await ready(fresh);
    const result = await fresh.evaluate(async (bytes) => window.scratchy.workspace.restoreBackup(new Blob([new Uint8Array(bytes)])), archiveBytes);
    expect(result.fresh && result.added >= 3, `fresh restore ${JSON.stringify(result)}`);
    expect(await fresh.evaluate(() => window.scratchy.workspace.folders.some((f) => f.title === "Research")), "folders missing");
    expect(await fresh.evaluate(async (id) => (await window.scratchy.workspace.store.history(id)).length > 0, first), "history missing");
    const again = await fresh.evaluate(async (bytes) => window.scratchy.workspace.restoreBackup(new Blob([new Uint8Array(bytes)])), archiveBytes);
    expect(again.added === 0, `reimport added ${again.added} duplicates`);
    await freshContext.close();
  });
  await check("restoring an older ZIP preserves current content and does not repeat conflict copies", async () => {
    await page.evaluate((id) => window.scratchy.workspace.switchTo(id), second); await add("keep-new-content"); await page.evaluate(() => window.scratchy.workspace.flush());
    const result = await page.evaluate(async (bytes) => window.scratchy.workspace.restoreBackup(new Blob([new Uint8Array(bytes)])), archiveBytes);
    expect(result.added >= 1, "conflicting archive did not create a separate board");
    expect((await scene()).some((e) => e.id === "keep-new-content"), "existing current content overwritten");
    const again = await page.evaluate(async (bytes) => window.scratchy.workspace.restoreBackup(new Blob([new Uint8Array(bytes)])), archiveBytes);
    expect(again.added === 0, `repeated conflict restore added ${again.added} boards`);
  });
  await check("two windows preserve stale edits as a recovered board", async () => {
    const other = await context.newPage(); await other.goto(url); await ready(other);
    await other.evaluate((id) => window.scratchy.workspace.switchTo(id), second);
    await add("newest-window", page); await page.evaluate(() => window.scratchy.workspace.flush());
    await add("stale-window", other); await other.evaluate(() => window.scratchy.workspace.flush());
    const recovered = await other.evaluate(() => ({ id: window.scratchy.workspace.activeId, title: window.scratchy.workspace.active.board.title }));
    expect(recovered.id !== second && recovered.title.includes("recovered"), JSON.stringify(recovered));
    expect((await scene()).some((e) => e.id === "newest-window"), "current window overwritten");
    await other.close();
  });
  await check("failed writes expose retry and a downloadable current drawing", async () => {
    await page.evaluate(() => { window.originalPut = IDBObjectStore.prototype.put; const failedId = window.scratchy.workspace.activeId; IDBObjectStore.prototype.put = function(value, ...args) { if (this.name === "boards" && value.id === failedId) throw new DOMException("Storage full", "QuotaExceededError"); return window.originalPut.call(this, value, ...args); }; });
    await add("must-recover");
    await page.evaluate(async () => { try { await window.scratchy.workspace.flush(); } catch {} });
    expect(await page.getByRole("button", { name: "Download current drawing", exact: true }).isVisible(), "recovery action missing");
    const wait = page.waitForEvent("download"); await page.getByRole("button", { name: "Download current drawing", exact: true }).click();
    const download = await wait; const text = await readFile(await download.path(), "utf8");
    expect(text.includes("must-recover"), "download did not contain unsaved edits");
    await page.evaluate(() => { IDBObjectStore.prototype.put = window.originalPut; });
    await page.getByRole("button", { name: "Retry save", exact: true }).click();
    await page.waitForFunction(() => document.querySelector("#ws-retry").hidden);
  });
  await check("history stays bounded and images remain shared", async () => {
    const result = await page.evaluate(async () => {
      const w = window.scratchy.workspace; const data = await w.store.board("legacy-drawing"), before = (await w.store.dump()).assets.length;
      const created = await w.store.create(data.scene, { title: "Retention fixture" }); let b = created;
      for (let i = 0; i < 55; i++) { await w.store.patch(b.id, { snapshotAt: 0 }); const scene = { ...data.scene, appState: { ...data.scene.appState, viewBackgroundColor: `#${(i + 1).toString(16).padStart(6, "0")}` } }; b = (await w.store.save(b.id, b.revision, scene)).board; }
      const dump = await w.store.dump(); return { count: (await w.store.history(b.id)).length, assets: dump.assets.length, before };
    });
    expect(result.count === 50, `history count ${result.count}`);
    expect(result.assets === result.before, `history duplicated image assets: ${result.before} -> ${result.assets}`);
  });
  await check("large collections stay lazy; ten open editors and narrow-screen controls work", async () => {
    const result = await page.evaluate(async () => {
      const w = window.scratchy.workspace;
      for (let i = 0; i < 1000; i++) await w.store.create(undefined, { title: `Collection ${i}` });
      await w.refresh(); const collection = [...w.boards.values()].filter((b) => b.title.startsWith("Collection "));
      const before = w.sessions.size;
      for (const b of collection.slice(0, Math.max(0, 10 - before))) await w.switchTo(b.id);
      return { boards: w.boards.size, editors: w.sessions.size, before };
    });
    expect(result.boards >= 1000 && result.editors === 10, JSON.stringify(result));
    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByRole("button", { name: "All boards", exact: true }).first().click();
    await page.getByRole("searchbox", { name: "Search boards" }).fill("Collection 999");
    expect(await page.getByRole("searchbox", { name: "Search boards" }).isVisible(), "mobile search missing");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "horizontal page overflow");
    await page.locator("#ws-collection [data-close]").click();
    await page.setViewportSize({ width: 1280, height: 800 });
  });
  await check("workspace opens and searches offline after reload", async () => {
    await page.evaluate(() => window.scratchy.workspace.flushAll());
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForFunction(async () => { const keys = await caches.keys(); const cache = await caches.open(keys.find((k) => k.startsWith("scratchy-"))); return Boolean(await cache.match("workspace/index.js")) && Boolean(await cache.match("workspace/index.css")); });
    await context.setOffline(true);
    try {
      await page.reload(); await ready();
      expect(await page.evaluate(() => window.scratchy.workspace.sessions.size) === 1, "reload eagerly mounted hidden editors");
      await page.keyboard.press(`${process.platform === "darwin" ? "Meta" : "Control"}+p`);
      await page.getByRole("searchbox", { name: "Search boards" }).fill("Collection 999");
      await page.locator("#ws-search").press("Enter");
      await page.waitForFunction(() => window.scratchy.workspace.active?.board.title === "Collection 999");
    } finally { await context.setOffline(false); }
  });
  await check("no browser page errors", async () => expect(errors.length === 0, errors.join("\n")));
} finally {
  await browser.close(); server.close();
}
console.log(failed ? `${failed} workspace checks failed` : "all workspace checks passed");
process.exitCode = failed ? 1 : 0;
