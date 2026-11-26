// mount(el, opts): puts an Excalidraw editor in an element and hands back a
// controller. The R htmlwidget, the standalone site and denr's Sketch panel
// all go through this one function.
import React, { useMemo } from "react";
import { createRoot } from "react-dom/client";
import {
  Excalidraw,
  MainMenu,
  CaptureUpdateAction,
  getSceneVersion,
  restore,
  serializeAsJSON,
} from "@excalidraw/excalidraw";
import { sceneData, placeRight, swapChart, debounce } from "./scene.js";
import { exportScene } from "./export.js";
import { mermaidToScene } from "./mermaid.js";

/** Scene JSON (text or object) -> { elements, appState, files }, repaired by Excalidraw. */
export const parseScene = (scene) => restore(sceneData(scene), null, null);

function Editor({ opts, ctrl, onApi, onChange }) {
  const initialData = useMemo(() => {
    const s = parseScene(opts.scene);
    return {
      elements: s.elements,
      files: s.files,
      appState: {
        ...s.appState,
        viewModeEnabled: opts.mode === "view",
        zenModeEnabled: !!opts.zen,
        gridModeEnabled: !!opts.grid,
        theme: opts.theme || "light",
      },
      libraryItems: opts.libraryItems,
      scrollToContent: true,
    };
  }, []);
  return (
    <div className="excalidrawer-editor" style={{ height: "100%", width: "100%" }}>
      <Excalidraw
        initialData={initialData}
        excalidrawAPI={(api) => api && onApi(api)}
        onChange={onChange}
        viewModeEnabled={opts.mode === "view"}
        langCode={opts.langCode}
        UIOptions={{ canvasActions: { saveToActiveFile: false, loadScene: opts.mode !== "view", ...(opts.canvasActions || {}) } }}
      >
        <MainMenu>
          {opts.menuItems ? opts.menuItems(ctrl) : null}
          <MainMenu.DefaultItems.LoadScene />
          <MainMenu.DefaultItems.Export />
          <MainMenu.DefaultItems.SaveAsImage />
          <MainMenu.DefaultItems.ClearCanvas />
          <MainMenu.Separator />
          <MainMenu.DefaultItems.ToggleTheme />
          <MainMenu.DefaultItems.ChangeCanvasBackground />
        </MainMenu>
        {opts.extras ? opts.extras(ctrl) : null}
      </Excalidraw>
    </div>
  );
}

const mounted = new WeakMap();

/**
 * opts: { scene, mode: "edit" | "view", theme: "light" | "dark", zen, grid,
 *         libraryItems, langCode, canvasActions, debounce (ms, default 400),
 *         onChange(json, { elements, appState, files }), onSelection(ids),
 *         extras(ctrl) and menuItems(ctrl): extra React content }.
 * Methods that change the scene wait for the editor to be ready, so they can
 * be called straight away.
 */
export function mount(el, opts = {}) {
  mounted.get(el)?.destroy();
  let api = null;
  let resolveReady;
  const ready = new Promise((resolve) => { resolveReady = resolve; });
  const listeners = new Set(opts.onChange ? [opts.onChange] : []);
  let lastVersion = -1;

  const report = debounce((elements, appState, files) => {
    if (listeners.size) {
      const json = serializeAsJSON(elements, appState, files, "local");
      for (const fn of listeners) fn(json, { elements, appState, files });
    }
    opts.onSelection?.(Object.keys(appState.selectedElementIds || {}));
  }, opts.debounce ?? 400);

  const onChange = (elements, appState, files) => {
    const v = getSceneVersion(elements);
    if (v === lastVersion) return;
    lastVersion = v;
    report(elements, appState, files);
  };

  const when = (fn) => async (...args) => { await ready; return fn(...args); };
  const addFiles = (s) => { if (s.files && Object.keys(s.files).length) api.addFiles(Object.values(s.files)); };

  const ctrl = {
    el,
    ready,
    get api() { return api; },
    /** { elements, appState, files } as the editor has them now. */
    getSceneData() {
      if (!api) return null;
      return { elements: api.getSceneElements(), appState: api.getAppState(), files: api.getFiles() };
    },
    /** The scene as .excalidraw JSON text. */
    getScene() {
      const d = ctrl.getSceneData();
      return d && serializeAsJSON(d.elements, d.appState, d.files, "local");
    },
    /** Replaces the drawing (keepAppState keeps background, zoom and so on). */
    setScene: when((scene, { keepAppState = false } = {}) => {
      const s = parseScene(scene);
      addFiles(s);
      api.updateScene({
        elements: s.elements,
        appState: keepAppState ? undefined : { viewBackgroundColor: s.appState.viewBackgroundColor },
        captureUpdate: CaptureUpdateAction.IMMEDIATELY,
      });
      api.scrollToContent(undefined, { fitToContent: true });
    }),
    /** Adds elements; placement "right" puts them beside the drawing. Returns the new elements. */
    add: when((scene, { placement } = {}) => {
      const s = parseScene(scene);
      addFiles(s);
      const existing = api.getSceneElements();
      const els = placement === "right" ? placeRight(existing, s.elements) : s.elements;
      api.updateScene({ elements: [...existing, ...els], captureUpdate: CaptureUpdateAction.IMMEDIATELY });
      api.scrollToContent(els, { fitToContent: false, animate: true });
      return els;
    }),
    /** Swaps a generated chart for a new version, keeping everything drawn by hand. */
    replaceChart: when((scene, chart) => {
      const s = parseScene(scene);
      addFiles(s);
      const { elements, hadOld } = swapChart(api.getSceneElements(), s.elements, chart);
      api.updateScene({ elements, captureUpdate: CaptureUpdateAction.IMMEDIATELY });
      if (!hadOld) api.scrollToContent(undefined, { fitToContent: true });
    }),
    scrollTo: when(() => api.scrollToContent(undefined, { fitToContent: true, animate: true })),
    set: when(({ theme, viewMode, zen, grid, background } = {}) => {
      const appState = {};
      if (theme) appState.theme = theme;
      if (viewMode !== undefined) appState.viewModeEnabled = viewMode;
      if (zen !== undefined) appState.zenModeEnabled = zen;
      if (grid !== undefined) appState.gridModeEnabled = grid;
      if (background) appState.viewBackgroundColor = background;
      api.updateScene({ appState });
    }),
    reset: when(() => api.resetScene()),
    /** See exportScene() for opts. */
    export: when((o = {}) => exportScene(ctrl.getSceneData(), o)),
    /** Converts Mermaid text and adds it beside the drawing. Throws if Mermaid can't read it. */
    mermaid: when(async (code, { fontSize = 20, placement = "right" } = {}) => {
      const s = await mermaidToScene(code, fontSize);
      return ctrl.add({ elements: s.elements, files: s.files }, { placement });
    }),
    /** Call after the editor's element moved or was resized while hidden. */
    refresh() { api?.refresh(); },
    onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    destroy() {
      report.cancel();
      listeners.clear();
      root.unmount();
      mounted.delete(el);
      if (el.excalidrawer === ctrl) delete el.excalidrawer;
    },
  };

  let seen = false;
  const onApi = (a) => {
    if (seen) return;
    seen = true;
    api = a;
    // Let the editor finish its first render before anything changes the scene.
    setTimeout(() => resolveReady(ctrl), 50);
  };

  if (!el.style.position) el.style.position = "relative";
  const root = createRoot(el);
  root.render(<Editor opts={opts} ctrl={ctrl} onApi={onApi} onChange={onChange} />);
  mounted.set(el, ctrl);
  el.excalidrawer = ctrl;
  return ctrl;
}
