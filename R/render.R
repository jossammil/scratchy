#' Draw a scene with grid
#'
#' Builds a grid grob that draws the scene the way Excalidraw does: rough.js
#' strokes and fills from each element's seed, Excalidraw's arrowheads, and
#' text in the bundled handwriting fonts. The sketchy geometry is computed
#' once; the grob rescales to whatever space it is drawn in, keeping the
#' aspect ratio.
#'
#' @param scene An `exc_scene`.
#' @param padding Space around the drawing, in px (Excalidraw uses 10).
#' @param background Draw the scene's background colour.
#' @param text How to draw text: `"outline"` turns glyphs into shapes (works
#'   on every device), `"font"` uses the registered font (needs ragg or
#'   svglite), `"auto"` picks `"font"` on those devices and `"outline"`
#'   elsewhere.
#' @param scale `NULL` to fit the drawing to the viewport, or a number of
#'   device pixels (at 96 dpi) per scene px for a fixed size.
#' @param frames Draw frame outlines and names.
#' @param paper Optional paper background: `"graph"`, `"dots"`, `"lines"`,
#'   `"kraft"`, `"blueprint"` or `"chalkboard"`. Defaults to the paper set by
#'   [exc_restyle()], if any.
#' @param name Grob name.
#' @return A grob of class `exc_grob`.
#' @export
#' @examples
#' s <- exc_scene(exc_rect(0, 0, 120, 60, label = "hi", fill = "yellow", fill_style = "hachure"))
#' grid::grid.newpage()
#' grid::grid.draw(exc_grob(s))
exc_grob <- function(scene, padding = 10, background = TRUE,
                     text = c("auto", "outline", "font"), scale = NULL,
                     frames = TRUE, paper = NULL, name = NULL) {
  check_scene(scene)
  text <- match.arg(text)
  els <- live_elements(scene)
  els <- Filter(function(e) (e$opacity %||% 100) > 0, els)
  bg <- scene$appState$viewBackgroundColor %||% "#ffffff"
  paper_info <- paper_spec(paper %||% scene$meta$paper)
  if (!is.null(paper_info$background)) bg <- paper_info$background
  bb <- exc_bbox(scene)
  # Converted plots keep the plot's own canvas (with its margins).
  if (!is.null(scene$meta$size)) {
    bb[["xmin"]] <- min(bb[["xmin"]], padding)
    bb[["ymin"]] <- min(bb[["ymin"]], padding)
    bb[["xmax"]] <- max(bb[["xmax"]], scene$meta$size[["width"]] - padding)
    bb[["ymax"]] <- max(bb[["ymax"]], scene$meta$size[["height"]] - padding)
  }
  if (frames) {
    for (e in els) {
      if (e$type == "frame" && !is.null(e$name)) bb[["ymin"]] <- min(bb[["ymin"]], e$y - 24)
    }
  }
  canvas <- c(x0 = bb[["xmin"]] - padding, y0 = bb[["ymin"]] - padding,
              w = max(1, bb[["xmax"]] - bb[["xmin"]] + 2 * padding),
              h = max(1, bb[["ymax"]] - bb[["ymin"]] + 2 * padding))

  drawable <- vapply(els, function(e) e$type %in% .rough_types, logical(1))
  parts <- vector("list", length(els))
  canvas_bg <- if (is_transparent(bg)) "#ffffff" else bg
  if (any(drawable)) parts[drawable] <- rough_parts(prepare_for_js(els[drawable], els), canvas_bg)
  frame_boxes <- list()
  for (e in els) if (e$type == "frame") frame_boxes[[e$id]] <- c(e$x, e$y, e$width, e$height)
  items <- lapply(seq_along(els), function(i) prepare_item(els[[i]], parts[[i]], scene$files))

  grid::gTree(items = items, canvas = canvas, bg = bg, background = background,
              text_mode = text, fixed_scale = scale, frames = frames,
              frame_boxes = frame_boxes, paper = paper_info, name = name, cl = "exc_grob")
}

# Extra inputs for the shape code:
# * Excalidraw hides the part of an arrow behind its label (a mask 5 px larger
#   than the text); pass that box so the strokes can be cut.
# * Presets may ask for extra bowing (stored in customData).
prepare_for_js <- function(drawables, all) {
  texts <- Filter(function(e) e$type == "text" && !is.null(e$containerId), all)
  by_container <- if (length(texts)) {
    stats::setNames(texts, vapply(texts, function(e) e$containerId, ""))
  } else {
    list()
  }
  lapply(drawables, function(e) {
    bowing <- e$customData$excalidrawer$bowing
    if (!is.null(bowing)) e$bowing <- bowing
    t <- if (e$type == "arrow") by_container[[e$id]] else NULL
    if (is.null(t) || !nzchar(trimws(t$text %||% ""))) return(e)
    p <- .bound_text_padding
    e$`__labelBox` <- c(t$x - p, t$y - p, t$x + t$width + p, t$y + t$height + p)
    e
  })
}

