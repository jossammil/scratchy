#' Map data values to positions in a converted plot
#'
#' Scenes made by [as_excalidraw()] from a ggplot remember how data values
#' map to px. Discrete values such as `"suv"` map to the centre of their
#' category. Wrap values in [I()] to give px directly.
#'
#' @param scene An `exc_scene` made from a ggplot.
#' @param x,y Data values (or px wrapped in `I()`).
#' @param panel Panel number for faceted plots, in layout order.
#' @return A list with `x` and `y` in px.
#' @export
exc_data_to_px <- function(scene, x, y, panel = 1) {
  check_scene(scene)
  as_px <- function(v) inherits(v, "AsIs") || is.null(scene$meta$coord)
  if (as_px(x) && as_px(y)) {
    if (is.null(scene$meta$coord) && (!is.numeric(unclass(x)) || !is.numeric(unclass(y)))) {
      cli::cli_abort(c("This scene has no data coordinates, so positions must be numbers in px.",
                       i = "Data coordinates work for scenes made from a ggplot with {.fn as_excalidraw}."))
    }
    return(list(x = as.numeric(unclass(x)), y = as.numeric(unclass(y))))
  }
  map <- scene$meta$coord[[panel]]
  if (is.null(map)) cli::cli_abort("Panel {panel} doesn't exist in this plot.")
  hval <- if (map$flip) y else x
  vval <- if (map$flip) x else y
  hscale <- if (map$flip) map$scale_y else map$scale_x
  vscale <- if (map$flip) map$scale_x else map$scale_y
  r <- map$rect
  px <- if (inherits(hval, "AsIs")) as.numeric(unclass(hval)) else {
    r[["x0"]] + (scale_position(hscale, hval) - map$x_range[1]) / diff(map$x_range) * (r[["x1"]] - r[["x0"]])
  }
  py <- if (inherits(vval, "AsIs")) as.numeric(unclass(vval)) else {
    r[["y1"]] - (scale_position(vscale, vval) - map$y_range[1]) / diff(map$y_range) * (r[["y1"]] - r[["y0"]])
  }
  list(x = px, y = py)
}

scale_position <- function(scale, v) {
  v <- unclass(v)
  if (scale$is_discrete()) {
    if (is.numeric(v)) return(v)
    return(as.numeric(scale$map(as.character(v))))
  }
  if (is.character(v)) v <- as.numeric(v)
  as.numeric(scale$transform(v))
}

# A px box around data values: single discrete values span their category
# band (0.9 wide, like geom_bar), single numbers are points, pairs are ranges.
data_box <- function(scene, x, y, panel) {
  band <- function(v, discrete) {
    if (length(v) == 1 && discrete) list(lo = v, hi = v, half = 0.45) else
      list(lo = v[1], hi = v[length(v)], half = 0)
  }
  map <- scene$meta$coord[[panel]]
  disc <- function(v, horizontal) {
    if (is.null(map) || inherits(v, "AsIs")) return(FALSE)
    sc <- if (xor(horizontal, map$flip)) map$scale_x else map$scale_y
    sc$is_discrete() && !is.numeric(v)
  }
  bx <- band(x, disc(x, TRUE))
  by <- band(y, disc(y, FALSE))
  corner <- function(xv, yv) exc_data_to_px(scene, xv, yv, panel)
  pts <- list(corner(bx$lo, by$lo), corner(bx$hi, by$hi))
  xs <- c(pts[[1]]$x, pts[[2]]$x)
  ys <- c(pts[[1]]$y, pts[[2]]$y)
  if (!is.null(map) && bx$half > 0) {
    unit <- (map$rect[["x1"]] - map$rect[["x0"]]) / diff(map$x_range)
    if (map$flip) unit <- (map$rect[["y1"]] - map$rect[["y0"]]) / diff(map$y_range)
    if (map$flip) ys <- c(min(ys) - bx$half * unit, max(ys) + bx$half * unit)
    else xs <- c(min(xs) - bx$half * unit, max(xs) + bx$half * unit)
  }
  if (!is.null(map) && by$half > 0) {
    unit <- (map$rect[["y1"]] - map$rect[["y0"]]) / diff(map$y_range)
    if (map$flip) unit <- (map$rect[["x1"]] - map$rect[["x0"]]) / diff(map$x_range)
    if (map$flip) xs <- c(min(xs) - by$half * unit, max(xs) + by$half * unit)
    else ys <- c(min(ys) - by$half * unit, max(ys) + by$half * unit)
  }
  c(x0 = min(xs), y0 = min(ys), x1 = max(xs), y1 = max(ys))
}

annotation <- function(els) {
  out <- lapply(unclass(els), function(e) {
    e$customData$scratchy$role <- "annotation"
    e
  })
  new_elements(out, attr(els, "files"))
}

