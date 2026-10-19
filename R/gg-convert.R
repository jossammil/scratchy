#' Turn a plot into an editable Excalidraw scene
#'
#' Draws the plot with [svglite::svglite()], reads back every line, box,
#' point, polygon and piece of text, and rebuilds them as Excalidraw
#' elements: bars become hachure-filled rectangles, lines become sketchy
#' lines, text uses a handwriting font. The result can be saved with
#' [write_excalidraw()] and edited by hand in Excalidraw, or drawn in R with
#' [exc_save()] / `plot()`.
#'
#' For ggplot2 plots the scene also remembers how data values map to
#' positions, so annotations such as [exc_note()] and [exc_mark()] can be
#' placed with data coordinates.
#'
#' @param x A ggplot, a formula such as `~ hist(x)` or a function that draws
#'   with base graphics, or a grid grob.
#' @param width,height Size of the drawing in px (Excalidraw units, 96 per
#'   inch).
#' @param theme For ggplots, a theme added before drawing. Defaults to
#'   [theme_excalidraw()]; use `NULL` to keep the plot's own theme.
#' @param fill_style Fill style for filled shapes: `"hachure"`,
#'   `"cross-hatch"`, `"solid"` or `"zigzag"`. Points and backgrounds are
#'   always solid.
#' @param roughness Sloppiness: `"architect"`, `"artist"`, `"cartoonist"` or
#'   a number.
#' @param outline Give filled shapes without a border a darker outline in
#'   the same hue, like Excalidraw shapes.
#' @param font Font for all text (see [exc_fonts()]); `NULL` keeps the fonts
#'   the plot used.
#' @param snap Round stroke widths to Excalidraw's thin / bold / extra bold.
#' @param preset Optional [exc_preset()] to restyle with afterwards.
#' @param seed Seed for the hand-drawn wobble, so the same plot always looks
#'   the same.
#' @param max_elements Warn when the scene has more elements than this;
#'   Excalidraw slows down with very many.
#' @param ... Unused.
#' @return An `exc_scene`.
#' @export
#' @examples
#' \donttest{
#' library(ggplot2)
#' p <- ggplot(mpg, aes(class, fill = drv)) + geom_bar() + scale_fill_excalidraw()
#' s <- as_excalidraw(p)
#' s
#' write_excalidraw(s, tempfile(fileext = ".excalidraw"))
#'
#' as_excalidraw(~ hist(faithful$eruptions, col = "#ffec99", main = "Old Faithful"))
#' }
as_excalidraw <- function(x, ...) UseMethod("as_excalidraw")

#' @rdname as_excalidraw
#' @export
as_excalidraw.ggplot <- function(x, width = 800, height = 500, theme = theme_excalidraw(),
                                 fill_style = "hachure", roughness = "artist", outline = TRUE,
                                 font = "Excalifont", snap = TRUE, preset = NULL, seed = 1,
                                 max_elements = 5000, ...) {
  rlang::check_installed(c("ggplot2", "svglite", "xml2"))
  p <- x
  if (!is.null(preset)) theme <- theme_excalidraw(preset = preset)
  if (!is.null(theme)) p <- p + theme
  if (!is.null(font)) {
    fam <- resolve_font(font)$family
    old <- lapply(list(text = ggplot2::GeomText, label = ggplot2::GeomLabel),
                  function(g) g$default_aes$family)
    ggplot2::update_geom_defaults("text", list(family = fam))
    ggplot2::update_geom_defaults("label", list(family = fam))
    on.exit({
      ggplot2::update_geom_defaults("text", list(family = old$text))
      ggplot2::update_geom_defaults("label", list(family = old$label))
    }, add = TRUE)
  }
  build <- ggplot2::ggplot_build(p)
  cap <- capture_svg(function() {
    # Build the gtable here so text is measured with the svglite device's fonts.
    gt <- ggplot2::ggplot_gtable(build)
    grid::grid.draw(gt)
    panel_locations(height / 96)
  }, width, height)
  opts <- convert_opts(fill_style, roughness, outline, font, snap)
  scene <- with_seed(seed, svg_to_scene(cap$svg, opts))
  scene$meta$coord <- coord_mapping(build, cap$extra)
  scene$meta$size <- c(width = width, height = height)
  finish_conversion(scene, preset, max_elements)
}

