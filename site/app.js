// excalidrawer in the browser: the editor full screen, the drawing kept in
// this browser between visits, files opened and saved on this computer.
import Excalidrawer from "./editor/excalidraw-widget.js";

const { mount, files: F } = Excalidrawer;
const boot = document.getElementById("boot");

// --- a tiny key-value store in IndexedDB (drawings can hold big images) ---
const db = new Promise((resolve, reject) => {
  const req = indexedDB.open("excalidrawer", 1);
  req.onupgradeneeded = () => req.result.createObjectStore("kv");
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});
const kv = async (mode, fn) => {
  const tx = (await db).transaction("kv", mode);
  const req = fn(tx.objectStore("kv"));
  return new Promise((resolve, reject) => { tx.oncomplete = () => resolve(req?.result); tx.onerror = () => reject(tx.error); });
};
const kvGet = (k) => kv("readonly", (s) => s.get(k)).catch(() => undefined);
const kvSet = (k, v) => kv("readwrite", (s) => s.put(v, k)).catch(() => {});

// --- state ---
const doc = { name: (await kvGet("name")) || "Untitled.excalidraw", handle: null, dirty: false };
const hasPicker = "showOpenFilePicker" in window;
const PICKER_TYPES = [{
  description: "Excalidraw drawings",
  accept: {
    "application/vnd.excalidraw+json": [".excalidraw"],
    "text/markdown": [".md"],
    "image/svg+xml": [".svg"],
    "image/png": [".png"],
    "application/vnd.excalidrawlib+json": [".excalidrawlib"],
  },
}];

function setTitle() {
  document.title = `${doc.dirty ? "• " : ""}${F.drawingStem(doc.name)} · excalidrawer`;
}

function download(name, blob) {
  Excalidrawer.extras.download(name, blob);
}

let ctrl;
// A drawing has changes when its version (the sum of its elements' versions,
// as Excalidraw counts it) differs from the one last opened or saved.
const sceneVersion = (els) => (els || []).reduce((a, e) => a + (e.version || 0), 0);
const markClean = () => { doc.base = sceneVersion(ctrl.getSceneData()?.elements); doc.dirty = false; setTitle(); };
let saveTimer = null;

const theme = (await kvGet("theme")) || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");

try {
  ctrl = mount(document.getElementById("app"), {
    scene: (await kvGet("scene")) || undefined,
    theme,
    name: F.drawingStem(doc.name),
    canvasActions: { loadScene: false },
    extras: { stickers: new URL("./stickers/", location.href).href, download, fileName: () => F.drawingStem(doc.name) },
    menu: [
      { label: "New drawing", onSelect: newDrawing },
      { label: "Open…", shortcut: "Ctrl+O", onSelect: openFile },
      { label: "Save", shortcut: "Ctrl+S", onSelect: save },
      { label: "Save as…", shortcut: "Ctrl+Shift+S", onSelect: saveAs },
      { label: "About excalidrawer", onSelect: () => document.getElementById("about").showModal() },
    ],
    debounce: 300,
    onChange(json, { elements, appState }) {
      clearTimeout(saveTimer);
      saveTimer = setTimeout(() => kvSet("scene", json), 200);
      if (appState?.theme) kvSet("theme", appState.theme);
      const dirty = doc.base !== undefined && sceneVersion(elements) !== doc.base;
      if (dirty !== doc.dirty) { doc.dirty = dirty; setTitle(); }
    },
  });
  await ctrl.ready;
  boot.hidden = true;
  markClean();
} catch (e) {
  boot.textContent = `The editor could not start: ${e.message}`;
  boot.className = "error";
  throw e;
}
setTitle();

async function load(file, name = file.name, handle = null) {
  try {
    const r = await F.readDrawingFile(file, name);
    if (r.kind === "library") {
      await ctrl.api.updateLibrary({ libraryItems: r.blob, merge: true, openLibraryMenu: true });
      return;
    }
    await ctrl.setScene(r.scene);
    Object.assign(doc, { name, handle });
    kvSet("name", name);
    markClean();
  } catch (e) {
    alert(e.message);
  }
}

async function openFile() {
  if (hasPicker) {
    try {
      const [handle] = await showOpenFilePicker({ types: PICKER_TYPES, excludeAcceptAllOption: false });
      const file = await handle.getFile();
      return load(file, file.name, handle);
    } catch (e) {
      if (e.name !== "AbortError") alert(e.message);
      return;
    }
  }
  const input = Object.assign(document.createElement("input"), { type: "file", accept: ".excalidraw,.md,.svg,.png,.excalidrawlib,.json" });
  input.onchange = () => input.files[0] && load(input.files[0]);
  input.click();
}

async function writeTo(handle, name) {
  const blob = await F.drawingBlob(ctrl, name);
  const w = await handle.createWritable();
  await w.write(blob);
  await w.close();
}

async function save() {
  if (doc.handle?.createWritable) {
    try {
      await writeTo(doc.handle, doc.name);
      markClean();
      return;
    } catch (e) {
      if (e.name === "AbortError") return;
    }
  }
  return saveAs();
}

async function saveAs() {
  let name = F.isDrawingName(doc.name) ? doc.name : `${F.drawingStem(doc.name)}.excalidraw`;
  if ("showSaveFilePicker" in window) {
    try {
      const handle = await showSaveFilePicker({ suggestedName: name, types: PICKER_TYPES });
      name = handle.name;
      await writeTo(handle, name);
      Object.assign(doc, { name, handle });
    } catch (e) {
      if (e.name !== "AbortError") alert(e.message);
      return;
    }
  } else {
    download(name, await F.drawingBlob(ctrl, name));
    doc.name = name;
  }
  kvSet("name", doc.name);
  markClean();
}

async function newDrawing() {
  if (doc.dirty && !confirm("Start a new drawing? The current one has changes that are not saved to a file.")) return;
  await ctrl.reset();
  Object.assign(doc, { name: "Untitled.excalidraw", handle: null });
  kvSet("name", doc.name);
  markClean();
}

// Keyboard: these win over the editor's own handling of the same keys.
window.addEventListener("keydown", (e) => {
  const mod = e.ctrlKey || e.metaKey;
  if (!mod || e.altKey) return;
  const k = e.key.toLowerCase();
  if (k === "s") { e.preventDefault(); e.stopPropagation(); (e.shiftKey ? saveAs : save)(); }
  else if (k === "o" && !e.shiftKey) { e.preventDefault(); e.stopPropagation(); openFile(); }
}, true);

// Obsidian files dropped on the canvas: Excalidraw itself handles the rest.
document.getElementById("app").addEventListener("drop", (e) => {
  const file = [...(e.dataTransfer?.files || [])].find((f) => Excalidrawer.extras.isObsidian(f.name));
  if (!file) return;
  e.preventDefault();
  e.stopPropagation();
  load(file);
}, true);

// Files opened with the installed app (file_handlers in the manifest).
if ("launchQueue" in window) {
  launchQueue.setConsumer(async (params) => {
    const [handle] = params.files || [];
    if (handle) { const file = await handle.getFile(); load(file, file.name, handle); }
  });
}

window.addEventListener("beforeunload", (e) => {
  if (doc.dirty && doc.handle) e.preventDefault();
});

// Offline use. The service worker is written by srcjs/tools/build-site.mjs.
if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost" || location.hostname === "127.0.0.1")) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}

window.excalidrawer = { ctrl, doc, version: Excalidrawer.version };