# Point on the border of a box (centre c, half sizes hw, hh) towards p.
box_edge <- function(cx, cy, hw, hh, px, py) {
  dx <- px - cx; dy <- py - cy
  if (dx == 0 && dy == 0) return(c(cx, cy))
  t <- min(if (dx != 0) hw / abs(dx) else Inf, if (dy != 0) hh / abs(dy) else Inf)
  c(cx + dx * t, cy + dy * t)
}

# A curved arrow that bows upwards (towards smaller y), like a hand-drawn
# pointer over a chart.
curved_arrow <- function(from, to, bend = 0.2, ...) {
  mid <- (from + to) / 2
  d <- to - from
  normal <- c(-d[2], d[1])
  if (normal[2] > 0) normal <- -normal
  ctrl <- mid + normal * bend
  exc_arrow(rbind(from, ctrl, to), curved = TRUE, ...)
}

#' Hand-drawn annotations
#'
#' Add sticky notes, callouts, marks and titles to a scene. Positions use the
#' plot's data values for scenes made from a ggplot (see [exc_data_to_px()]),
#' or px when wrapped in [I()].
#'
#' * `exc_note()`: a sticky note, optionally with an arrow pointing `to` a spot.
#' * `exc_callout()`: a handwritten remark with a curved arrow to a spot.
#' * `exc_mark()`: circle, box, underline, highlight, strike through,
#'   bracket or cross out a value or a range, like rough-notation.
#' * `exc_title()`: a big title with a hand-drawn underline, above the drawing.
#'
#' @param scene An `exc_scene`.
#' @param text The text.
#' @param x,y Where to put it: data values, or px in `I()`. For
#'   `exc_mark()`, give one value to mark a point or category, or two values
#'   for a range.
#' @param to Optional `c(x, y)` (or `list(x, y)`) the note's arrow points at.
#' @param width Maximum width of the note in px before the text wraps.
#' @param fill Note colour (an Excalidraw hue name or a colour).
#' @param angle Tilt in degrees, for a casually stuck-on look.
#' @param panel Panel number in faceted plots.
#' @param ... Style properties passed to the elements, such as `stroke`,
#'   `font`, `font_size` or `roughness`.
#' @return The scene with the annotation added.
#' @name annotations
#' @examples
#' \donttest{
#' library(ggplot2)
#' p <- ggplot(mpg, aes(class)) + geom_bar(fill = "#a5d8ff")
#' as_excalidraw(p) |>
#'   exc_title("What do people drive?") |>
#'   exc_mark(x = "suv", y = c(0, 62), type = "box") |>
#'   exc_note("SUVs win!", x = "midsize", y = 55, to = c("suv", 50)) |>
#'   exc_callout("so few", x = "2seater", y = 5)
#' }
NULL

#' @rdname annotations
#' @export
exc_note <- function(scene, text, x, y, to = NULL, width = 200, fill = "yellow", angle = -2,
                     panel = 1, ...) {
  check_scene(scene)
  pos <- exc_data_to_px(scene, x, y, panel)
  s <- resolve_style(NULL, list(...))
  font <- resolve_font(s$fontFamily)
  wrapped <- wrap_text(text, width - 24, font, s$fontSize)
  m <- measure_text(wrapped, font, s$fontSize)
  w <- m$width + 28
  h <- m$height + 24
  fill_col <- norm_color(fill, shade = 2)
  note <- exc_rect(pos$x - w / 2, pos$y - h / 2, w, h, label = wrapped, fill = fill_col,
                   fill_style = "solid", rounded = TRUE, angle = angle,
                   stroke = ink_for(fill_col), ...)
  note[[2]]$strokeColor <- s$strokeColor
  els <- note
  if (!is.null(to)) {
    to <- as.list(to)
    tgt <- exc_data_to_px(scene, to[[1]], to[[2]], panel)
    start <- box_edge(pos$x, pos$y, w / 2 + 4, h / 2 + 4, tgt$x, tgt$y)
    end <- c(tgt$x, tgt$y)
    end <- end - (end - start) / sqrt(sum((end - start)^2)) * 6
    els <- c(els, curved_arrow(start, end, ...))
  }
  exc_add(scene, annotation(els))
}

#' @rdname annotations
#' @param dx,dy Offset in px from the spot to the text.
#' @export
exc_callout <- function(scene, text, x, y, dx = 60, dy = -60, panel = 1, ...) {
  check_scene(scene)
  tgt <- exc_data_to_px(scene, x, y, panel)
  s <- resolve_style(NULL, list(...))
  label <- exc_text(text, tgt$x + dx, tgt$y + dy, hjust = if (dx >= 0) 0 else 1, vjust = 0.5, ...)
  t <- label[[1]]
  start <- c(if (dx >= 0) t$x - 6 else t$x + t$width + 6, t$y + t$height / 2)
  end <- c(tgt$x, tgt$y)
  end <- end - (end - start) / sqrt(sum((end - start)^2)) * 6
  exc_add(scene, annotation(c(label, curved_arrow(start, end, bend = 0.25, ...))))
}