#' @rdname as_excalidraw
#' @export
as_excalidraw.formula <- function(x, width = 800, height = 500, fill_style = "hachure",
                                  roughness = "artist", outline = TRUE, font = "Excalifont",
                                  snap = TRUE, preset = NULL, seed = 1, max_elements = 5000, ...) {
  env <- environment(x)
  expr <- x[[length(x)]]
  as_excalidraw.function(function() eval(expr, env), width = width, height = height,
                         fill_style = fill_style, roughness = roughness, outline = outline,
                         font = font, snap = snap, preset = preset, seed = seed,
                         max_elements = max_elements)
}

#' @rdname as_excalidraw
#' @export
as_excalidraw.function <- function(x, width = 800, height = 500, fill_style = "hachure",
                                   roughness = "artist", outline = TRUE, font = "Excalifont",
                                   snap = TRUE, preset = NULL, seed = 1, max_elements = 5000, ...) {
  rlang::check_installed(c("svglite", "xml2"))
  fam <- if (is.null(font)) "" else resolve_font(font)$family
  cap <- capture_svg(function() {
    old <- graphics::par(family = fam)
    on.exit(graphics::par(old), add = TRUE)
    res <- x()
    if (inherits(res, c("ggplot", "grob", "gtable", "trellis"))) print(res)
    NULL
  }, width, height)
  opts <- convert_opts(fill_style, roughness, outline, font, snap)
  scene <- with_seed(seed, svg_to_scene(cap$svg, opts))
  scene$meta$size <- c(width = width, height = height)
  finish_conversion(scene, preset, max_elements)
}

#' @rdname as_excalidraw
#' @export
as_excalidraw.grob <- function(x, width = 800, height = 500, fill_style = "hachure",
                               roughness = "artist", outline = TRUE, font = "Excalifont",
                               snap = TRUE, preset = NULL, seed = 1, max_elements = 5000, ...) {
  as_excalidraw.function(function() {
    grid::grid.draw(x)
  }, width = width, height = height, fill_style = fill_style, roughness = roughness,
  outline = outline, font = font, snap = snap, preset = preset, seed = seed,
  max_elements = max_elements)
}

#' @export
as_excalidraw.exc_scene <- function(x, ...) x

finish_conversion <- function(scene, preset, max_elements) {
  n <- length(scene$elements)
  if (n > max_elements) {
    cli::cli_warn(c("The scene has {n} elements; Excalidraw may be slow to edit it.",
                    i = "Consider fewer points, or raise {.arg max_elements}."))
  }
  if (!is.null(preset)) scene <- exc_restyle(scene, preset)
  scene
}

convert_opts <- function(fill_style, roughness, outline, font, snap) {
  st <- normalize_style(list(fillStyle = fill_style, roughness = roughness))
  list(fill_style = st$fillStyle, roughness = st$roughness, outline = outline,
       font = if (is.null(font)) NULL else resolve_font(font), snap = snap)
}

with_seed <- function(seed, code) {
  if (is.null(seed)) return(code)
  old <- if (exists(".Random.seed", globalenv(), inherits = FALSE)) get(".Random.seed", globalenv()) else NULL
  on.exit({
    if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, globalenv())
  })
  set.seed(seed)
  code
}

# Draw on an svglite string device and return the SVG (plus whatever `draw`
# returns, computed while the device is still open).
capture_svg <- function(draw, width, height) {
  old <- grDevices::dev.cur()
  s <- svglite::svgstring(width = width / 96, height = height / 96, bg = "transparent",
                          fix_text_size = FALSE, standalone = TRUE)
  dev <- grDevices::dev.cur()
  on.exit({
    if (dev %in% grDevices::dev.list()) grDevices::dev.off(dev)
    if (old > 1 && old %in% grDevices::dev.list()) grDevices::dev.set(old)
  }, add = TRUE)
  extra <- draw()
  grDevices::dev.off(dev)
  pages <- as.character(s())
  # Measuring text can open a blank first page; the drawing is on the last.
  list(svg = pages[length(pages)], extra = extra)
}

vp_names <- function(tr) {
  if (inherits(tr, "vpTree")) return(c(tr$parent$name, unlist(lapply(tr$children, vp_names))))
  if (inherits(tr, "viewport")) return(tr$name)
  if (is.list(tr)) return(unlist(lapply(tr, vp_names)))
  NULL
}

