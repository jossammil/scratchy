// RevealSketchy: hand-drawn annotations and boxes for reveal.js, drawn with
// rough.js (the engine behind Excalidraw).
//
//   [word]{.rn-underline}   [word]{.rn-circle}   [word]{.rn-box}
//   [word]{.rn-highlight}   [word]{.rn-strike}   [word]{.rn-cross}
//   [word]{.rn-bracket}     add .fragment to reveal one on click
//   ::: {.sketch-box}  ...  :::     (data-fill="#a5d8ff" for a hachure fill)
//
// Positions are measured in unscaled slide coordinates, so annotations stay
// in place however reveal.js scales the slide.
window.RevealSketchy = (function () {
  "use strict";
  var SVG_NS = "http://www.w3.org/2000/svg";
  var COLORS = { underline: "#e03131", circle: "#e03131", box: "#e03131", highlight: "#ffd43b",
                 strike: "#e03131", cross: "#e03131", bracket: "#1971c2" };
  var deck = null;

  function hash(s) {
    var h = 7;
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 2147483647;
    return h || 1;
  }

  function slideOf(el) {
    return el.closest("section");
  }

  // Rectangles of an element's text (one per line when it wraps) in the
  // slide's own, unscaled coordinates. A Range measures the text itself, so
  // block elements such as headings aren't measured edge to edge.
  function rectsIn(el, slide) {
    var scale = deck.getScale ? deck.getScale() : 1;
    var base = slide.getBoundingClientRect();
    var range = document.createRange();
    range.selectNodeContents(el);
    var list = range.getClientRects();
    if (!list.length) list = el.getClientRects();
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var r = list[i];
      if (r.width < 1 || r.height < 1) continue;
      var box = { x: (r.left - base.left) / scale, y: (r.top - base.top) / scale,
                  w: r.width / scale, h: r.height / scale };
      // merge fragments of the same line
      var last = out[out.length - 1];
      if (last && Math.abs(last.y - box.y) < 2 && Math.abs(last.h - box.h) < 2 && box.x <= last.x + last.w + 6) {
        var x1 = Math.max(last.x + last.w, box.x + box.w);
        last.x = Math.min(last.x, box.x);
        last.w = x1 - last.x;
      } else {
        out.push(box);
      }
    }
    return out;
  }

  function overlay(slide, cls) {
    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "rn-svg " + (cls || ""));
    svg.setAttribute("width", slide.offsetWidth || 10);
    svg.setAttribute("height", slide.offsetHeight || 10);
    slide.appendChild(svg);
    return svg;
  }

  function animateIn(svg, animate) {
    var paths = svg.querySelectorAll("path");
    paths.forEach(function (p) {
      var len = p.getTotalLength ? p.getTotalLength() : 0;
      if (!animate || !len) return;
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
      p.getBoundingClientRect();
      p.style.strokeDashoffset = 0;
    });
  }

  function annotate(el, show) {
    var slide = slideOf(el);
    if (!slide) return;
    var type = null;
    el.classList.forEach(function (c) { if (c.indexOf("rn-") === 0) type = c.slice(3); });
    if (!type) return;
    if (el._rnSvg) el._rnSvg.remove();
    var color = el.getAttribute("data-color") || COLORS[type] || "#e03131";
    var seed = hash((el.textContent || "") + type);
    var svg = overlay(slide, type === "highlight" ? "rn-highlight-layer" : "");
    var rc = rough.svg(svg);
    var o = { stroke: color, strokeWidth: 2.5, roughness: 1.4, seed: seed, bowing: 1.5 };
    var rects = rectsIn(el, slide);
    var pad = 4;
    if (type === "circle" || type === "box" || type === "bracket") {
      var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      rects.forEach(function (r) { x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y); x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h); });
      rects = [{ x: x0, y: y0, w: x1 - x0, h: y1 - y0 }];
    }
    rects.forEach(function (r) {
      if (type === "underline") {
        svg.appendChild(rc.line(r.x - 2, r.y + r.h + 1, r.x + r.w + 2, r.y + r.h + 3, o));
      } else if (type === "strike") {
        svg.appendChild(rc.line(r.x - 2, r.y + r.h * 0.55, r.x + r.w + 2, r.y + r.h * 0.5, o));
      } else if (type === "cross") {
        svg.appendChild(rc.line(r.x, r.y, r.x + r.w, r.y + r.h, o));
        svg.appendChild(rc.line(r.x, r.y + r.h, r.x + r.w, r.y, o));
      } else if (type === "box") {
        svg.appendChild(rc.rectangle(r.x - pad, r.y - pad, r.w + 2 * pad, r.h + 2 * pad, o));
      } else if (type === "circle") {
        svg.appendChild(rc.ellipse(r.x + r.w / 2, r.y + r.h / 2, r.w * 1.25 + 16, r.h * 1.6 + 10,
                                   Object.assign({}, o, { roughness: 1.8 })));
      } else if (type === "highlight") {
        svg.appendChild(rc.line(r.x - 2, r.y + r.h / 2, r.x + r.w + 2, r.y + r.h / 2,
                                Object.assign({}, o, { strokeWidth: r.h * 0.85, roughness: 2.2 })));
      } else if (type === "bracket") {
        var t = 10;
        svg.appendChild(rc.linearPath([[r.x - pad + t, r.y - pad], [r.x - pad, r.y - pad], [r.x - pad, r.y + r.h + pad], [r.x - pad + t, r.y + r.h + pad]], o));
        svg.appendChild(rc.linearPath([[r.x + r.w + pad - t, r.y - pad], [r.x + r.w + pad, r.y - pad], [r.x + r.w + pad, r.y + r.h + pad], [r.x + r.w + pad - t, r.y + r.h + pad]], o));
      }
    });
    el._rnSvg = svg;
    svg.style.visibility = show ? "visible" : "hidden";
    if (show) animateIn(svg, true);
  }

  function sketchBox(el) {
    if (el._sketchSvg) el._sketchSvg.remove();
    var w = el.offsetWidth, h = el.offsetHeight;
    if (!w || !h) return;
    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "sketch-svg");
    svg.setAttribute("width", w);
    svg.setAttribute("height", h);
    el.insertBefore(svg, el.firstChild);
    var rc = rough.svg(svg);
    var o = { stroke: el.getAttribute("data-stroke") || "#1e1e1e", strokeWidth: 2, roughness: 1.2,
              seed: hash(el.textContent || "box"),
              fill: el.getAttribute("data-fill") || undefined,
              fillStyle: el.getAttribute("data-fill-style") || "hachure", hachureGap: 8 };
    if (el.classList.contains("sketch-circle")) {
      svg.appendChild(rc.ellipse(w / 2, h / 2, w, h, o));
    } else {
      svg.appendChild(rc.rectangle(2, 2, w - 4, h - 4, o));
    }
    el._sketchSvg = svg;
  }

  function prepare(slide, showAll) {
    if (!slide) return;
    slide.querySelectorAll(".sketch-box, .sketch-circle").forEach(sketchBox);
    slide.querySelectorAll("[class*='rn-']").forEach(function (el) {
      if (el.classList.contains("rn-svg")) return;
      annotate(el, showAll || !el.classList.contains("fragment") || el.classList.contains("visible"));
    });
    slide.querySelectorAll("h1.title").forEach(function (h) {
      if (!h.classList.contains("rn-underline")) {
        h.classList.add("rn-underline");
        h.setAttribute("data-color", "#e03131");
        annotate(h, true);
      }
    });
  }

  return {
    id: "RevealSketchy",
    init: function (reveal) {
      deck = reveal;
      var cfg = reveal.getConfig().excalidraw || {};
      if (cfg.paper && cfg.paper !== "plain") {
        var vp = document.querySelector(".reveal-viewport") || document.body;
        vp.classList.add("paper-" + cfg.paper);
      }
      var refresh = function () { prepare(reveal.getCurrentSlide()); };
      reveal.on("ready", function () { setTimeout(refresh, 200); });
      reveal.on("slidechanged", function () { setTimeout(refresh, 50); });
      reveal.on("resize", refresh);
      // Printing (?print-pdf) lays every slide out again: redraw them all.
      reveal.on("pdf-ready", function () {
        document.querySelectorAll(".reveal .slides section").forEach(function (sl) { prepare(sl, true); });
      });
      reveal.on("fragmentshown", function (e) {
        var el = e.fragment;
        if (el._rnSvg) { el._rnSvg.style.visibility = "visible"; animateIn(el._rnSvg, true); }
      });
      reveal.on("fragmenthidden", function (e) {
        if (e.fragment._rnSvg) e.fragment._rnSvg.style.visibility = "hidden";
      });
    }
  };
})();
