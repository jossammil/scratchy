// Excalidraw editor for the excalidrawer R package: an htmlwidget renderer,
// Shiny messaging (scene updates, chart replacement, exports, Mermaid), and
// a few headless helpers that R drives through chromote.

import React, { useMemo, useRef } from "react";
import { createRoot } from "react-dom/client";
import {
  Excalidraw,
  MainMenu,
  CaptureUpdateAction,
  convertToExcalidrawElements,
  exportToBlob,
  exportToSvg,
  getSceneVersion,
  restore,
  serializeAsJSON,
} from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";

// Fonts are served next to this bundle so the editor works offline.
window.EXCALIDRAW_ASSET_PATH = new URL("./", import.meta.url).href;

const apis = new Map();

const parseScene = (scene) => {
  const data = typeof scene === "string" ? JSON.parse(scene) : scene || {};
  return restore({ type: "excalidraw", elements: [], ...data }, null, null);
};

const debounce = (fn, ms) => {
  let t = null;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
};

const shinyInput = (id, name, value) => {
  if (window.Shiny && window.Shiny.setInputValue && id) {
    window.Shiny.setInputValue(`${id}_${name}`, value, { priority: "event" });
  }
};

const toBase64 = async (blob) => {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let bin = "";
  const step = 0x8000;
  for (let i = 0; i < buf.length; i += step) {
    bin += String.fromCharCode.apply(null, buf.subarray(i, i + step));
  }
  return btoa(bin);
};

const exportScene = async ({ elements, appState, files }, opts = {}) => {
  const state = {
    ...appState,
    exportBackground: opts.background !== false,
    exportEmbedScene: !!opts.embed,
    exportWithDarkMode: false,
  };
  const base = { elements, appState: state, files: files || {}, exportPadding: opts.padding ?? 10 };
  if (opts.type === "png") {
    const blob = await exportToBlob({ ...base, mimeType: "image/png", quality: 1,
                                      getDimensions: (w, h) => ({ width: w * (opts.scale || 2),
                                                                  height: h * (opts.scale || 2),
                                                                  scale: opts.scale || 2 }) });
    return { type: "png", data: await toBase64(blob) };
  }
  const svg = await exportToSvg(base);
  return { type: "svg", data: svg.outerHTML };
};

// Mermaid text -> Excalidraw elements (and files for diagrams Mermaid can
// only give as images).
const mermaidToScene = async (code, fontSize = 20) => {
  const { parseMermaidToExcalidraw } = await import("@excalidraw/mermaid-to-excalidraw");
  const { elements, files } = await parseMermaidToExcalidraw(code, { themeVariables: { fontSize: `${fontSize}px` } });
  return { elements: convertToExcalidrawElements(elements, { regenerateIds: true }), files: files || {} };
};

const elementsBounds = (els) => {
  const live = els.filter((e) => !e.isDeleted);
  if (!live.length) return null;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const e of live) {
    x0 = Math.min(x0, e.x); y0 = Math.min(y0, e.y);
    x1 = Math.max(x1, e.x + Math.abs(e.width)); y1 = Math.max(y1, e.y + Math.abs(e.height));
  }
  return { x0, y0, x1, y1 };
};

const shift = (els, dx, dy) => els.map((e) => ({ ...e, x: e.x + dx, y: e.y + dy }));

const chartIdOf = (e) => e.customData?.excalidrawer?.chart;