prepare_item <- function(el, parts, files) {
  item <- list(type = el$type, id = el$id, opacity = (el$opacity %||% 100) / 100,
               frame_id = el$frameId)
  if (el$type %in% .rough_types) {
    item$parts <- parts
  } else if (el$type == "text") {
    item$layout <- text_layout(el)
  } else if (el$type == "image") {
    item$raster <- image_raster(el, files)
    item$box <- c(el$x, el$y, el$width, el$height, el$angle %||% 0)
  } else if (el$type %in% c("frame", "magicframe")) {
    item$box <- c(el$x, el$y, el$width, el$height)
    item$name <- el$name
  } else {
    item$type <- "skip"
  }
  item
}

image_raster <- function(el, files) {
  f <- files[[el$fileId %||% ""]]
  if (is.null(f$dataURL)) return(NULL)
  b64 <- sub("^data:[^,]*,", "", f$dataURL)
  bytes <- jsonlite::base64_dec(b64)
  mime <- f$mimeType %||% ""
  tryCatch(
    switch(mime,
      "image/png" = if (requireNamespace("png", quietly = TRUE)) png::readPNG(bytes, native = FALSE),
      "image/jpeg" = if (requireNamespace("jpeg", quietly = TRUE)) jpeg::readJPEG(bytes),
      "image/svg+xml" = if (requireNamespace("rsvg", quietly = TRUE)) {
        rsvg::rsvg(bytes, width = max(64, ceiling(el$width * 3)))
      },
      NULL
    ),
    error = function(e) NULL
  )
}

#' @importFrom grid makeContent
#' @export
makeContent.exc_grob <- function(x) {
  cv <- x$canvas
  w_in <- grid::convertWidth(grid::unit(1, "npc"), "inches", valueOnly = TRUE)
  h_in <- grid::convertHeight(grid::unit(1, "npc"), "inches", valueOnly = TRUE)
  s <- if (is.null(x$fixed_scale)) min(w_in / cv[["w"]], h_in / cv[["h"]]) else x$fixed_scale / 96
  mode <- resolve_text_mode(x$text_mode)
  vp <- grid::viewport(
    width = grid::unit(cv[["w"]] * s, "inches"), height = grid::unit(cv[["h"]] * s, "inches"),
    xscale = c(cv[["x0"]], cv[["x0"]] + cv[["w"]]),
    yscale = c(-(cv[["y0"]] + cv[["h"]]), -cv[["y0"]]),
    name = "exc_canvas"
  )
  kids <- list()
  if (isTRUE(x$background) && !is_transparent(x$bg)) {
    kids <- c(kids, list(grid::rectGrob(gp = grid::gpar(fill = x$bg, col = NA))))
  }
  kids <- c(kids, paper_grobs(x$paper, cv, s))
  for (it in x$items) {
    g <- item_grob(it, s, mode, x$frames)
    if (is.null(g)) next
    fb <- if (!is.null(it$frame_id)) x$frame_boxes[[it$frame_id]] else NULL
    if (!is.null(fb)) g <- grid::gTree(children = grid::gList(g), vp = frame_clip_vp(fb))
    kids <- c(kids, list(g))
  }
  grid::setChildren(x, grid::gList(grid::gTree(children = do.call(grid::gList, kids), vp = vp)))
}

frame_clip_vp <- function(fb) {
  grid::viewport(x = grid::unit(fb[1], "native"), y = grid::unit(-fb[2], "native"),
                 width = grid::unit(fb[3], "native"), height = grid::unit(fb[4], "native"),
                 just = c("left", "top"), clip = "on",
                 xscale = c(fb[1], fb[1] + fb[3]), yscale = c(-(fb[2] + fb[4]), -fb[2]))
}

resolve_text_mode <- function(mode) {
  if (mode != "auto") return(mode)
  dev <- names(grDevices::dev.cur())
  if (grepl("^agg_|^devSVG", dev)) "font" else "outline"
}

with_alpha <- function(col, alpha) {
  if (alpha >= 1) return(col)
  grDevices::adjustcolor(col, alpha.f = alpha)
}

paths_xy <- function(paths) {
  xy <- unlist(paths, use.names = FALSE)
  n <- length(xy)
  list(x = xy[seq(1, n, 2)], y = -xy[seq(2, n, 2)], lens = lengths(paths) / 2)
}

item_grob <- function(it, s, mode, frames) {
  switch(it$type,
    text = text_grob(it$layout, s, mode, it$opacity),
    image = image_grob(it),
    frame = , magicframe = if (frames) frame_grob(it, s, mode) else NULL,
    skip = NULL,
    parts_grob(it$parts, s, it$opacity)
  )
}

