// Scene helpers that need nothing from Excalidraw itself, so they run (and are
// tested) in plain Node.

/** A scene given as JSON text or an object, as Excalidraw's restore() wants it. */
export function sceneData(scene) {
  const data = typeof scene === "string" ? (scene.trim() ? JSON.parse(scene) : {}) : scene || {};
  return { type: "excalidraw", elements: [], ...data };
}

export const chartIdOf = (e) => e?.customData?.scratchy?.chart;

/** Bounding box of the elements that are not deleted, or null. */
export function elementsBounds(els) {
  const live = (els || []).filter((e) => !e.isDeleted);
  if (!live.length) return null;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const e of live) {
    x0 = Math.min(x0, e.x); y0 = Math.min(y0, e.y);
    x1 = Math.max(x1, e.x + Math.abs(e.width || 0)); y1 = Math.max(y1, e.y + Math.abs(e.height || 0));
  }
  return { x0, y0, x1, y1 };
}

export const shift = (els, dx, dy) => els.map((e) => ({ ...e, x: e.x + dx, y: e.y + dy }));

/** Moves new elements to sit `gap` px to the right of the existing drawing, tops aligned. */
export function placeRight(existing, incoming, gap = 60) {
  const a = elementsBounds(existing), b = elementsBounds(incoming);
  return a && b ? shift(incoming, a.x1 + gap - b.x0, a.y0 - b.y0) : incoming;
}

/**
 * Swaps the elements of one generated chart (tagged customData.scratchy.chart)
 * for a new version in the same place, keeping everything else.
 */
export function swapChart(existing, incoming, chart) {
  const old = existing.filter((e) => chartIdOf(e) === chart);
  let els = incoming.map((e) => ({
    ...e,
    customData: { ...(e.customData || {}), scratchy: { ...(e.customData?.scratchy || {}), chart } },
  }));
  const a = elementsBounds(old), b = elementsBounds(els);
  if (a && b) els = shift(els, a.x0 - b.x0, a.y0 - b.y0);
  const kept = existing.filter((e) => chartIdOf(e) !== chart);
  return { elements: [...kept, ...els], hadOld: old.length > 0 };
}

export function bytesToBase64(bytes) {
  let bin = "";
  const step = 0x8000;
  for (let i = 0; i < bytes.length; i += step) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + step));
  return btoa(bin);
}

export function debounce(fn, ms) {
  let t = null;
  const d = (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
  d.cancel = () => clearTimeout(t);
  return d;
}
