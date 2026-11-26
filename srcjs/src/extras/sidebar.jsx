// The scratchy sidebar: stickers, people, style presets, Mermaid and
// exports (animated SVG, Obsidian), inside Excalidraw's own Sidebar.
import React, { useEffect, useState } from "react";
import { Sidebar, CaptureUpdateAction, exportToSvg, restoreElements } from "@excalidraw/excalidraw";
import { presets, restyleElements } from "./restyle.js";
import { animateSvg } from "./animate.js";
import { toObsidian } from "./obsidian.js";
import { stickerIndex, stickerLibrary, peepOptions, peepSvg, svgImageScene } from "./assets.js";

export const SIDEBAR = "scratchy";

const CSS = `
.exr-pane{padding:.25rem .75rem 1rem;display:flex;flex-direction:column;gap:.6rem;overflow:auto;font-size:.875rem;color:var(--text-primary-color)}
.exr-pane h4{margin:.5rem 0 0;font-size:.8rem;text-transform:uppercase;letter-spacing:.04em;color:var(--color-gray-60,#868e96)}
.exr-row{display:flex;gap:.4rem;align-items:center;flex-wrap:wrap}
.exr-pane button{font:inherit;padding:.35rem .6rem;border-radius:.5rem;border:1px solid var(--default-border-color,#ced4da);background:var(--island-bg-color,#fff);color:inherit;cursor:pointer}
.exr-pane button:hover{background:var(--button-hover-bg,#f1f0ff)}
.exr-pane button.exr-primary{background:var(--color-primary,#6965db);color:#fff;border-color:transparent}
.exr-pane select,.exr-pane input[type=text],.exr-pane input[type=number],.exr-pane textarea{font:inherit;padding:.3rem .4rem;border-radius:.4rem;border:1px solid var(--default-border-color,#ced4da);background:var(--input-bg-color,#fff);color:inherit;min-width:0}
.exr-pane textarea{width:100%;min-height:8rem;font-family:var(--ui-font-mono,monospace);font-size:.8rem;box-sizing:border-box}
.exr-list{display:flex;flex-direction:column;gap:.35rem}
.exr-item{display:flex;justify-content:space-between;gap:.5rem;align-items:center}
.exr-item small{display:block;color:var(--color-gray-60,#868e96)}
.exr-msg{font-size:.8rem;color:var(--color-gray-60,#868e96)}
.exr-msg.exr-err{color:var(--color-danger,#e03131)}
.exr-presets{display:grid;grid-template-columns:1fr 1fr;gap:.4rem}
.exr-sidebar .sidebar-triggers{display:flex;flex-wrap:wrap;gap:.25rem;flex:1}
.exr-sidebar .sidebar-tab-trigger{font-size:.8rem;height:auto;padding:.3rem .55rem;width:auto}
`;
let styled = false;
function injectCss() {
  if (styled || typeof document === "undefined") return;
  styled = true;
  const s = document.createElement("style");
  s.textContent = CSS;
  document.head.append(s);
}

export function defaultDownload(name, blob) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

const selectedIds = (api) => {
  const ids = new Set(Object.keys(api.getAppState().selectedElementIds || {}));
  if (!ids.size) return null;
  for (const e of api.getSceneElements()) if (e.containerId && ids.has(e.containerId)) ids.add(e.id);
  return ids;
};

function Stickers({ ctrl, base }) {
  const [libs, setLibs] = useState(null);
  const [msg, setMsg] = useState("");
  useEffect(() => { stickerIndex(base).then(setLibs, (e) => setMsg(e.message)); }, [base]);
  const add = async (lib) => {
    try {
      await ctrl.api.updateLibrary({ libraryItems: stickerLibrary(base, lib.file), merge: true, openLibraryMenu: true });
    } catch (e) { setMsg(e.message); }
  };
  return (
    <div className="exr-pane">
      <div className="exr-msg">Add a library, then drag its stickers from the Library onto the canvas.</div>
      {msg && <div className="exr-msg exr-err">{msg}</div>}
      <div className="exr-list">
        {(libs || []).map((lib) => (
          <div className="exr-item" key={lib.library}>
            <span>{lib.title}<small>{lib.author}</small></span>
            <button onClick={() => add(lib)}>Add</button>
          </div>
        ))}
      </div>
    </div>
  );
}

