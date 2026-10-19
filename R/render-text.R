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
    x = el$x, y = el$y, angle = el$angle %||% 0
  )
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

# Glyph outlines in scene px: list(x, y, id) with one id per contour; draw as
# a single path with the winding rule.
text_outlines <- function(lay) {
  xs <- list(); ys <- list(); ids <- list(); n <- 0L
  for (i in seq_along(lay$lines)) {
    line <- lay$lines[[i]]
    if (!nzchar(trimws(line))) next
    x0 <- lay$anchor_x - switch(lay$align, center = lay$widths[i] / 2, right = lay$widths[i], 0)
    sh <- textshaping::shape_text(line, family = lay$font$family, size = lay$size, res = 72)$shape
    for (g in seq_len(nrow(sh))) {
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
  if (n == 0) return(NULL)
  p <- rotate_local(unlist(xs), unlist(ys), lay$cx, lay$cy, lay$angle, lay$x, lay$y)
  list(x = p$x, y = p$y, id = unlist(ids))
}

# Baseline anchor points for drawing text with real fonts.
text_anchors <- function(lay) {
  hj <- switch(lay$align, center = 0.5, right = 1, 0)
  p <- rotate_local(rep(lay$anchor_x, length(lay$lines)), lay$baselines,
                    lay$cx, lay$cy, lay$angle, lay$x, lay$y)
  list(x = p$x, y = p$y, hjust = hj, rot = -lay$angle * 180 / pi)
}
