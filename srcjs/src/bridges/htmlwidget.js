// The R htmlwidget and Shiny proxy, on top of mount(). Messages from
// excalidraw_proxy() arrive as { id, method, args }; results go back as
// input$<id>_scene, _selection, _export and _mermaid.
import { mount } from "../core/mount.jsx";

const ctrls = new Map();
// Messages that arrive before their editor exists wait here.
const pending = new Map();

const shinyInput = (id, name, value) => {
  if (window.Shiny && window.Shiny.setInputValue && id) {
    window.Shiny.setInputValue(`${id}_${name}`, value, { priority: "event" });
  }
};

const methods = {
  update: (c, { scene, keepAppState }) => c.setScene(scene, { keepAppState }),
  add: (c, { scene, placement }) => c.add(scene, { placement }),
  replaceChart: (c, { scene, chart }) => c.replaceChart(scene, chart),
  scrollTo: (c) => c.scrollTo(),
  set: (c, args) => c.set(args),
  reset: (c) => c.reset(),
  async export(c, opts, id) {
    const res = await c.export(opts);
    shinyInput(id, "export", { ...res, nonce: opts.nonce || Date.now() });
  },
  async mermaid(c, { code, fontSize }, id) {
    try {
      await c.mermaid(code, { fontSize });
      shinyInput(id, "mermaid", { ok: true, nonce: Date.now() });
    } catch (e) {
      shinyInput(id, "mermaid", { ok: false, message: String(e?.message || e), nonce: Date.now() });
    }
  },
};

const dispatch = (msg) => {
  const fn = methods[msg.method];
  if (!fn) return;
  const c = ctrls.get(msg.id);
  if (!c) {
    if (!pending.has(msg.id)) pending.set(msg.id, []);
    pending.get(msg.id).push(msg);
    return;
  }
  fn(c, msg.args || {}, msg.id);
};

if (window.Shiny && window.Shiny.addCustomMessageHandler) {
  window.Shiny.addCustomMessageHandler("excalidrawer-proxy", dispatch);
}

/** renderValue() of the htmlwidget binding (inst/htmlwidgets/excalidraw.js). */
export function render(el, x) {
  const id = el.id;
  const c = mount(el, {
    scene: x.scene, mode: x.mode, theme: x.theme, zen: x.zen, grid: x.grid, debounce: x.debounce,
    onChange: (json) => shinyInput(id, "scene", json),
    onSelection: (ids) => shinyInput(id, "selection", ids),
  });
  ctrls.set(id, c);
  const queued = pending.get(id) || [];
  pending.delete(id);
  queued.forEach(dispatch);
  c.ready.then(() => {
    if (!window.Shiny) return;
    shinyInput(id, "scene", c.getScene());
    shinyInput(id, "selection", Object.keys(c.api.getAppState().selectedElementIds || {}));
  });
  return c;
}

window.excalidrawerLib = { render };
if (window.__excalidrawerResolve) window.__excalidrawerResolve({ render });