# Positions (in px from the top-left) of the ggplot panel viewports, which
# gtable names like "panel-1-1.10-7-10-7".
panel_locations <- function(height_in) {
  names <- unique(grep("^panel[-.]", vp_names(grid::current.vpTree()), value = TRUE))
  locs <- lapply(names, function(n) {
    grid::seekViewport(n)
    ll <- grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
    ur <- grid::deviceLoc(grid::unit(1, "npc"), grid::unit(1, "npc"), valueOnly = TRUE)
    c(x0 = ll$x * 96, x1 = ur$x * 96, y0 = (height_in - ur$y) * 96, y1 = (height_in - ll$y) * 96)
  })
  grid::upViewport(0)
  if (length(locs) == 0) return(NULL)
  m <- do.call(rbind, locs)
  m[order(round(m[, "y0"]), round(m[, "x0"])), , drop = FALSE]
}

# Data -> px mapping for each panel (Cartesian and flipped coordinates).
coord_mapping <- function(build, locs) {
  if (is.null(locs)) return(NULL)
  coord <- build$layout$coord
  if (!inherits(coord, "CoordCartesian")) return(NULL)
  lay <- build$layout$layout
  lay <- lay[order(lay$ROW, lay$COL), , drop = FALSE]
  if (nrow(lay) != nrow(locs)) return(NULL)
  flip <- inherits(coord, "CoordFlip")
  panels <- lapply(seq_len(nrow(lay)), function(i) {
    idx <- as.integer(lay$PANEL[i])
    pp <- build$layout$panel_params[[idx]]
    list(
      panel = idx,
      rect = locs[i, ],
      x_range = pp$x.range, y_range = pp$y.range,
      scale_x = build$layout$panel_scales_x[[lay$SCALE_X[i]]],
      scale_y = build$layout$panel_scales_y[[lay$SCALE_Y[i]]],
      flip = flip
    )
  })
  panels[order(vapply(panels, function(p) p$panel, 1))]
}

# ---- SVG -> elements ----------------------------------------------------------

.svg_k <- 96 / 72

svg_to_scene <- function(svg, opts) {
  doc <- xml2::read_xml(svg)
  xml2::xml_ns_strip(doc)
  clips <- list()
  for (cp in xml2::xml_find_all(doc, "//clipPath")) {
    r <- xml2::xml_find_first(cp, "./rect")
    if (!inherits(r, "xml_missing")) {
      clips[[xml2::xml_attr(cp, "id")]] <- num_attrs(r, c("x", "y", "width", "height")) * .svg_k
    }
  }
  vb <- as.numeric(strsplit(xml2::xml_attr(doc, "viewBox"), " ")[[1]])
  canvas <- c(0, 0, vb[3], vb[4]) * .svg_k
  state <- new.env(parent = emptyenv())
  state$els <- list()
  state$files <- list()
  state$background <- NULL
  state$chart <- new_id()
  state$groups <- list()
  walk_svg(xml2::xml_find_first(doc, "/svg/g"), NULL, canvas, clips, opts, state)
  els <- state$els
  els <- lapply(els, function(e) {
    e$groupIds <- c(e$groupIds, list(state$chart))
    e$customData$excalidrawer$chart <- state$chart
    e
  })
  scene <- exc_scene(background = state$background %||% "#ffffff")
  new_scene(els, scene$appState, state$files, list())
}

# Numeric attributes; non-numeric values such as width='100%' become NA.
num_attrs <- function(node, names) {
  vapply(names, function(n) suppressWarnings(as.numeric(xml2::xml_attr(node, n))), 1)
}

walk_svg <- function(node, clip, canvas, clips, opts, state) {
  for (child in xml2::xml_children(node)) {
    nm <- xml2::xml_name(child)
    if (nm == "defs" || nm == "style" || nm == "clipPath") next
    if (nm == "g") {
      cp <- xml2::xml_attr(child, "clip-path")
      sub_clip <- clip
      if (!is.na(cp)) sub_clip <- clips[[sub("^url\\(#(.*)\\)$", "\\1", cp)]]
      walk_svg(child, sub_clip, canvas, clips, opts, state)
      next
    }
    new <- convert_node(child, nm, clip, canvas, opts, state)
    if (length(new)) state$els <- c(state$els, new)
  }
}

