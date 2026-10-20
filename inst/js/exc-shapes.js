// exc-shapes.js
//
// Turns Excalidraw elements into sketchy, absolutely positioned polylines and
// polygons for the R renderer. The element-to-rough.js logic is a port of
// Excalidraw's packages/element/src/shape.ts, bounds.ts and utils.ts
// (MIT License, Copyright (c) 2020 Excalidraw), so the same element seed
// gives the same strokes as excalidraw.com.
//
// Needs the globals `rough` (rough.js 4.6.4) and `PerfectFreehand`.

var ExcShapes = (function () {
  "use strict";

  var generator = rough.generator();
  var CARTOONIST = 2;
  var PROPORTIONAL_RADIUS = 0.25;
  var ADAPTIVE_RADIUS = 32;
  var LINE_CONFIRM_THRESHOLD = 8;

  // ---- helpers ported from Excalidraw ---------------------------------------

  function isTransparent(c) {
    if (!c) return true;
    return c === "transparent" ||
      (c.length === 5 && c.substr(4, 1) === "0") ||
      (c.length === 9 && c.substr(7, 2) === "00");
  }

  function isLinear(el) {
    return el.type === "line" || el.type === "arrow";
  }

  function canChangeRoundness(type) {
    return type === "rectangle" || type === "iframe" || type === "embeddable" ||
      type === "line" || type === "diamond" || type === "image";
  }

  function isPathALoop(points) {
    if (points && points.length >= 3) {
      var a = points[0], b = points[points.length - 1];
      return Math.hypot(a[0] - b[0], a[1] - b[1]) <= LINE_CONFIRM_THRESHOLD;
    }
    return false;
  }

  function getCornerRadius(x, el) {
    var r = el.roundness;
    if (r && (r.type === 2 || r.type === 1)) return x * PROPORTIONAL_RADIUS;
    if (r && r.type === 3) {
      var fixed = r.value != null ? r.value : ADAPTIVE_RADIUS;
      var cutoff = fixed / PROPORTIONAL_RADIUS;
      return x <= cutoff ? x * PROPORTIONAL_RADIUS : fixed;
    }
    return 0;
  }

  function adjustRoughness(el) {
    var roughness = el.roughness;
    var maxSize = Math.max(el.width, el.height);
    var minSize = Math.min(el.width, el.height);
    if ((minSize >= 20 && maxSize >= 50) ||
        (minSize >= 15 && !!el.roundness && canChangeRoundness(el.type)) ||
        (isLinear(el) && maxSize >= 50)) {
      return roughness;
    }
    return Math.min(roughness / (maxSize < 10 ? 3 : 2), 2.5);
  }

  function dashArrayDashed(sw) { return [8, 8 + sw]; }
  function dashArrayDotted(sw) { return [1.5, 6 + sw]; }

  function roughOptions(el, continuousPath) {
    var o = {
      seed: el.seed,
      strokeLineDash: el.strokeStyle === "dashed" ? dashArrayDashed(el.strokeWidth) :
        el.strokeStyle === "dotted" ? dashArrayDotted(el.strokeWidth) : undefined,
      disableMultiStroke: el.strokeStyle !== "solid",
      strokeWidth: el.strokeStyle !== "solid" ? el.strokeWidth + 0.5 : el.strokeWidth,
      fillWeight: el.strokeWidth / 2,
      hachureGap: el.strokeWidth * 4,
      roughness: adjustRoughness(el),
      stroke: el.strokeColor,
      preserveVertices: !!continuousPath || el.roughness < CARTOONIST
    };
    if (el.bowing != null) o.bowing = el.bowing;
    switch (el.type) {
      case "rectangle":
      case "iframe":
      case "embeddable":
      case "diamond":
      case "ellipse":
        o.fillStyle = el.fillStyle;
        o.fill = isTransparent(el.backgroundColor) ? undefined : el.backgroundColor;
        if (el.type === "ellipse") o.curveFitting = 1;
        return o;
      case "line":
      case "freedraw":
        if (isPathALoop(el.points)) {
          o.fillStyle = el.fillStyle;
          o.fill = el.backgroundColor === "transparent" ? undefined : el.backgroundColor;
        }
        return o;
      default:
        return o;
    }
  }

  function diamondPoints(el) {
    var topX = Math.floor(el.width / 2) + 1, topY = 0;
    var rightX = el.width, rightY = Math.floor(el.height / 2) + 1;
    return [topX, topY, rightX, rightY, topX, el.height, 0, rightY];
  }

  function rotatePoint(x, y, cx, cy, a) {
    if (!a) return [x, y];
    return [(x - cx) * Math.cos(a) - (y - cy) * Math.sin(a) + cx,
            (x - cx) * Math.sin(a) + (y - cy) * Math.cos(a) + cy];
  }

  function curvePathOps(shape) {
    if (!shape) return [];
    for (var i = 0; i < shape.sets.length; i++) {
      if (shape.sets[i].type === "path") return shape.sets[i].ops;
    }
    return shape.sets[0].ops;
  }

  function arrowheadSize(a) {
    switch (a) {
      case "arrow": return 25;
      case "diamond": case "diamond_outline": return 12;
      case "cardinality_many": case "cardinality_one_or_many": case "cardinality_zero_or_many": return 15;
      case "cardinality_one": case "cardinality_exactly_one": case "cardinality_zero_or_one": return 20;
      default: return 15;
    }
  }

  function arrowheadAngle(a) {
    if (a === "bar") return 90;
    if (a === "arrow") return 20;
    return 25;
  }

  function arrowheadPoints(el, shape, position, arrowhead, offsetMultiplier) {
    offsetMultiplier = offsetMultiplier || 0;
    if (arrowhead === null || shape.length < 1) return null;
    var ops = curvePathOps(shape[0]);
    if (ops.length < 1) return null;
    var index = position === "start" ? 1 : ops.length - 1;
    var data = ops[index].data;
    if (data.length !== 6) return null;
    var p3 = [data[4], data[5]], p2 = [data[2], data[3]], p1 = [data[0], data[1]];
    var prev = ops[index - 1];
    var p0 = [0, 0];
    if (prev.op === "move") p0 = [prev.data[0], prev.data[1]];
    else if (prev.op === "bcurveTo") p0 = [prev.data[4], prev.data[5]];
    var eq = function (t, i) {
      return Math.pow(1 - t, 3) * p3[i] + 3 * t * Math.pow(1 - t, 2) * p2[i] +
        3 * Math.pow(t, 2) * (1 - t) * p1[i] + p0[i] * Math.pow(t, 3);
    };
    var tip = position === "start" ? p0 : p3;
    var x2 = tip[0], y2 = tip[1];
    var x1 = eq(0.3, 0), y1 = eq(0.3, 1);
    var distance = Math.hypot(x2 - x1, y2 - y1);
    var nx = (x2 - x1) / distance, ny = (y2 - y1) / distance;
    var size = arrowheadSize(arrowhead);
    var pts = el.points;
    var c = position === "end" ? pts[pts.length - 1] : pts[0];
    var p = pts.length > 1 ? (position === "end" ? pts[pts.length - 2] : pts[1]) : [0, 0];
    var length = Math.hypot(c[0] - p[0], c[1] - p[1]);
    var lengthMultiplier = arrowhead === "diamond" || arrowhead === "diamond_outline" ? 0.25 : 0.5;
    var minSize = Math.min(size, length * lengthMultiplier);
    var tx = x2 - nx * minSize * offsetMultiplier, ty = y2 - ny * minSize * offsetMultiplier;
    var xs = tx - nx * minSize, ys = ty - ny * minSize;
    if (arrowhead === "circle" || arrowhead === "circle_outline") {
      var diameter = Math.hypot(ys - ty, xs - tx) + el.strokeWidth - 2;
      return [tx, ty, diameter];
    }
    var angle = arrowheadAngle(arrowhead) * Math.PI / 180;
    var r3, r4;
    if (arrowhead === "cardinality_many" || arrowhead === "cardinality_one_or_many") {
      r3 = rotatePoint(tx, ty, xs, ys, -angle);
      r4 = rotatePoint(tx, ty, xs, ys, angle);
      return [xs, ys, r3[0], r3[1], r4[0], r4[1]];
    }
    r3 = rotatePoint(xs, ys, tx, ty, -angle);
    r4 = rotatePoint(xs, ys, tx, ty, angle);
    if (arrowhead === "diamond" || arrowhead === "diamond_outline") {
      var o;
      if (position === "start") {
        var q = pts.length > 1 ? pts[1] : [0, 0];
        o = rotatePoint(tx + minSize * 2, ty, tx, ty, Math.atan2(q[1] - ty, q[0] - tx));
      } else {
        var q2 = pts.length > 1 ? pts[pts.length - 2] : [0, 0];
        o = rotatePoint(tx - minSize * 2, ty, tx, ty, Math.atan2(ty - q2[1], tx - q2[0]));
      }
      return [tx, ty, r3[0], r3[1], o[0], o[1], r4[0], r4[1]];
    }
    return [tx, ty, r3[0], r3[1], r4[0], r4[1]];
  }

  function arrowheadLineOptions(el, options) {
    var o = Object.assign({}, options);
    if (el.strokeStyle === "dotted") {
      var dash = dashArrayDotted(el.strokeWidth - 1);
      o.strokeLineDash = [dash[0], dash[1] - 1];
    } else {
      delete o.strokeLineDash;
    }
    o.roughness = Math.min(1, o.roughness || 0);
    return o;
  }

  function linesToTip(ap, o) {
    if (ap === null) return [];
    return [generator.line(ap[2], ap[3], ap[0], ap[1], o), generator.line(ap[4], ap[5], ap[0], ap[1], o)];
  }

  function cardinalityOne(ap, o) {
    if (ap === null) return [];
    return [generator.line(ap[2], ap[3], ap[4], ap[5], o)];
  }

  function outlineCircle(options, stroke, ap, fill, scale) {
    if (ap === null) return [];
    var o = Object.assign({}, options, {
      fill: fill, fillStyle: "solid", stroke: stroke,
      roughness: Math.min(0.5, options.roughness || 0)
    });
    delete o.strokeLineDash;
    return [generator.circle(ap[0], ap[1], ap[2] * (scale || 1), o)];
  }

  function arrowheadShapes(el, shape, position, arrowhead, options, canvasBg) {
    if (arrowhead === null || arrowhead === undefined) return [];
    if (arrowhead === "dot") arrowhead = "circle";
    var stroke = el.strokeColor;
    var ap, o, lo;
    switch (arrowhead) {
      case "circle":
      case "circle_outline":
        return outlineCircle(options, stroke, arrowheadPoints(el, shape, position, arrowhead),
          arrowhead === "circle_outline" ? canvasBg : stroke);
      case "triangle":
      case "triangle_outline":
        ap = arrowheadPoints(el, shape, position, arrowhead);
        if (ap === null) return [];
        o = Object.assign({}, options, {
          fill: arrowhead === "triangle_outline" ? canvasBg : stroke,
          fillStyle: "solid", roughness: Math.min(1, options.roughness || 0)
        });
        delete o.strokeLineDash;
        return [generator.polygon([[ap[0], ap[1]], [ap[2], ap[3]], [ap[4], ap[5]], [ap[0], ap[1]]], o)];
      case "diamond":
      case "diamond_outline":
        ap = arrowheadPoints(el, shape, position, arrowhead);
        if (ap === null) return [];
        o = Object.assign({}, options, {
          fill: arrowhead === "diamond_outline" ? canvasBg : stroke,
          fillStyle: "solid", roughness: Math.min(1, options.roughness || 0)
        });
        delete o.strokeLineDash;
        return [generator.polygon([[ap[0], ap[1]], [ap[2], ap[3]], [ap[4], ap[5]], [ap[6], ap[7]], [ap[0], ap[1]]], o)];
      case "cardinality_one":
        return cardinalityOne(arrowheadPoints(el, shape, position, arrowhead), arrowheadLineOptions(el, options));
      case "cardinality_many":
        return linesToTip(arrowheadPoints(el, shape, position, arrowhead), arrowheadLineOptions(el, options));
      case "cardinality_one_or_many":
        lo = arrowheadLineOptions(el, options);
        return linesToTip(arrowheadPoints(el, shape, position, "cardinality_many"), lo)
          .concat(cardinalityOne(arrowheadPoints(el, shape, position, "cardinality_one", -0.25), lo));
      case "cardinality_exactly_one":
        lo = arrowheadLineOptions(el, options);
        return cardinalityOne(arrowheadPoints(el, shape, position, "cardinality_one", -0.5), lo)
          .concat(cardinalityOne(arrowheadPoints(el, shape, position, "cardinality_one"), lo));
      case "cardinality_zero_or_one":
        lo = arrowheadLineOptions(el, options);
        return outlineCircle(options, stroke, arrowheadPoints(el, shape, position, "circle_outline", 1.5), canvasBg, 0.8)
          .concat(cardinalityOne(arrowheadPoints(el, shape, position, "cardinality_one", -0.5), lo));
      case "cardinality_zero_or_many":
        lo = arrowheadLineOptions(el, options);
        return linesToTip(arrowheadPoints(el, shape, position, "cardinality_many"), lo)
          .concat(outlineCircle(options, stroke, arrowheadPoints(el, shape, position, "circle_outline", 1.5), canvasBg, 0.8));
      default:
        return linesToTip(arrowheadPoints(el, shape, position, arrowhead), arrowheadLineOptions(el, options));
    }
  }

  function headingIsHorizontal(p, o) {
    var x = p[0] - o[0], y = p[1] - o[1];
    var ax = Math.abs(x), ay = Math.abs(y);
    if (x > ay) return true;
    if (x <= -ay) return true;
    return false;
  }

  function elbowArrowPath(points, radius) {
    var sub = [];
    for (var i = 1; i < points.length - 1; i++) {
      var prev = points[i - 1], next = points[i + 1], pt = points[i];
      var corner = Math.min(radius,
        Math.hypot(pt[0] - next[0], pt[1] - next[1]) / 2,
        Math.hypot(pt[0] - prev[0], pt[1] - prev[1]) / 2);
      if (headingIsHorizontal(pt, prev)) {
        sub.push(prev[0] < pt[0] ? [pt[0] - corner, pt[1]] : [pt[0] + corner, pt[1]]);
      } else if (prev[1] < pt[1]) {
        sub.push([pt[0], pt[1] - corner]);
      } else {
        sub.push([pt[0], pt[1] + corner]);
      }
      sub.push(pt);
      if (headingIsHorizontal(next, pt)) {
        sub.push(next[0] < pt[0] ? [pt[0] - corner, pt[1]] : [pt[0] + corner, pt[1]]);
      } else if (next[1] < pt[1]) {
        sub.push([pt[0], pt[1] - corner]);
      } else {
        sub.push([pt[0], pt[1] + corner]);
      }
    }
    var d = ["M " + points[0][0] + " " + points[0][1]];
    for (var j = 0; j < sub.length; j += 3) {
      d.push("L " + sub[j][0] + " " + sub[j][1]);
      d.push("Q " + sub[j + 1][0] + " " + sub[j + 1][1] + ", " + sub[j + 2][0] + " " + sub[j + 2][1]);
    }
    var last = points[points.length - 1];
    d.push("L " + last[0] + " " + last[1]);
    return d.join(" ");
  }

  // Ramer-Douglas-Peucker, as in points-on-curve's simplify().
  function simplify(points, tolerance) {
    if (points.length <= 2) return points.slice();
    var sqTol = tolerance * tolerance;
    function segDist(p, a, b) {
      var x = a[0], y = a[1], dx = b[0] - x, dy = b[1] - y;
      if (dx !== 0 || dy !== 0) {
        var t = ((p[0] - x) * dx + (p[1] - y) * dy) / (dx * dx + dy * dy);
        if (t > 1) { x = b[0]; y = b[1]; } else if (t > 0) { x += dx * t; y += dy * t; }
      }
      dx = p[0] - x; dy = p[1] - y;
      return dx * dx + dy * dy;
    }
    function step(pts, first, last, out) {
      var maxD = sqTol, idx = -1;
      for (var i = first + 1; i < last; i++) {
        var d = segDist(pts[i], pts[first], pts[last]);
        if (d > maxD) { idx = i; maxD = d; }
      }
      if (idx > -1) {
        if (idx - first > 1) step(pts, first, idx, out);
        out.push(pts[idx]);
        if (last - idx > 1) step(pts, idx, last, out);
      }
    }
    var out = [points[0]];
    step(points, 0, points.length - 1, out);
    out.push(points[points.length - 1]);
    return out;
  }

  function freedrawOutline(el) {
    var input = el.simulatePressure ? el.points :
      el.points.length ? el.points.map(function (p, i) { return [p[0], p[1], el.pressures[i]]; }) : [[0, 0, 0.5]];
    return PerfectFreehand.getStroke(input, {
      simulatePressure: el.simulatePressure,
      size: el.strokeWidth * 4.25,
      thinning: 0.6,
      smoothing: 0.5,
      streamline: (el.strokeOptions && el.strokeOptions.streamline) || 0.5,
      easing: function (t) { return Math.sin((t * Math.PI) / 2); },
      last: true
    });
  }

  // Excalidraw's getSvgPathFromStroke(), sampled into a closed polygon.
  function strokeOutlinePolygon(points) {
    if (!points.length) return [];
    var out = [points[0][0], points[0][1]];
    var cur = points[0];
    var n = points.length;
    for (var i = 0; i < n; i++) {
      var ctrl = points[i];
      var nxt = points[(i + 1) % n];
      var end = [(ctrl[0] + nxt[0]) / 2, (ctrl[1] + nxt[1]) / 2];
      for (var k = 1; k <= 3; k++) {
        var t = k / 3, u = 1 - t;
        out.push(u * u * cur[0] + 2 * u * t * ctrl[0] + t * t * end[0],
                 u * u * cur[1] + 2 * u * t * ctrl[1] + t * t * end[1]);
      }
      cur = end;
    }
    out.push(points[0][0], points[0][1]);
    return out;
  }

  // ---- shapes per element (Excalidraw's _generateElementShape) -----------------

  function elementShapes(el, canvasBg) {
    var w = el.width, h = el.height, r;
    switch (el.type) {
      case "rectangle":
      case "iframe":
      case "embeddable":
        if (el.roundness) {
          r = getCornerRadius(Math.min(w, h), el);
          return [generator.path(
            "M " + r + " 0 L " + (w - r) + " 0 Q " + w + " 0, " + w + " " + r +
            " L " + w + " " + (h - r) + " Q " + w + " " + h + ", " + (w - r) + " " + h +
            " L " + r + " " + h + " Q 0 " + h + ", 0 " + (h - r) +
            " L 0 " + r + " Q 0 0, " + r + " 0",
            roughOptions(el, true))];
        }
        return [generator.rectangle(0, 0, w, h, roughOptions(el, false))];
      case "diamond": {
        var d = diamondPoints(el);
        if (el.roundness) {
          var vr = getCornerRadius(Math.abs(d[0] - d[6]), el);
          var hr = getCornerRadius(Math.abs(d[3] - d[1]), el);
          return [generator.path(
            "M " + (d[0] + vr) + " " + (d[1] + hr) + " L " + (d[2] - vr) + " " + (d[3] - hr) +
            " C " + d[2] + " " + d[3] + ", " + d[2] + " " + d[3] + ", " + (d[2] - vr) + " " + (d[3] + hr) +
            " L " + (d[4] + vr) + " " + (d[5] - hr) +
            " C " + d[4] + " " + d[5] + ", " + d[4] + " " + d[5] + ", " + (d[4] - vr) + " " + (d[5] - hr) +
            " L " + (d[6] + vr) + " " + (d[7] + hr) +
            " C " + d[6] + " " + d[7] + ", " + d[6] + " " + d[7] + ", " + (d[6] + vr) + " " + (d[7] - hr) +
            " L " + (d[0] - vr) + " " + (d[1] + hr) +
            " C " + d[0] + " " + d[1] + ", " + d[0] + " " + d[1] + ", " + (d[0] + vr) + " " + (d[1] + hr),
            roughOptions(el, true))];
        }
        return [generator.polygon([[d[0], d[1]], [d[2], d[3]], [d[4], d[5]], [d[6], d[7]]],
          roughOptions(el, false))];
      }
      case "ellipse":
        return [generator.ellipse(w / 2, h / 2, w, h, roughOptions(el, false))];
      case "line":
      case "arrow": {
        var options = roughOptions(el, false);
        var pts = el.points && el.points.length ? el.points : [[0, 0]];
        var shape;
        if (el.type === "arrow" && el.elbowed) {
          shape = [generator.path(elbowArrowPath(pts, 16), roughOptions(el, true))];
        } else if (!el.roundness) {
          shape = [options.fill ? generator.polygon(pts, options) : generator.linearPath(pts, options)];
        } else {
          shape = [generator.curve(pts, options)];
        }
        if (el.type === "arrow") {
          var start = el.startArrowhead === undefined ? null : el.startArrowhead;
          var end = el.endArrowhead === undefined ? "arrow" : el.endArrowhead;
          if (start !== null) shape = shape.concat(arrowheadShapes(el, shape, "start", start, options, canvasBg));
          if (end !== null) shape = shape.concat(arrowheadShapes(el, shape, "end", end, options, canvasBg));
        }
        return shape;
      }
      case "freedraw": {
        var shapes = [];
        if (isPathALoop(el.points)) {
          var fo = Object.assign({}, roughOptions(el, false), { stroke: "none" });
          shapes.push(generator.curve(simplify(el.points, 0.75), fo));
        }
        shapes.push({ polygon: strokeOutlinePolygon(freedrawOutline(el)), fill: el.strokeColor });
        return shapes;
      }
      default:
        return [];
    }
  }

  // ---- sampling and dashing -----------------------------------------------------

  function opsToPaths(ops, tol) {
    var paths = [], cur = null, x = 0, y = 0;
    for (var i = 0; i < ops.length; i++) {
      var op = ops[i], d = op.data;
      if (op.op === "move") {
        if (cur && cur.length > 2) paths.push(cur);
        cur = [d[0], d[1]];
        x = d[0]; y = d[1];
      } else if (op.op === "lineTo") {
        if (!cur) cur = [x, y];
        cur.push(d[0], d[1]);
        x = d[0]; y = d[1];
      } else if (op.op === "bcurveTo") {
        if (!cur) cur = [x, y];
        var len = Math.hypot(d[0] - x, d[1] - y) + Math.hypot(d[2] - d[0], d[3] - d[1]) +
          Math.hypot(d[4] - d[2], d[5] - d[3]);
        var n = Math.max(2, Math.min(96, Math.ceil(len / tol)));
        for (var k = 1; k <= n; k++) {
          var t = k / n, u = 1 - t;
          cur.push(u * u * u * x + 3 * u * u * t * d[0] + 3 * u * t * t * d[2] + t * t * t * d[4],
                   u * u * u * y + 3 * u * u * t * d[1] + 3 * u * t * t * d[3] + t * t * t * d[5]);
        }
        x = d[4]; y = d[5];
      }
    }
    if (cur && cur.length > 2) paths.push(cur);
    return paths;
  }

  // Canvas-style dashing, restarting at each subpath.
  function dashPaths(paths, dash) {
    if (!dash || !dash.length) return paths;
    var out = [];
    paths.forEach(function (p) {
      var di = 0, left = dash[0], on = true, seg = [p[0], p[1]];
      for (var i = 2; i < p.length; i += 2) {
        var x0 = p[i - 2], y0 = p[i - 1], x1 = p[i], y1 = p[i + 1];
        var len = Math.hypot(x1 - x0, y1 - y0), pos = 0;
        while (len - pos > left) {
          pos += left;
          var t = pos / len, xm = x0 + (x1 - x0) * t, ym = y0 + (y1 - y0) * t;
          if (on) { seg.push(xm, ym); out.push(seg); }
          seg = [xm, ym];
          on = !on;
          di = (di + 1) % dash.length;
          left = dash[di];
        }
        left -= (len - pos);
        if (on) seg.push(x1, y1); else seg = [x1, y1];
      }
      if (on && seg.length > 2) out.push(seg);
    });
    return out;
  }

  // Remove the parts of polylines inside an axis-aligned box (Liang-Barsky).
  function insideInterval(x0, y0, x1, y1, b) {
    var t0 = 0, t1 = 1, dx = x1 - x0, dy = y1 - y0;
    var p = [-dx, dx, -dy, dy], q = [x0 - b[0], b[2] - x0, y0 - b[1], b[3] - y0];
    for (var i = 0; i < 4; i++) {
      if (p[i] === 0) {
        if (q[i] < 0) return null;
      } else {
        var r = q[i] / p[i];
        if (p[i] < 0) { if (r > t1) return null; if (r > t0) t0 = r; }
        else { if (r < t0) return null; if (r < t1) t1 = r; }
      }
    }
    return t0 < t1 ? [t0, t1] : null;
  }

  function cutPaths(paths, box) {
    var out = [];
    paths.forEach(function (p) {
      var cur = [];
      for (var i = 0; i + 3 < p.length; i += 2) {
        var x0 = p[i], y0 = p[i + 1], x1 = p[i + 2], y1 = p[i + 3];
        var hit = insideInterval(x0, y0, x1, y1, box);
        if (!hit) {
          if (!cur.length) cur.push(x0, y0);
          cur.push(x1, y1);
          continue;
        }
        if (hit[0] > 0) {
          if (!cur.length) cur.push(x0, y0);
          cur.push(x0 + (x1 - x0) * hit[0], y0 + (y1 - y0) * hit[0]);
        }
        if (cur.length >= 4) out.push(cur);
        cur = [];
        if (hit[1] < 1) cur.push(x0 + (x1 - x0) * hit[1], y0 + (y1 - y0) * hit[1], x1, y1);
      }
      if (cur.length >= 4) out.push(cur);
    });
    return out;
  }

  // ---- placement ---------------------------------------------------------------

  function transformer(el) {
    var cx, cy;
    if (el.points && el.points.length && (isLinear(el) || el.type === "freedraw")) {
      var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      el.points.forEach(function (p) {
        if (p[0] < minX) minX = p[0]; if (p[0] > maxX) maxX = p[0];
        if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1];
      });
      cx = (minX + maxX) / 2; cy = (minY + maxY) / 2;
    } else {
      cx = el.width / 2; cy = el.height / 2;
    }
    var a = el.angle || 0, c = Math.cos(a), s = Math.sin(a), ox = el.x, oy = el.y;
    return function (path) {
      var out = new Array(path.length);
      for (var i = 0; i < path.length; i += 2) {
        var dx = path[i] - cx, dy = path[i + 1] - cy;
        out[i] = dx * c - dy * s + cx + ox;
        out[i + 1] = dx * s + dy * c + cy + oy;
      }
      return out;
    };
  }

  function drawableParts(drawable, tol) {
    var o = drawable.options, parts = [];
    var evenOdd = drawable.shape === "curve" || drawable.shape === "polygon" || drawable.shape === "path";
    drawable.sets.forEach(function (set) {
      var paths = opsToPaths(set.ops, tol);
      if (!paths.length) return;
      if (set.type === "path") {
        if (!o.stroke || o.stroke === "none" || isTransparent(o.stroke)) return;
        parts.push({ kind: "stroke", role: "outline", color: o.stroke, width: o.strokeWidth,
                     paths: dashPaths(paths, o.strokeLineDash) });
      } else if (set.type === "fillPath") {
        if (!o.fill) return;
        parts.push({ kind: "fill", role: "fill", color: o.fill, rule: evenOdd ? "evenodd" : "winding",
                     paths: paths });
      } else if (set.type === "fillSketch") {
        if (!o.fill) return;
        var fw = o.fillWeight < 0 ? o.strokeWidth / 2 : o.fillWeight;
        parts.push({ kind: "stroke", role: "fill", color: o.fill, width: fw, paths: paths });
      }
    });
    return parts;
  }

  function renderElement(el, canvasBg, tol) {
    var shapes = elementShapes(el, canvasBg);
    var place = transformer(el);
    var parts = [];
    shapes.forEach(function (sh) {
      if (sh.polygon) {
        if (sh.polygon.length > 4) {
          parts.push({ kind: "fill", role: "outline", color: sh.fill, rule: "winding", paths: [sh.polygon] });
        }
      } else {
        parts = parts.concat(drawableParts(sh, tol));
      }
    });
    parts.forEach(function (p) {
      p.paths = p.paths.map(place);
      if (el.__labelBox && p.kind === "stroke") p.paths = cutPaths(p.paths, el.__labelBox);
    });
    return { id: el.id, parts: parts };
  }

  return {
    render: function (elements, canvasBg, tol) {
      canvasBg = canvasBg || "#ffffff";
      tol = tol || 1;
      return elements.map(function (el) {
        try {
          return renderElement(el, canvasBg, tol);
        } catch (e) {
          return { id: el.id, parts: [], error: String(e) };
        }
      });
    }
  };
})();