#' @rdname annotations
#' @param type `"circle"`, `"box"`, `"underline"`, `"highlight"`,
#'   `"strike"`, `"bracket"` or `"cross"`.
#' @param color Mark colour. Highlights default to a translucent yellow.
#' @param padding Space in px between the marked area and the mark.
#' @export
exc_mark <- function(scene, x, y, type = c("circle", "box", "underline", "highlight",
                                           "strike", "bracket", "cross"),
                     color = NULL, padding = 6, panel = 1, ...) {
  check_scene(scene)
  type <- match.arg(type)
  b <- data_box(scene, x, y, panel)
  b <- b + c(-padding, -padding, padding, padding)
  w <- b[["x1"]] - b[["x0"]]
  h <- b[["y1"]] - b[["y0"]]
  col <- color %||% if (type == "highlight") "yellow" else "red"
  ink <- norm_color(col)
  args <- utils::modifyList(list(stroke = ink, stroke_width = 2), list(...))
  els <- switch(type,
    circle = do.call(exc_ellipse, c(list(b[["x0"]] - w * 0.08, b[["y0"]] - h * 0.08, w * 1.16, h * 1.16,
                                         roughness = 1.5), args)),
    box = do.call(exc_rect, c(list(b[["x0"]], b[["y0"]], w, h), args)),
    underline = do.call(exc_line, c(list(c(b[["x0"]], b[["x1"]]), c(b[["y1"]], b[["y1"]] + 2)), args)),
    strike = do.call(exc_line, c(list(c(b[["x0"]], b[["x1"]]), rep((b[["y0"]] + b[["y1"]]) / 2, 2)), args)),
    cross = c(do.call(exc_line, c(list(c(b[["x0"]], b[["x1"]]), c(b[["y0"]], b[["y1"]])), args)),
              do.call(exc_line, c(list(c(b[["x0"]], b[["x1"]]), c(b[["y1"]], b[["y0"]])), args))),
    bracket = {
      tick <- min(10, w / 4)
      c(do.call(exc_line, c(list(c(b[["x0"]] + tick, b[["x0"]], b[["x0"]], b[["x0"]] + tick),
                                 c(b[["y0"]], b[["y0"]], b[["y1"]], b[["y1"]])), args)),
        do.call(exc_line, c(list(c(b[["x1"]] - tick, b[["x1"]], b[["x1"]], b[["x1"]] - tick),
                                 c(b[["y0"]], b[["y0"]], b[["y1"]], b[["y1"]])), args)))
    },
    highlight = do.call(exc_rect, c(list(b[["x0"]], b[["y0"]], w, h, fill = norm_color(col, 2),
                                         fill_style = "solid", stroke = "transparent",
                                         opacity = 55, roughness = 1), list(...)))
  )
  els <- annotation(els)
  if (type == "highlight") {
    scene$elements <- c(unclass(els), scene$elements)
    scene$elements <- ensure_indices(lapply(scene$elements, function(e) set_null(e, "index")))
    return(scene)
  }
  exc_add(scene, els)
}

#' @rdname annotations
#' @param title,subtitle Title and optional subtitle text.
#' @param size Title font size in px (Excalidraw's XL is 36).
#' @param underline Draw a hand-drawn underline under the title.
#' @export
exc_title <- function(scene, title, subtitle = NULL, size = 36, underline = TRUE, ...) {
  check_scene(scene)
  bb <- exc_bbox(scene)
  x0 <- bb[["xmin"]] + 4
  t <- exc_text(title, x0, 0, font_size = size, ...)
  sub <- if (!is.null(subtitle)) exc_text(subtitle, x0, 0, font_size = round(size * 0.55), ...) else NULL
  gap <- 14
  total <- t[[1]]$height + (if (underline) 12 else 0) + (if (!is.null(sub)) sub[[1]]$height + 6 else 0)
  top <- bb[["ymin"]] - total - gap
  t[[1]]$y <- top
  els <- t
  if (underline) {
    uy <- top + t[[1]]$height + 4
    els <- c(els, exc_line(c(x0, x0 + t[[1]]$width * 0.55, x0 + t[[1]]$width + 6),
                           c(uy, uy + 3, uy - 1), curved = TRUE, stroke = "red",
                           stroke_width = 2))
  }
  if (!is.null(sub)) {
    sub[[1]]$y <- top + t[[1]]$height + (if (underline) 14 else 4)
    els <- c(els, sub)
  }
  exc_add(scene, annotation(els))
}