parse_style <- function(style) {
  if (is.na(style) || !nzchar(style)) return(list())
  parts <- trimws(strsplit(style, ";", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  kv <- regmatches(parts, regexpr(":", parts), invert = TRUE)
  stats::setNames(lapply(kv, function(p) trimws(p[2])), vapply(kv, function(p) trimws(p[1]), ""))
}

svg_color <- function(col, opacity = NULL) {
  if (is.null(col) || col == "none") return(NULL)
  col <- tolower(col)
  if (!is.null(opacity) && as.numeric(opacity) < 1) attr(col, "opacity") <- as.numeric(opacity)
  col
}

snap_width <- function(w, snap) {
  if (!snap) return(round(w, 2))
  if (w < 1.5) 1 else if (w < 3) 2 else 4
}

is_canvas_rect <- function(r, canvas) {
  all(abs(r - canvas) < 2)
}

same_rect <- function(a, b) !is.null(a) && !is.null(b) && all(abs(a - b) < 1.5)

# Stroke colour for a fill without a border: the strong shade of the same
# Excalidraw hue, or a darker version of the colour.
ink_for <- function(fill) {
  for (h in names(.palette)) {
    shades <- .palette[[h]]
    if (length(shades) == 5 && tolower(fill) %in% shades) return(shades[5])
  }
  rgb <- grDevices::col2rgb(fill)[, 1]
  dark <- round(rgb * 0.45)
  grDevices::rgb(dark[1], dark[2], dark[3], maxColorValue = 255)
}

element_style <- function(stroke, fill, sw, dash, opts, fill_style = NULL, opacity = 100) {
  s <- .default_style
  s$strokeColor <- if (is.null(stroke)) "transparent" else as.character(stroke)
  s$backgroundColor <- if (is.null(fill)) "transparent" else as.character(fill)
  s$fillStyle <- fill_style %||% opts$fill_style
  s$strokeWidth <- snap_width(sw, opts$snap)
  s$strokeStyle <- dash %||% "solid"
  s$roughness <- opts$roughness
  s$opacity <- opacity
  s
}

dash_style <- function(st, sw) {
  d <- st[["stroke-dasharray"]]
  if (is.null(d) || d == "none") return("solid")
  first <- as.numeric(strsplit(d, ",")[[1]][1])
  if (first <= 2 * max(sw / .svg_k, 0.5)) "dotted" else "dashed"
}

convert_node <- function(node, nm, clip, canvas, opts, state) {
  st <- parse_style(xml2::xml_attr(node, "style"))
  stroke <- svg_color(st[["stroke"]] %||% (if (nm == "text") "none" else "#000000"))
  fill <- svg_color(st[["fill"]] %||% (if (nm == "text") "#000000" else "none"))
  sw <- as.numeric(st[["stroke-width"]] %||% 1) * .svg_k
  op_fill <- as.numeric(st[["fill-opacity"]] %||% 1)
  op_stroke <- as.numeric(st[["stroke-opacity"]] %||% 1)
  in_panel <- !is.null(clip) && !is_canvas_rect(clip, canvas)
  role <- if (in_panel) "data" else "guide"
  tag <- function(els, r = role) {
    lapply(els, function(e) {
      e$customData$excalidrawer$role <- r
      e
    })
  }

  switch(nm,
    rect = {
      r <- num_attrs(node, c("x", "y", "width", "height")) * .svg_k
      if (any(is.na(r))) return(list())
      if (is.null(fill) && is.null(stroke)) return(list())
      if (is_canvas_rect(r, canvas) || (is.null(clip) && r[3] >= canvas[3] - 2)) {
        if (!is.null(fill) && is.null(state$background)) state$background <- fill
        return(list())
      }
      background <- same_rect(r, clip) || (r[3] * r[4] > 0.6 * canvas[3] * canvas[4])
      if (!is.null(clip)) r <- clip_rect(r, clip)
      if (is.null(r)) return(list())
      if (background) {
        s <- element_style(stroke, fill, sw, NULL, opts, fill_style = "solid", opacity = op_fill * 100)
        s$roughness <- 0
        el <- base_element("rectangle", r[1], r[2], r[3], r[4], s, locked = TRUE)
        return(tag(list(el), "background"))
      }
      if (is.null(stroke) && opts$outline && !is.null(fill)) {
        stroke <- ink_for(fill)
        sw <- 2
      }
      s <- element_style(stroke, fill, sw, dash_style(st, sw), opts, opacity = op_fill * 100)
      tag(list(base_element("rectangle", r[1], r[2], r[3], r[4], s)))
    },
    circle = {
      ctr <- num_attrs(node, c("cx", "cy", "r")) * .svg_k
      if (!is.null(clip) && !point_in_rect(ctr[1], ctr[2], clip)) return(list())
      if (is.null(stroke) && is.null(fill)) return(list())
      d <- 2 * ctr[3]
      s <- element_style(stroke, fill, sw, NULL, opts, fill_style = "solid",
                         opacity = max(op_fill, op_stroke) * 100)
      if (d < 8) s$strokeWidth <- 1
      tag(list(base_element("ellipse", ctr[1] - ctr[3], ctr[2] - ctr[3], d, d, s)))
    },
    line = ,
    polyline = {
      if (is.null(stroke)) return(list())
      pts <- if (nm == "line") {
        matrix(num_attrs(node, c("x1", "y1", "x2", "y2")), ncol = 2, byrow = TRUE)
      } else {
        parse_points(xml2::xml_attr(node, "points"))
      }
      pts <- pts * .svg_k
      pieces <- if (!is.null(clip) && in_panel) clip_polyline(pts, clip) else list(pts)
      s <- element_style(stroke, NULL, sw, dash_style(st, sw), opts, opacity = op_stroke * 100)
      r <- if (in_panel && identical(s$strokeStyle, "dashed") && op_stroke < 0.6) "grid" else role
      tag(lapply(Filter(function(m) nrow(m) >= 2, pieces), function(m) {
        el <- linear_element("line", m, s, 0, NULL, NULL, NULL, NULL)
        el <- set_null(el, "startArrowhead")
        el <- set_null(el, "endArrowhead")
        el$polygon <- FALSE
        el
      }), r)
    },
    polygon = ,
    path = {
      polys <- if (nm == "polygon") {
        list(parse_points(xml2::xml_attr(node, "points")))
      } else {
        parse_path(xml2::xml_attr(node, "d"))
      }
      polys <- lapply(polys, function(m) m * .svg_k)
      if (!is.null(clip) && in_panel) polys <- lapply(polys, clip_polygon, rect = clip)
      polys <- Filter(function(m) !is.null(m) && nrow(m) >= 3, polys)
      if (length(polys) == 0) return(list())
      if (is.null(stroke) && opts$outline && !is.null(fill)) {
        stroke <- ink_for(fill)
        sw <- 2
      }
      s <- element_style(stroke, fill, sw, dash_style(st, sw), opts,
                         opacity = (if (is.null(fill)) op_stroke else op_fill) * 100)
      tag(lapply(polys, function(m) {
        if (any(m[1, ] != m[nrow(m), ])) m <- rbind(m, m[1, ])
        el <- linear_element("line", m, s, 0, NULL, NULL, NULL, NULL)
        el <- set_null(el, "startArrowhead")
        el <- set_null(el, "endArrowhead")
        el$polygon <- TRUE
        el
      }))
    },
    text = convert_text(node, st, fill, op_fill, clip, opts, tag),
    image = convert_image(node, state, tag),
    list()
  )
}

convert_text <- function(node, st, fill, opacity, clip, opts, tag) {
  label <- xml2::xml_text(node)
  if (!nzchar(trimws(label))) return(list())
  size <- as.numeric(sub("px$", "", st[["font-size"]] %||% "12")) * .svg_k
  family <- gsub("[\"']", "", st[["font-family"]] %||% "")
  font <- opts$font %||% tryCatch(resolve_font(family), error = function(e) resolve_font("Helvetica"))
  anchor <- xml2::xml_attr(node, "text-anchor")
  hj <- switch(if (is.na(anchor)) "start" else anchor, middle = 0.5, end = 1, 0)
  tr <- xml2::xml_attr(node, "transform")
  angle <- 0
  if (!is.na(tr)) {
    nums <- as.numeric(regmatches(tr, gregexpr("-?[0-9.]+", tr))[[1]])
    ax <- nums[1] * .svg_k
    ay <- nums[2] * .svg_k
    if (length(nums) >= 3) angle <- nums[3]
  } else {
    ax <- as.numeric(xml2::xml_attr(node, "x")) * .svg_k
    ay <- as.numeric(xml2::xml_attr(node, "y")) * .svg_k
  }
  if (!is.null(clip) && !point_in_rect(ax, ay, clip, tol = 2)) return(list())
  s <- .default_style
  s$strokeColor <- as.character(fill %||% "#1e1e1e")
  s$backgroundColor <- "transparent"
  s$fontFamily <- if (is.null(font$custom)) font$id else font$name
  s$fontSize <- size
  s$opacity <- opacity * 100
  el <- text_element(label, 0, 0, s, text_align = c("left", "center", "right")[match(hj, c(0, 0.5, 1))])
  vo <- vertical_offset(font, size, size * el$lineHeight)
  # Box centre relative to the baseline anchor, then rotate (SVG degrees are
  # clockwise on screen, like Excalidraw's angle).
  dx <- -hj * el$width + el$width / 2
  dy <- -vo + el$height / 2
  a <- angle * pi / 180
  cx <- ax + dx * cos(a) - dy * sin(a)
  cy <- ay + dx * sin(a) + dy * cos(a)
  el$x <- cx - el$width / 2
  el$y <- cy - el$height / 2
  el$angle <- a %% (2 * pi)
  tag(list(el), "text")
}

convert_image <- function(node, state, tag) {
  href <- xml2::xml_attr(node, "href")
  if (is.na(href)) href <- xml2::xml_attr(node, "xlink:href")
  if (is.na(href) || !grepl("^data:", href)) return(list())
  r <- num_attrs(node, c("x", "y", "width", "height")) * .svg_k
  mime <- sub("^data:([^;]+);.*$", "\\1", href)
  file_id <- digest_string(href)
  state$files[[file_id]] <- list(mimeType = mime, id = file_id, dataURL = href,
                                 created = timestamp_ms(), lastRetrieved = timestamp_ms())
  s <- .default_style
  s$strokeColor <- "transparent"
  el <- base_element("image", r[1], r[2], r[3], r[4], s)
  el$fileId <- file_id
  el$status <- "saved"
  el$scale <- list(1, 1)
  el <- set_null(el, "crop")
  tag(list(el), "data")
}

digest_string <- function(x) {
  f <- tempfile()
  on.exit(unlink(f))
  writeLines(x, f, useBytes = TRUE)
  unname(tools::md5sum(f))
}

parse_points <- function(s) {
  v <- as.numeric(unlist(strsplit(trimws(s), "[ ,]+")))
  matrix(v, ncol = 2, byrow = TRUE)
}

# svglite paths use only M, L and Z.
parse_path <- function(d) {
  tokens <- regmatches(d, gregexpr("[MLZmlz]|-?[0-9.]+(?:e-?[0-9]+)?", d, perl = TRUE))[[1]]
  out <- list()
  cur <- numeric()
  i <- 1
  cmd <- "M"
  while (i <= length(tokens)) {
    t <- tokens[i]
    if (t %in% c("M", "m")) {
      if (length(cur) >= 6) out[[length(out) + 1]] <- matrix(cur, ncol = 2, byrow = TRUE)
      cur <- numeric()
      cmd <- "M"
      i <- i + 1
    } else if (t %in% c("L", "l")) {
      cmd <- "L"
      i <- i + 1
    } else if (t %in% c("Z", "z")) {
      if (length(cur) >= 6) out[[length(out) + 1]] <- matrix(cur, ncol = 2, byrow = TRUE)
      cur <- numeric()
      i <- i + 1
    } else {
      cur <- c(cur, as.numeric(tokens[i]), as.numeric(tokens[i + 1]))
      i <- i + 2
    }
  }
  if (length(cur) >= 6) out[[length(out) + 1]] <- matrix(cur, ncol = 2, byrow = TRUE)
  out
}

point_in_rect <- function(x, y, r, tol = 0) {
  x >= r[1] - tol && x <= r[1] + r[3] + tol && y >= r[2] - tol && y <= r[2] + r[4] + tol
}

clip_rect <- function(r, clip) {
  x0 <- max(r[1], clip[1]); y0 <- max(r[2], clip[2])
  x1 <- min(r[1] + r[3], clip[1] + clip[3]); y1 <- min(r[2] + r[4], clip[2] + clip[4])
  if (x1 - x0 <= 0.01 || y1 - y0 <= 0.01) return(NULL)
  c(x0, y0, x1 - x0, y1 - y0)
}

# Liang-Barsky clipping of a polyline; returns the visible pieces.
clip_polyline <- function(m, rect) {
  b <- c(rect[1], rect[2], rect[1] + rect[3], rect[2] + rect[4])
  if (all(m[, 1] >= b[1] & m[, 1] <= b[3] & m[, 2] >= b[2] & m[, 2] <= b[4])) return(list(m))
  pieces <- list()
  cur <- NULL
  for (i in seq_len(nrow(m) - 1)) {
    p0 <- m[i, ]; p1 <- m[i + 1, ]
    d <- p1 - p0
    t0 <- 0; t1 <- 1; ok <- TRUE
    p <- c(-d[1], d[1], -d[2], d[2])
    q <- c(p0[1] - b[1], b[3] - p0[1], p0[2] - b[2], b[4] - p0[2])
    for (k in 1:4) {
      if (p[k] == 0) {
        if (q[k] < 0) ok <- FALSE
      } else {
        r <- q[k] / p[k]
        if (p[k] < 0) { if (r > t1) ok <- FALSE else if (r > t0) t0 <- r }
        else { if (r < t0) ok <- FALSE else if (r < t1) t1 <- r }
      }
    }
    if (!ok || t0 > t1) {
      if (!is.null(cur)) { pieces[[length(pieces) + 1]] <- cur; cur <- NULL }
      next
    }
    a <- p0 + t0 * d; z <- p0 + t1 * d
    if (is.null(cur)) cur <- rbind(a) else if (t0 > 0) {
      pieces[[length(pieces) + 1]] <- cur
      cur <- rbind(a)
    }
    cur <- rbind(cur, z)
    if (t1 < 1) { pieces[[length(pieces) + 1]] <- cur; cur <- NULL }
  }
  if (!is.null(cur)) pieces[[length(pieces) + 1]] <- cur
  lapply(pieces, function(x) { colnames(x) <- c("x", "y"); unname(x) })
}

# Sutherland-Hodgman clipping of a polygon against a rectangle.
clip_polygon <- function(m, rect) {
  if (is.null(m)) return(NULL)
  b <- c(rect[1], rect[2], rect[1] + rect[3], rect[2] + rect[4])
  if (all(m[, 1] >= b[1] & m[, 1] <= b[3] & m[, 2] >= b[2] & m[, 2] <= b[4])) return(m)
  edges <- list(
    list(inside = function(p) p[1] >= b[1], cut = function(p, q) c(b[1], p[2] + (q[2] - p[2]) * (b[1] - p[1]) / (q[1] - p[1]))),
    list(inside = function(p) p[1] <= b[3], cut = function(p, q) c(b[3], p[2] + (q[2] - p[2]) * (b[3] - p[1]) / (q[1] - p[1]))),
    list(inside = function(p) p[2] >= b[2], cut = function(p, q) c(p[1] + (q[1] - p[1]) * (b[2] - p[2]) / (q[2] - p[2]), b[2])),
    list(inside = function(p) p[2] <= b[4], cut = function(p, q) c(p[1] + (q[1] - p[1]) * (b[4] - p[2]) / (q[2] - p[2]), b[4]))
  )
  pts <- lapply(seq_len(nrow(m)), function(i) m[i, ])
  for (e in edges) {
    if (length(pts) == 0) return(NULL)
    out <- list()
    for (i in seq_along(pts)) {
      cur <- pts[[i]]
      prev <- pts[[if (i == 1) length(pts) else i - 1]]
      if (e$inside(cur)) {
        if (!e$inside(prev)) out[[length(out) + 1]] <- e$cut(prev, cur)
        out[[length(out) + 1]] <- cur
      } else if (e$inside(prev)) {
        out[[length(out) + 1]] <- e$cut(prev, cur)
      }
    }
    pts <- out
  }
  if (length(pts) < 3) return(NULL)
  do.call(rbind, pts)
}