const handlers = {
  update(api, { scene, keepAppState }) {
    const s = parseScene(scene);
    if (s.files && Object.keys(s.files).length) api.addFiles(Object.values(s.files));
    api.updateScene({
      elements: s.elements,
      appState: keepAppState ? undefined : { viewBackgroundColor: s.appState.viewBackgroundColor },
      captureUpdate: CaptureUpdateAction.IMMEDIATELY,
    });
    api.scrollToContent(undefined, { fitToContent: true });
  },
  add(api, { scene, placement }) {
    const s = parseScene(scene);
    if (s.files && Object.keys(s.files).length) api.addFiles(Object.values(s.files));
    let els = s.elements;
    const existing = api.getSceneElements();
    if (placement === "right") {
      const a = elementsBounds(existing), b = elementsBounds(els);
      if (a && b) els = shift(els, a.x1 + 60 - b.x0, a.y0 - b.y0);
    }
    api.updateScene({ elements: [...existing, ...els], captureUpdate: CaptureUpdateAction.IMMEDIATELY });
    api.scrollToContent(els, { fitToContent: false, animate: true });
  },
  // Swap a generated chart for a new version, keeping everything drawn by hand.
  replaceChart(api, { scene, chart }) {
    const s = parseScene(scene);
    if (s.files && Object.keys(s.files).length) api.addFiles(Object.values(s.files));
    const existing = api.getSceneElements();
    const old = existing.filter((e) => chartIdOf(e) === chart);
    let els = s.elements.map((e) => ({ ...e, customData: { ...(e.customData || {}),
      excalidrawer: { ...(e.customData?.excalidrawer || {}), chart } } }));
    const a = elementsBounds(old), b = elementsBounds(els);
    if (a && b) els = shift(els, a.x0 - b.x0, a.y0 - b.y0);
    const kept = existing.filter((e) => chartIdOf(e) !== chart);
    api.updateScene({ elements: [...kept, ...els], captureUpdate: CaptureUpdateAction.IMMEDIATELY });
    if (!old.length) api.scrollToContent(undefined, { fitToContent: true });
  },
  scrollTo(api) {
    api.scrollToContent(undefined, { fitToContent: true, animate: true });
  },
  set(api, { theme, viewMode, zen, grid, background }) {
    const appState = {};
    if (theme) appState.theme = theme;
    if (viewMode !== undefined) appState.viewModeEnabled = viewMode;
    if (zen !== undefined) appState.zenModeEnabled = zen;
    if (grid !== undefined) appState.gridModeEnabled = grid;
    if (background) appState.viewBackgroundColor = background;
    api.updateScene({ appState });
  },
  reset(api) {
    api.resetScene();
  },
  async export(api, opts, id) {
    const res = await exportScene({ elements: api.getSceneElements(), appState: api.getAppState(),
                                    files: api.getFiles() }, opts);
    shinyInput(id, "export", { ...res, nonce: opts.nonce || Date.now() });
  },
  async mermaid(api, { code, fontSize }, id) {
    try {
      const s = await mermaidToScene(code, fontSize);
      handlers.add(api, { scene: { elements: s.elements, files: s.files }, placement: "right" });
      shinyInput(id, "mermaid", { ok: true, nonce: Date.now() });
    } catch (e) {
      shinyInput(id, "mermaid", { ok: false, message: String(e?.message || e), nonce: Date.now() });
    }
  },
};

if (window.Shiny && window.Shiny.addCustomMessageHandler) {
  window.Shiny.addCustomMessageHandler("excalidrawer-proxy", (msg) => {
    const api = apis.get(msg.id);
    const fn = handlers[msg.method];
    if (api && fn) fn(api, msg.args || {}, msg.id);
  });
}

function Editor({ x, id }) {
  const lastVersion = useRef(-1);
  const initialData = useMemo(() => {
    const s = parseScene(x.scene);
    return {
      elements: s.elements,
      files: s.files,
      appState: {
        ...s.appState,
        viewModeEnabled: x.mode === "view",
        zenModeEnabled: !!x.zen,
        gridModeEnabled: !!x.grid,
        theme: x.theme || "light",
      },
      scrollToContent: true,
    };
  }, []);
  const report = useMemo(() => debounce((elements, appState, files) => {
    shinyInput(id, "scene", serializeAsJSON(elements, appState, files, "local"));
    shinyInput(id, "selection", Object.keys(appState.selectedElementIds || {}));
  }, x.debounce ?? 400), []);
  const onChange = (elements, appState, files) => {
    const v = getSceneVersion(elements);
    if (v === lastVersion.current) return;
    lastVersion.current = v;
    report(elements, appState, files);
  };
  return (
    <div className="excalidrawer-editor" style={{ height: "100%", width: "100%" }}>
      <Excalidraw
        initialData={initialData}
        excalidrawAPI={(api) => {
          apis.set(id, api);
          if (window.Shiny) setTimeout(() => report(api.getSceneElements(), api.getAppState(), api.getFiles()), 0);
        }}
        onChange={onChange}
        viewModeEnabled={x.mode === "view"}
        UIOptions={{ canvasActions: { saveToActiveFile: false, loadScene: x.mode !== "view" } }}
      >
        <MainMenu>
          <MainMenu.DefaultItems.LoadScene />
          <MainMenu.DefaultItems.Export />
          <MainMenu.DefaultItems.SaveAsImage />
          <MainMenu.DefaultItems.ClearCanvas />
          <MainMenu.Separator />
          <MainMenu.DefaultItems.ToggleTheme />
          <MainMenu.DefaultItems.ChangeCanvasBackground />
        </MainMenu>
      </Excalidraw>
    </div>
  );
}

const roots = new WeakMap();

const render = (el, x) => {
  const id = el.id;
  let root = roots.get(el);
  if (root) root.unmount();
  el.style.position = el.style.position || "relative";
  root = createRoot(el);
  roots.set(el, root);
  root.render(<Editor x={x} id={id} />);
  return root;
};

// Headless helpers for R (via chromote).
window.excalidrawerHeadless = {
  async mermaid(code, fontSize) {
    const s = await mermaidToScene(code, fontSize);
    return JSON.stringify({ type: "excalidraw", version: 2, source: "excalidrawer",
                            elements: s.elements, appState: {}, files: s.files });
  },
  async export(sceneJson, opts) {
    const s = parseScene(sceneJson);
    return exportScene(s, opts);
  },
};

if (window.__excalidrawerResolve) window.__excalidrawerResolve({ render });
window.excalidrawerLib = { render };
