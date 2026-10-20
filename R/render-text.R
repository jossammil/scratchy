# Text layout for the native renderer, following Excalidraw's SVG export:
# one line per row, baseline at i * lineHeightPx + getVerticalOffset(), x
# anchored by textAlign, rotated around the element's centre.

text_layout <- function(el) {
  font <- element_font(el)
  size <- el$fontSize %||% 20
  lh <- el$lineHeight %||% font_metrics(font)$line_height
  lh_px <- size * lh
  lines <- strsplit(normalize_text(el$text %||% ""), "\n", fixed = TRUE)[[1]]
  if (length(lines) == 0) lines <- ""
  vo <- vertical_offset(font, size, lh_px)
  align <- el$textAlign %||% "left"
  anchor_x <- switch(align, center = el$width / 2, right = el$width, 0)
  list(
    font = font, size = size, lines = lines, align = align,
    anchor_x = anchor_x,
    baselines = (seq_along(lines) - 1) * lh_px + vo,
    widths = text_widths(lines, font, size),
    color = el$strokeColor %||% "#1e1e1e",
    cx = el$width / 2, cy = el$height / 2,
    x = el$x, y = el$y, angle = el$angle %||% 0,
    emoji = emoji_rasters(lines)
  )
}

is_emoji_cp <- function(cp) {
  (cp >= 0x1F000 & cp <= 0x1FAFF) | (cp >= 0x2600 & cp <= 0x27BF) |
    (cp >= 0x2B00 & cp <= 0x2BFF) | cp == 0x2764
}

.emoji_cache <- new.env(parent = emptyenv())

# Colour emoji have no outlines, so render each one once with ragg (which
# draws colour emoji) and crop it to its ink. Done when the grob is built,
# not while drawing, so switching devices is safe.
emoji_rasters <- function(lines) {
  chars <- unique(unlist(strsplit(lines, "")))
  if (length(chars) == 0) return(list())
  cps <- vapply(chars, function(ch) utf8ToInt(ch)[1], 1)
  emo <- chars[is_emoji_cp(cps)]
  if (length(emo) == 0 || !requireNamespace("ragg", quietly = TRUE)) return(list())
  stats::setNames(lapply(emo, render_emoji), emo)
}

render_emoji <- function(ch) {
  hit <- .emoji_cache[[ch]]
  if (!is.null(hit)) return(hit)
  cur <- grDevices::dev.cur()
  cap <- ragg::agg_capture(width = 160, height = 160, units = "px", res = 72, background = "transparent")
  dev <- grDevices::dev.cur()
  out <- tryCatch({
    grid::grid.text(ch, gp = grid::gpar(fontsize = 96))
    r <- as.matrix(grDevices::as.raster(cap(native = FALSE)))
    ink <- which(substr(r, 8, 9) != "00" & nchar(r) == 9, arr.ind = TRUE)
    if (nrow(ink) == 0) NULL else r[min(ink[, 1]):max(ink[, 1]), min(ink[, 2]):max(ink[, 2]), drop = FALSE]
  }, error = function(e) NULL, finally = {
    grDevices::dev.off(dev)
    if (cur > 1) grDevices::dev.set(cur)
  })
  if (!is.null(out)) .emoji_cache[[ch]] <- out
  out
}

rotate_local <- function(x, y, cx, cy, a, ox, oy) {
  if (a == 0) return(list(x = x + ox, y = y + oy))
  dx <- x - cx
  dy <- y - cy
  list(x = dx * cos(a) - dy * sin(a) + cx + ox,
       y = dx * sin(a) + dy * cos(a) + cy + oy)
}

.glyph_cache <- new.env(parent = emptyenv())

glyph_outline_cached <- function(index, path, font_index, size) {
  key <- paste(path, font_index, index, size, sep = "|")
  hit <- .glyph_cache[[key]]
  if (!is.null(hit)) return(hit)
  o <- tryCatch(
    systemfonts::glyph_outline(index, path = path, index = font_index, size = size, tolerance = 0.1),
    error = function(e) NULL
  )
  if (is.null(o) || nrow(o) == 0) o <- data.frame(glyph = integer(), contour = integer(), x = numeric(), y = numeric())
  .glyph_cache[[key]] <- o
  o
}

# Glyph outlines in scene px: list(x, y, id) with one id per contour, drawn as
# a single path with the winding rule. Colour emoji come back as `rasters`:
# pre-rendered bitmaps with their box in local px.
text_outlines <- function(lay) {
  xs <- list(); ys <- list(); ids <- list(); n <- 0L
  rasters <- list()
  for (i in seq_along(lay$lines)) {
    line <- lay$lines[[i]]
    if (!nzchar(trimws(line))) next
    x0 <- lay$anchor_x - switch(lay$align, center = lay$widths[i] / 2, right = lay$widths[i], 0)
    sh <- textshaping::shape_text(line, family = lay$font$family, size = lay$size, res = 72)$shape
    chars <- strsplit(line, "")[[1]]
    for (g in seq_len(nrow(sh))) {
      ch <- chars[sh$glyph[g]]
      if (!is.na(ch) && !is.null(lay$emoji[[ch]])) {
        r <- glyph_box(ch, sh$font_path[g], sh$font_index[g], lay$size)
        if (!is.null(r)) {
          r$raster <- lay$emoji[[ch]]
          r$x <- x0 + sh$x_offset[g] + r$x
          r$y <- lay$baselines[i] - r$y
          rasters[[length(rasters) + 1]] <- r
        }
        next
      }
      o <- glyph_outline_cached(sh$index[g], sh$font_path[g], sh$font_index[g], lay$size)
      if (nrow(o) == 0) next
      for (ct in unique(o$contour)) {
        sel <- o$contour == ct
        n <- n + 1L
        xs[[n]] <- x0 + sh$x_offset[g] + o$x[sel]
        ys[[n]] <- lay$baselines[i] - o$y[sel]
        ids[[n]] <- rep(n, sum(sel))
      }
    }
  }
  out <- list(rasters = lapply(rasters, function(r) {
    ctr <- rotate_local(r$x + r$w / 2, r$y + r$h / 2, lay$cx, lay$cy, lay$angle, lay$x, lay$y)
    r$cx <- ctr$x
    r$cy <- ctr$y
    r
  }))
  if (n > 0) {
    p <- rotate_local(unlist(xs), unlist(ys), lay$cx, lay$cy, lay$angle, lay$x, lay$y)
    out$x <- p$x
    out$y <- p$y
    out$id <- unlist(ids)
  }
  if (n == 0 && length(rasters) == 0) return(NULL)
  out
}

# A glyph's ink box: x from the pen position, y = top of the box above the
# baseline, w/h in px.
glyph_box <- function(ch, path, font_index, size) {
  tryCatch({
    gi <- systemfonts::glyph_info(ch, path = path, index = font_index, size = size)
    if (gi$width[1] <= 0) NULL else
      list(x = gi$x_bearing[1], y = gi$y_bearing[1], w = gi$width[1], h = gi$height[1])
  }, error = function(e) NULL)
}

# Baseline anchor points for drawing text with real fonts.
text_anchors <- function(lay) {
  hj <- switch(lay$align, center = 0.5, right = 1, 0)
  p <- rotate_local(rep(lay$anchor_x, length(lay$lines)), lay$baselines,
                    lay$cx, lay$cy, lay$angle, lay$x, lay$y)
  list(x = p$x, y = p$y, hjust = hj, rot = -lay$angle * 180 / pi)
}