parts_grob <- function(parts, s, alpha) {
  if (length(parts) == 0) return(NULL)
  gs <- lapply(parts, function(p) {
    if (length(p$paths) == 0) return(NULL)
    xy <- paths_xy(p$paths)
    if (p$kind == "fill") {
      grid::pathGrob(xy$x, xy$y, id.lengths = xy$lens, rule = p$rule %||% "winding",
                     default.units = "native",
                     gp = grid::gpar(fill = with_alpha(p$color, alpha), col = NA))
    } else {
      grid::polylineGrob(xy$x, xy$y, id.lengths = xy$lens, default.units = "native",
                         gp = grid::gpar(col = with_alpha(p$color, alpha), lwd = p$width * s * 96,
                                         lineend = "round", linejoin = "round"))
    }
  })
  gs <- compact(gs)
  if (length(gs) == 0) return(NULL)
  grid::gTree(children = do.call(grid::gList, gs))
}

text_grob <- function(lay, s, mode, alpha) {
  col <- with_alpha(lay$color, alpha)
  if (mode == "outline") {
    o <- text_outlines(lay)
    if (is.null(o)) return(NULL)
    kids <- list()
    if (!is.null(o$x)) {
      kids[[1]] <- grid::pathGrob(o$x, -o$y, id = o$id, rule = "winding", default.units = "native",
                                  gp = grid::gpar(fill = col, col = NA))
    }
    for (r in o$rasters) {
      kids[[length(kids) + 1]] <- if (lay$angle == 0) {
        grid::rasterGrob(r$raster, x = r$cx, y = -r$cy, width = r$w, height = r$h,
                         default.units = "native", interpolate = TRUE)
      } else {
        grid::rasterGrob(r$raster, interpolate = TRUE, vp = grid::viewport(
          x = grid::unit(r$cx, "native"), y = grid::unit(-r$cy, "native"),
          width = grid::unit(r$w, "native"), height = grid::unit(r$h, "native"),
          angle = -lay$angle * 180 / pi))
      }
    }
    return(grid::gTree(children = do.call(grid::gList, kids)))
  }
  a <- text_anchors(lay)
  grid::textGrob(lay$lines, x = a$x, y = -a$y, hjust = a$hjust, vjust = 0, rot = a$rot,
                 default.units = "native",
                 gp = grid::gpar(fontfamily = lay$font$family, fontsize = lay$size * s * 72, col = col))
}

image_grob <- function(it) {
  b <- it$box
  if (is.null(it$raster)) {
    return(grid::rectGrob(b[1], -b[2], b[3], b[4], just = c("left", "top"), default.units = "native",
                          gp = grid::gpar(col = "#ced4da", fill = "#f1f3f5", lty = 2)))
  }
  r <- grid::rasterGrob(it$raster, interpolate = TRUE)
  grid::gTree(children = grid::gList(r), vp = grid::viewport(
    x = grid::unit(b[1] + b[3] / 2, "native"), y = grid::unit(-(b[2] + b[4] / 2), "native"),
    width = grid::unit(b[3], "native"), height = grid::unit(b[4], "native"),
    angle = -b[5] * 180 / pi))
}

frame_grob <- function(it, s, mode) {
  b <- it$box
  outline <- grid::roundrectGrob(b[1], -b[2], b[3], b[4], just = c("left", "top"),
                                 r = grid::unit(.frame_style$radius * s, "inches"),
                                 default.units = "native",
                                 gp = grid::gpar(col = .frame_style$strokeColor, fill = NA,
                                                 lwd = .frame_style$strokeWidth * s * 96))
  if (is.null(it$name) || !nzchar(it$name)) return(outline)
  lbl <- list(text = it$name, x = b[1], y = b[2] - .frame_style$nameOffsetY - 14 * 1.25,
              width = b[3], height = 14 * 1.25, fontSize = 14, fontFamily = 2,
              lineHeight = 1.25, textAlign = "left", strokeColor = .frame_style$nameColor,
              angle = 0)
  grid::gTree(children = grid::gList(outline, text_grob(text_layout(lbl), s, mode, 1)))
}

#' @export
plot.exc_scene <- function(x, ...) {
  grid::grid.newpage()
  grid::grid.draw(exc_grob(x, ...))
  invisible(x)
}

#' @importFrom grid grid.draw
#' @export
grid.draw.exc_scene <- function(x, recording = TRUE) {
  grid::grid.draw(exc_grob(x), recording = recording)
}

# Draw scenes in R Markdown / Quarto chunks.
#' @exportS3Method knitr::knit_print
knit_print.exc_scene <- function(x, ...) {
  plot(x)
  invisible(x)
}