function People({ ctrl }) {
  const [opts, setOpts] = useState(null);
  const [seed, setSeed] = useState("Ada");
  const [face, setFace] = useState("");
  const [head, setHead] = useState("");
  const [clothing, setClothing] = useState("#a5d8ff");
  const [msg, setMsg] = useState("");
  useEffect(() => { peepOptions().then(setOpts, (e) => setMsg(e.message)); }, []);
  const add = async () => {
    try {
      const o = { seed, size: 160, clothingColor: [clothing.replace("#", "")] };
      if (face) o.face = [face];
      if (head) o.head = [head];
      const svg = await peepSvg(o);
      await ctrl.add(svgImageScene(svg, { width: 160, height: 160 }), { placement: "right" });
      setMsg("");
    } catch (e) { setMsg(e.message); }
  };
  const pick = (label, value, set, choices) => (
    <label className="exr-row">{label}
      <select value={value} onChange={(e) => set(e.target.value)}>
        <option value="">any</option>
        {(choices || []).map((c) => <option key={c} value={c}>{c}</option>)}
      </select>
    </label>
  );
  return (
    <div className="exr-pane">
      <div className="exr-msg">Hand-drawn people in Pablo Stanley's Open Peeps style. Each name is a different person.</div>
      <label className="exr-row">Name <input type="text" value={seed} onChange={(e) => setSeed(e.target.value)} />
        <button onClick={() => setSeed(Math.random().toString(36).slice(2, 7))} title="Someone new">↻</button></label>
      {pick("Face", face, setFace, opts?.face)}
      {pick("Head", head, setHead, opts?.head)}
      <label className="exr-row">Clothing <input type="color" value={clothing} onChange={(e) => setClothing(e.target.value)} /></label>
      <div className="exr-row"><button className="exr-primary" onClick={add}>Add person</button></div>
      {msg && <div className="exr-msg exr-err">{msg}</div>}
    </div>
  );
}

function Style({ ctrl }) {
  const [msg, setMsg] = useState("");
  const apply = (name) => {
    const api = ctrl.api;
    const ids = selectedIds(api);
    const r = restyleElements(api.getSceneElements(), name, ids);
    const elements = r.textChanged ? restoreElements(r.elements, null, { refreshDimensions: true }) : r.elements;
    api.updateScene({ elements, appState: ids ? undefined : { viewBackgroundColor: r.background },
                      captureUpdate: CaptureUpdateAction.IMMEDIATELY });
    setMsg(`${name} applied to ${ids ? "the selection" : "the whole drawing"}.`);
  };
  return (
    <div className="exr-pane">
      <div className="exr-msg">The presets of the R package. They apply to the selection, or to everything when nothing is selected.</div>
      <div className="exr-presets">
        {Object.keys(presets).map((n) => <button key={n} onClick={() => apply(n)}>{n}</button>)}
      </div>
      {msg && <div className="exr-msg">{msg}</div>}
    </div>
  );
}

function Mermaid({ ctrl }) {
  const [code, setCode] = useState("flowchart LR\n  Data --> Sketch --> Share");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const run = async () => {
    setBusy(true);
    try { const els = await ctrl.mermaid(code); setMsg(`Added ${els.length} elements.`); }
    catch (e) { setMsg(`Mermaid could not read that: ${e.message}`); }
    finally { setBusy(false); }
  };
  return (
    <div className="exr-pane">
      <div className="exr-msg">Flowcharts, sequence and class diagrams become editable shapes; other diagram types come in as an image.</div>
      <textarea value={code} spellCheck={false} onChange={(e) => setCode(e.target.value)} />
      <div className="exr-row"><button className="exr-primary" disabled={busy} onClick={run}>{busy ? "Converting…" : "Add to drawing"}</button></div>
      {msg && <div className={`exr-msg${msg.startsWith("Mermaid") ? " exr-err" : ""}`}>{msg}</div>}
    </div>
  );
}

