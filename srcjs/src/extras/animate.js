// Self-drawing SVGs from the editor, with the timing R's exc_animate() uses:
// each element gets a slot in z-order as long as the work it does (plus a
// little), outlines are traced with stroke-dashoffset, fills fade in once the
// outline is done, text appears line by line. Viewers who ask for reduced
// motion, and programs without CSS animation, see the finished drawing.
//
// It works on Excalidraw's own SVG export, so the strokes are the editor's.

const SKIP = new Set(["defs", "metadata", "style", "title", "desc"]);
const LEAVES = "path,line,polyline,polygon,ellipse,circle,rect,text,image,use,foreignObject";
const num = (x, d = 2) => String(Math.round(x * 10 ** d) / 10 ** d);

/** Splits an element's pieces into draw / after / write / fade phases. */
function pieces(unit) {
  const leaves = unit.matches?.(LEAVES) ? [unit] : [...unit.querySelectorAll(LEAVES)];
  const out = [];
  const strokes = [];
  for (const node of leaves) {
    if (node.closest("text") && node.tagName !== "text") continue;
    const tag = node.tagName.toLowerCase();
    if (tag === "text") {
      out.push({ node, phase: "write", prop: "opacity", len: Math.max(8, 8 * (node.textContent || "").length) });
      continue;
    }
    if (tag === "image" || tag === "use" || tag === "foreignobject") { out.push({ node, phase: "fade", prop: "opacity", len: 0 }); continue; }
    const cs = getComputedStyle(node);
    const stroked = cs.stroke && cs.stroke !== "none" && parseFloat(cs.strokeWidth || "1") > 0;
    const filled = cs.fill && cs.fill !== "none";
    if (stroked && !filled) {
      let len = 0;
      try { len = node.getTotalLength(); } catch { /* not a geometry element */ }
      const p = { node, phase: "draw", prop: "stroke-dashoffset", len, color: cs.stroke };
      strokes.push(p);
      out.push(p);
    } else {
      out.push({ node, phase: "after", prop: filled ? "fill-opacity" : "opacity", len: 0 });
    }
  }
  // rough.js draws a hachure fill as strokes in the fill colour before the
  // outline: those fade in with the fill instead of being traced.
  const outline = strokes.length ? strokes[strokes.length - 1].color : null;
  for (const p of strokes) if (p.color !== outline) { p.phase = "after"; p.prop = "stroke-opacity"; }
  return out;
}

function timePieces(ps, s, e, fade, duration) {
  const drawn = ps.filter((p) => p.phase === "draw");
  const written = ps.filter((p) => p.phase === "write");
  if (!drawn.length && !written.length) ps.forEach((p) => { if (p.phase === "after") p.phase = "fade"; });
  const dl = drawn.reduce((a, p) => a + p.len, 0);
  const wl = written.reduce((a, p) => a + p.len, 0);
  const m = !written.length ? e : !drawn.length ? s : s + (e - s) * (dl + wl > 0 ? dl / (dl + wl) : 0.5);
  if (drawn.length) {
    const tot = dl || drawn.length;
    let acc = 0;
    for (const p of drawn) { p.a = s + (m - s) * acc / tot; acc += dl ? p.len : 1; p.b = s + (m - s) * acc / tot; }
  }
  if (written.length) {
    const n = written.length;
    const each = Math.min(e - m, Math.max(3 * (e - m) / n, 0.05));
    written.forEach((p, i) => { p.a = m + (e - m - each) * i / Math.max(1, n - 1); p.b = p.a + each; });
  }
  for (const p of ps) {
    if (p.phase === "fade") { p.a = s; p.b = Math.min(duration, Math.max(e, s + fade)); }
    if (p.phase === "after") { p.a = e; p.b = Math.min(duration, e + fade); }
  }
}

function keyframes(name, a, b, prop, hidden) {
  a = Math.round(10000 * a) / 100;
  b = Math.max(Math.round(10000 * b) / 100, a + 0.01);
  if (b > 100) { a = 99.99; b = 100; }
  const shown = prop === "stroke-dashoffset" ? "0" : "1";
  return `@keyframes ${name}{${a === 0 ? "0%" : `0%,${num(a)}%`}{${prop}:${num(hidden)}}${num(b)}%{${prop}:${shown}}}`;
}

/**
 * svg: an SVG element from exportToSvg(). opts: { duration (s, 5), loop
 * (false), hold (s the finished drawing stays before a loop restarts, 2) }.
 * Returns the animated SVG as text.
 */
export function animateSvg(svg, { duration = 5, loop = false, hold = 2 } = {}) {
  const clone = svg.cloneNode(true);
  const host = document.createElement("div");
  host.style.cssText = "position:fixed;left:-100000px;top:0;visibility:hidden;pointer-events:none";
  host.append(clone);
  document.body.append(host);
  try {
    const prefix = "x" + Math.random().toString(36).slice(2, 7);
    let sawGroup = false;
    const units = [];
    for (const child of [...clone.children]) {
      const tag = child.tagName.toLowerCase();
      if (SKIP.has(tag)) continue;
      // The background rectangle comes before the first element and stays put.
      if (tag === "rect" && !sawGroup) continue;
      sawGroup = true;
      const ps = pieces(child);
      if (ps.length) units.push(ps);
    }
    const fade = Math.min(Math.max(duration * 0.06, 0.1), 0.5, duration / 3);
    const weights = units.map((ps) => ps.reduce((a, p) => a + (p.phase === "after" ? 0 : p.len), 0) + 40);
    const total = weights.reduce((a, w) => a + w, 0) || 1;
    let acc = 0;
    units.forEach((ps, i) => {
      const s = (duration - fade) * acc / total;
      acc += weights[i];
      timePieces(ps, s, (duration - fade) * acc / total, fade, duration);
    });
    const cycle = loop ? duration + hold : duration;
    const css = [
      `.${prefix}-a{animation:${num(cycle, 3)}s linear ${loop ? "infinite" : "1"} both}`,
      `@media (prefers-reduced-motion:reduce){.${prefix}-a{animation:none!important}}`,
    ];
    let k = 0;
    for (const ps of units) for (const p of ps) {
      const name = `${prefix}-k${++k}`;
      let hidden = 0;
      if (p.phase === "draw") {
        const len = Math.max(p.len, 0.01);
        p.node.setAttribute("stroke-dasharray", `${num(len)} ${num(len)}`);
        hidden = len;
      }
      css.push(keyframes(name, p.a / cycle, p.b / cycle, p.prop, hidden));
      p.node.classList.add(`${prefix}-a`);
      p.node.style.animationName = name;
    }
    if (loop) {
      const out = Math.min(0.5, hold / 2);
      if (out > 0) {
        css.push(`@keyframes ${prefix}-out{0%,${num(100 * (cycle - out) / cycle)}%{opacity:1}100%{opacity:0}}`);
        const wrap = document.createElementNS("http://www.w3.org/2000/svg", "g");
        wrap.setAttribute("class", `${prefix}-a`);
        wrap.setAttribute("style", `animation-name:${prefix}-out`);
        for (const child of [...clone.children]) {
          const tag = child.tagName.toLowerCase();
          if (!SKIP.has(tag) && !(tag === "rect" && child === clone.querySelector(":scope > rect"))) wrap.append(child);
        }
        clone.append(wrap);
      }
    }
    const style = document.createElementNS("http://www.w3.org/2000/svg", "style");
    style.textContent = css.join("\n");
    clone.insertBefore(style, clone.firstChild);
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + new XMLSerializer().serializeToString(clone);
  } finally {
    host.remove();
  }
}
