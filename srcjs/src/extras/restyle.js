// The R package's style presets (exc_preset(), exc_restyle()) for the editor.
// presets.json is written from R by data-raw/extras-json.R.
import table from "./presets.json" with { type: "json" };

export const presets = table.presets;
export const fonts = table.fonts;

function luminance(col) {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(col || "");
  if (!m) return null;
  let h = m[1];
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
const transparent = (c) => !c || c === "transparent" || /^#[0-9a-f]{6}00$/i.test(c);
const isDark = (c) => !transparent(c) && (luminance(c) ?? 1) < 0.3;

/**
 * Applies a preset to elements, as exc_restyle() does in R: dark strokes take
 * the preset's ink, shapes its sloppiness, stroke width and fill style, text
 * its font. Returns { elements, background, textChanged } and changes nothing
 * in place; text elements need their size refreshed afterwards.
 */
export function restyleElements(elements, name, ids = null) {
  const p = presets[name];
  if (!p) throw new Error(`Unknown preset: ${name}`);
  const pick = ids ? (e) => ids.has(e.id) : () => true;
  const out = elements.map((e) => {
    if (e.isDeleted || !pick(e) || ["frame", "magicframe", "image"].includes(e.type)) return e;
    const n = { ...e };
    if (isDark(n.strokeColor)) n.strokeColor = p.ink;
    if (n.type === "text") {
      n.fontFamily = p.fontFamily;
      const ex = { ...(n.customData?.excalidrawer || {}) };
      if (p.customFont) ex.font = p.customFont; else delete ex.font;
      n.customData = { ...(n.customData || {}), excalidrawer: ex };
      if (!Object.keys(ex).length) delete n.customData.excalidrawer;
      return n;
    }
    n.roughness = p.roughness;
    if (n.type !== "freedraw") n.strokeWidth = p.strokeWidth;
    const small = n.type === "ellipse" && Math.max(n.width, n.height) < 16;
    if (!transparent(n.backgroundColor) && !small) n.fillStyle = p.fillStyle;
    return n;
  });
  return { elements: out, background: p.background, textChanged: out.some((e, i) => e !== elements[i] && e.type === "text") };
}

/** Sets one style property on elements (all, or the ids given). */
export function setStyle(elements, prop, value, ids = null) {
  return elements.map((e) => (e.isDeleted || (ids && !ids.has(e.id)) || !(prop in e) ? e : { ...e, [prop]: value }));
}