function Export({ ctrl, cfg }) {
  const [duration, setDuration] = useState(5);
  const [loop, setLoop] = useState(false);
  const [msg, setMsg] = useState("");
  const download = cfg.download || defaultDownload;
  const base = () => (cfg.fileName ? cfg.fileName() : "drawing");
  const go = (fn) => async () => { try { setMsg(""); await fn(); } catch (e) { setMsg(e.message); } };
  const animated = go(async () => {
    const d = ctrl.getSceneData();
    const svg = await exportToSvg({ elements: d.elements, appState: { ...d.appState, exportBackground: true }, files: d.files, exportPadding: 10 });
    const text = animateSvg(svg, { duration: Number(duration) || 5, loop });
    await download(`${base()}.svg`, new Blob([text], { type: "image/svg+xml" }), { kind: "animated-svg" });
  });
  return (
    <div className="exr-pane">
      <h4>Images</h4>
      <div className="exr-row">
        <button onClick={go(async () => download(`${base()}.png`, await ctrl.export({ type: "png", as: "blob" }), { kind: "png" }))}>PNG</button>
        <button onClick={go(async () => download(`${base()}.svg`, await ctrl.export({ type: "svg", as: "blob" }), { kind: "svg" }))}>SVG</button>
        <button title="An SVG that opens again as an editable drawing"
                onClick={go(async () => download(`${base()}.excalidraw.svg`, await ctrl.export({ type: "svg", as: "blob", embed: true }), { kind: "svg" }))}>Editable SVG</button>
      </div>
      <h4>A drawing that draws itself</h4>
      <label className="exr-row">Seconds <input type="number" min="1" max="60" value={duration} onChange={(e) => setDuration(e.target.value)} style={{ width: "4rem" }} /></label>
      <label className="exr-row"><input type="checkbox" checked={loop} onChange={(e) => setLoop(e.target.checked)} /> Loop</label>
      <div className="exr-row"><button className="exr-primary" onClick={animated}>Animated SVG</button></div>
      <h4>Files</h4>
      <div className="exr-row">
        <button onClick={go(() => download(`${base()}.excalidraw`, new Blob([ctrl.getScene()], { type: "application/json" }), { kind: "excalidraw" }))}>.excalidraw</button>
        <button title="For Obsidian's Excalidraw plugin"
                onClick={go(() => download(`${base()}.excalidraw.md`, new Blob([toObsidian(ctrl.getScene())], { type: "text/markdown" }), { kind: "obsidian" }))}>Obsidian .md</button>
      </div>
      {msg && <div className="exr-msg exr-err">{msg}</div>}
    </div>
  );
}

const icon = (
  <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M4 20c2-1 3.5-3.5 5-6.5S12 6 15 4c1.5-1 3.5-.5 4 1s-.5 3-2 4c-2.5 1.5-6 2-8.5 4.5" />
    <path d="M14 17.5l1.6 1.6 3.4-3.6" />
  </svg>
);

export function ExtrasTrigger({ cfg = {} }) {
  return <Sidebar.Trigger name={SIDEBAR} tab={cfg.stickers ? "stickers" : "people"}
                          title="scratchy: stickers, people, styles, Mermaid, exports" icon={icon} />;
}

/** cfg: { stickers: base URL of the sticker libraries (or false), download(name, blob, info), fileName() }. */
export function ExtrasSidebar({ ctrl, cfg = {} }) {
  injectCss();
  const tabs = [
    cfg.stickers !== false && cfg.stickers ? ["stickers", "Stickers"] : null,
    ["people", "People"], ["style", "Style"], ["mermaid", "Mermaid"], ["export", "Export"],
  ].filter(Boolean);
  return (
    <Sidebar name={SIDEBAR} className="exr-sidebar">
      <Sidebar.Tabs className="exr-tabs">
        <Sidebar.Header>
          <Sidebar.TabTriggers>
            {tabs.map(([t, label]) => <Sidebar.TabTrigger key={t} tab={t}>{label}</Sidebar.TabTrigger>)}
          </Sidebar.TabTriggers>
        </Sidebar.Header>
        {cfg.stickers ? <Sidebar.Tab tab="stickers"><Stickers ctrl={ctrl} base={cfg.stickers} /></Sidebar.Tab> : null}
        <Sidebar.Tab tab="people"><People ctrl={ctrl} /></Sidebar.Tab>
        <Sidebar.Tab tab="style"><Style ctrl={ctrl} /></Sidebar.Tab>
        <Sidebar.Tab tab="mermaid"><Mermaid ctrl={ctrl} /></Sidebar.Tab>
        <Sidebar.Tab tab="export"><Export ctrl={ctrl} cfg={cfg} /></Sidebar.Tab>
      </Sidebar.Tabs>
    </Sidebar>
  );
}
