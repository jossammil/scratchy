#' Animate a scene drawing itself
#'
#' Saves a scene as an animated SVG in which the drawing sketches itself:
#' elements appear one after another in z-order, each stroke traced from start
#' to end (CSS `stroke-dasharray` animations), fills fade in once their
#' outline is done, and text is written in letter by letter. The strokes are
#' the native renderer's, so the finished drawing matches [exc_save()]. Save
#' to a `.gif` file to record the animation in headless Chrome instead.
#'
#' The SVG plays in web browsers, also inside `<img>` tags, slides and README
#' files. Viewers who ask their system for reduced motion, and programs that
#' don't run CSS animations, see the finished drawing.
#'
#' @param scene An `exc_scene`.
#' @param file Output path ending in `.svg` or `.gif`. GIFs are recorded in
#'   Chrome or Chromium (through the chromote package) and put together with
#'   the gifski or magick package.
#' @param duration Seconds from blank canvas to finished drawing. Each element
#'   gets time in proportion to how much it has to draw.
#' @param loop Replay forever, showing the finished drawing for `hold`
#'   seconds between plays. `FALSE` plays once and keeps the drawing.
#' @param hold Seconds the finished drawing stays up before a loop starts
#'   again.
#' @param text How text appears: `"write"` letter by letter, `"fade"` each
#'   text element as a whole.
#' @param padding Space around the drawing, in px.
#' @param background Draw the background colour (`FALSE` = transparent).
#' @param paper Optional paper background; see [exc_papers()]. Defaults to
#'   the paper set by [exc_restyle()], if any.
#' @param frames Draw frame outlines and names.
#' @param scale Size: 1 = one pixel per scene px. For GIFs this is the pixel
#'   density, as in [exc_save()].
#' @param fps Frames per second for GIFs (at most 50).
#' @return `file`, invisibly.
#' @export
#' @examples
#' s <- exc_scene(
#'   exc_rect(0, 0, 160, 80, label = "Idea", fill = "yellow"),
#'   exc_arrow(c(170, 270), c(40, 40)),
#'   exc_ellipse(280, 0, 150, 80, label = "Chart", fill = "blue", fill_style = "hachure")
#' )
#' f <- tempfile(fileext = ".svg")
#' exc_animate(s, f, duration = 3)
#' \dontrun{
#' browseURL(f)
#' # A looping GIF (needs Chrome and the gifski or magick package)
#' exc_animate(s, "idea.gif", loop = TRUE)
#' }
exc_animate <- function(scene, file, duration = 5, loop = FALSE, hold = 2,
                        text = c("write", "fade"), padding = 10, background = TRUE,
                        paper = NULL, frames = TRUE, scale = 1, fps = 20) {
  check_scene(scene)
  text <- match.arg(text)
  check_positive(duration)
  check_positive(hold, zero = TRUE)
  check_positive(scale)
  check_positive(fps)
  ext <- tolower(tools::file_ext(file))
  if (!ext %in% c("svg", "gif")) cli::cli_abort("Can't animate to {.val {ext}} files. Use svg or gif.")
  if (ext == "gif") {
    if (fps > 50) cli::cli_abort("{.arg fps} must be at most 50: GIFs time frames in hundredths of a second.")
    encoder <- gif_encoder()
  }
  g <- exc_grob(scene, padding = padding, background = background, text = "outline",
                frames = frames, paper = paper)
  anim <- animation_svg(g, scene, duration = duration, loop = loop, hold = hold, text = text,
                        scale = if (ext == "svg") scale else 1)
  if (ext == "svg") {
    write_utf8(anim$svg, file)
  } else {
    svg_file <- tempfile(fileext = ".svg")
    on.exit(unlink(svg_file), add = TRUE)
    write_utf8(anim$svg, svg_file)
    record_gif(svg_file, file, anim, scale = scale, fps = fps, loop = loop, encoder = encoder,
               transparent = !isTRUE(g$background) || is_transparent(g$bg))
  }
  invisible(file)
}

check_positive <- function(x, zero = FALSE, arg = rlang::caller_arg(x)) {
  ok <- is.numeric(x) && length(x) == 1 && is.finite(x) && (x > 0 || (zero && x == 0))
  if (!ok) cli::cli_abort("{.arg {arg}} must be a {if (zero) 'non-negative' else 'positive'} number.")
  invisible(x)
}

write_utf8 <- function(lines, file) {
  con <- file(file, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(paste(lines, collapse = "\n"), "\n"))), con)
}

# ---- building the SVG ---------------------------------------------------------

# Each element becomes a unit of pieces (one SVG element each). A piece has a
# `phase` that sets when it animates within its element's time slot:
# "draw" pieces are traced one after another, "write" pieces (glyphs) are
# staggered, "fade" pieces fade in over the slot and "after" pieces (fills)
# fade in once the slot is over. `render(k)` returns the markup, animated by
# the keyframes named `k`; consecutive pieces with the same `wrap` share a
# group carrying those attributes (stroke colour and width, say).
animation_svg <- function(g, scene, duration, loop, hold, text, scale) {
  cv <- whole_px_canvas(g$canvas)
  prefix <- paste0("e", substr(rlang::hash(list(scene$elements, duration, loop, hold, text)), 1, 5))
  els <- live_elements(scene)
  by_id <- stats::setNames(els, vapply(els, function(e) e$id %||% "", ""))
  units <- lapply(g$items, function(it) {
    anim_unit(it, by_id[[it$id %||% ""]], text, g$frames, scene$files, prefix)
  })
  units <- compact(units)
  fade <- min(max(duration * 0.06, 0.1), 0.5, duration / 3)
  units <- schedule_units(units, duration, fade)
  cycle <- if (loop) duration + hold else duration
  fade_out <- if (loop) min(0.5, hold / 2) else 0

  clip_ids <- character()
  css <- character()
  body <- character()
  k <- 0L
  for (u in units) {
    inner <- character()
    open <- NULL
    for (p in u$pieces) {
      k <- k + 1L
      name <- paste0(prefix, "-k", k)
      css[k] <- anim_keyframes(name, p$a / cycle, p$b / cycle, p$prop, p$hidden %||% 0)
      if (!identical(p$wrap, open)) {
        inner <- c(inner, if (!is.null(open)) "</g>", if (!is.null(p$wrap)) paste0("<g ", p$wrap, ">"))
        open <- p$wrap
      }
      inner <- c(inner, p$render(name))
    }
    if (!is.null(open)) inner <- c(inner, "</g>")
    attrs <- if (u$opacity < 1) sprintf(' opacity="%s"', fmt_num(u$opacity, 3)) else ""
    fb <- if (!is.null(u$frame_id)) g$frame_boxes[[u$frame_id]] else NULL
    if (!is.null(fb)) {
      if (!u$frame_id %in% names(clip_ids)) {
        clip_ids[[u$frame_id]] <- sprintf("%s-c%d", prefix, length(clip_ids) + 1L)
      }
      attrs <- paste0(attrs, sprintf(' clip-path="url(#%s)"', clip_ids[[u$frame_id]]))
    }
    body <- c(body, paste0(if (nzchar(attrs)) paste0("<g", attrs, ">"), paste(inner, collapse = ""),
                           if (nzchar(attrs)) "</g>"))
  }
  clips <- vapply(names(clip_ids), function(id) {
    b <- g$frame_boxes[[id]]
    sprintf('<clipPath id="%s"><rect x="%s" y="%s" width="%s" height="%s"/></clipPath>',
            clip_ids[[id]], fmt_num(b[1]), fmt_num(b[2]), fmt_num(b[3]), fmt_num(b[4]))
  }, "")
  animated <- sprintf(".%s-s>*,.%s-t>*,.%s-a", prefix, prefix, prefix)

  svg <- c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="%s %s %s %s">',
            fmt_num(cv[["w"]] * scale), fmt_num(cv[["h"]] * scale),
            fmt_num(cv[["x0"]]), fmt_num(cv[["y0"]]), fmt_num(cv[["w"]]), fmt_num(cv[["h"]])),
    "<style>",
    sprintf(".%s-s{fill:none;stroke-linecap:round;stroke-linejoin:round}", prefix),
    sprintf("%s{animation:%ss linear %s both}", animated, fmt_num(cycle, 3), if (loop) "infinite" else "1"),
    sprintf("@media (prefers-reduced-motion:reduce){%s{animation:none!important}}", animated),
    css,
    if (fade_out > 0) {
      sprintf("@keyframes %s-out{0%%,%s%%{opacity:1}100%%{opacity:0}}", prefix,
              fmt_num(100 * (cycle - fade_out) / cycle))
    },
    "</style>",
    if (length(clips)) c("<defs>", clips, "</defs>"),
    if (isTRUE(g$background) && !is_transparent(g$bg)) {
      sprintf('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>', fmt_num(cv[["x0"]]),
              fmt_num(cv[["y0"]]), fmt_num(cv[["w"]]), fmt_num(cv[["h"]]), xml_attr(g$bg))
    },
    paper_svg(g$paper, cv),
    if (fade_out > 0) sprintf('<g %s>', animated_attrs(prefix, paste0(prefix, "-out"))) else "<g>",
    body,
    "</g>",
    "</svg>"
  )
  list(svg = svg, width = cv[["w"]], height = cv[["h"]], duration = duration, cycle = cycle,
       fade_out = fade_out, pieces = k)
}

# Whole pixels, as exc_save() rounds them, keeping the drawing centred.
whole_px_canvas <- function(cv) {
  w <- max(1, round(cv[["w"]]))
  h <- max(1, round(cv[["h"]]))
  c(x0 = cv[["x0"]] - (w - cv[["w"]]) / 2, y0 = cv[["y0"]] - (h - cv[["h"]]) / 2, w = w, h = h)
}

anim_unit <- function(it, el, text, frames, files, prefix) {
  pieces <- switch(it$type,
    text = text_pieces(it$layout, text, prefix),
    image = image_pieces(it, el, files, prefix),
    frame = , magicframe = if (frames) frame_pieces(it, text, prefix),
    skip = NULL,
    rough_pieces(it$parts, el, prefix)
  )
  if (length(pieces) == 0) return(NULL)
  list(pieces = pieces, opacity = it$opacity, frame_id = it$frame_id)
}

# Outline strokes are traced path by path; fills (solid or sketched) fade in
# after the outline; a freehand stroke (a filled outline) is uncovered by a
# mask traced along the points it was drawn through.
rough_pieces <- function(parts, el, prefix) {
  out <- list()
  for (p in parts) {
    if (length(p$paths) == 0) next
    if (identical(p$role, "fill")) {
      out <- c(out, list(fill_piece(p, prefix)))
    } else if (p$kind == "stroke") {
      out <- c(out, lapply(p$paths, stroke_piece, color = p$color, width = p$width, prefix = prefix))
    } else {
      out <- c(out, list(ink_piece(p, el, prefix)))
    }
  }
  out
}

stroke_piece <- function(xy, color, width, prefix) {
  xy <- tidy_xy(xy)
  len <- polyline_length(xy)
  d <- svg_path_d(list(xy))
  wrap <- stroke_attrs(prefix, color, width)
  if (len < 0.5) {
    return(list(phase = "draw", len = len, prop = "stroke-opacity", wrap = wrap, render = function(k) {
      sprintf('<path style="animation-name:%s" d="%s"/>', k, d)
    }))
  }
  dash <- ceiling(len * 10) / 10
  # The dash covers the path when the offset is 0; at dash + 2 the path lies in the gap.
  list(phase = "draw", len = len, prop = "stroke-dashoffset", hidden = dash + 2, wrap = wrap,
       render = function(k) {
         sprintf('<path style="animation-name:%s" d="%s" stroke-dasharray="%s %s"/>', k, d,
                 fmt_num(dash + 1), fmt_num(dash + 2))
       })
}

stroke_attrs <- function(prefix, color, width) {
  sprintf('class="%s-s" stroke="%s" stroke-width="%s"', prefix, xml_attr(color), fmt_num(width))
}

fill_piece <- function(p, prefix) {
  d <- svg_path_d(lapply(p$paths, tidy_xy))
  if (p$kind == "stroke") {
    return(list(phase = "after", len = 0, prop = "stroke-opacity",
                wrap = stroke_attrs(prefix, p$color, p$width),
                render = function(k) sprintf('<path style="animation-name:%s" d="%s"/>', k, d)))
  }
  rule <- if (identical(p$rule, "evenodd")) ' fill-rule="evenodd"' else ""
  list(phase = "after", len = 0, prop = "fill-opacity", render = function(k) {
    sprintf('<path %s d="%s" fill="%s"%s/>', animated_attrs(prefix, k), d, xml_attr(p$color), rule)
  })
}

ink_piece <- function(p, el, prefix) {
  d <- svg_path_d(lapply(p$paths, tidy_xy))
  centre <- if (identical(el$type, "freedraw")) freedraw_centreline(el) else NULL
  len <- if (is.null(centre)) 0 else polyline_length(centre)
  if (len < 0.5) {
    return(list(phase = "draw", len = 0, prop = "fill-opacity", render = function(k) {
      sprintf('<path %s d="%s" fill="%s"/>', animated_attrs(prefix, k), d, xml_attr(p$color))
    }))
  }
  dash <- ceiling(len * 10) / 10
  pen <- (el$strokeWidth %||% 2) * 4.25 + 6
  list(phase = "draw", len = len, prop = "stroke-dashoffset", hidden = dash + 2, render = function(k) {
    paste0(
      sprintf(paste0('<mask id="%sm"><g %s><path style="animation-name:%s" d="%s" ',
                     'stroke-dasharray="%s %s"/></g></mask>'),
              k, stroke_attrs(prefix, "#fff", pen), k, svg_path_d(list(centre)), fmt_num(dash + 1),
              fmt_num(dash + 2)),
      sprintf('<path d="%s" fill="%s" mask="url(#%sm)"/>', d, xml_attr(p$color), k)
    )
  })
}

# The points a freehand stroke went through, placed like exc-shapes.js does.
freedraw_centreline <- function(el) {
  pts <- points_to_xy(el$points)
  if (nrow(pts) < 2) return(NULL)
  cx <- (min(pts[, 1]) + max(pts[, 1])) / 2
  cy <- (min(pts[, 2]) + max(pts[, 2])) / 2
  p <- rotate_local(pts[, 1], pts[, 2], cx, cy, el$angle %||% 0, el$x, el$y)
  tidy_xy(c(rbind(p$x, p$y)))
}

# Writing takes longer than drawing a line as long as the text is wide.
text_pieces <- function(lay, text, prefix) {
  o <- text_outlines(lay)
  if (is.null(o)) return(NULL)
  ink <- 2 * sum(lay$widths)
  glyphs <- list()
  if (!is.null(o$x)) {
    contours <- split(seq_along(o$x), o$id)
    glyph_of <- vapply(contours, function(i) o$glyph[i[1]], 1L)
    for (gl in unique(glyph_of)) {
      d <- svg_path_d(lapply(contours[glyph_of == gl], function(i) tidy_xy(c(rbind(o$x[i], o$y[i])))),
                      close = TRUE)
      glyphs[[length(glyphs) + 1]] <- list(glyph = gl, d = d)
    }
  }
  emoji <- lapply(o$rasters, function(r) {
    uri <- raster_data_uri(r$raster)
    if (is.null(uri)) return(NULL)
    rot <- if (lay$angle != 0) {
      sprintf(' transform="rotate(%s %s %s)"', fmt_num(lay$angle * 180 / pi, 3), fmt_num(r$cx), fmt_num(r$cy))
    } else {
      ""
    }
    list(glyph = r$glyph, image = sprintf(
      'href="%s" x="%s" y="%s" width="%s" height="%s" preserveAspectRatio="none"%s',
      uri, fmt_num(r$cx - r$w / 2), fmt_num(r$cy - r$h / 2), fmt_num(r$w), fmt_num(r$h), rot))
  })
  emoji <- compact(emoji)
  col <- xml_attr(lay$color)
  if (text == "fade") {
    d <- paste(vapply(glyphs, function(x) x$d, ""), collapse = "")
    shapes <- c(if (nzchar(d)) sprintf('<path d="%s" fill="%s"/>', d, col),
                vapply(emoji, function(x) paste0("<image ", x$image, "/>"), ""))
    if (length(shapes) == 0) return(NULL)
    return(list(list(phase = "fade", len = ink, prop = "opacity", render = function(k) {
      sprintf('<g %s>%s</g>', animated_attrs(prefix, k), paste(shapes, collapse = ""))
    })))
  }
  all <- c(glyphs, emoji)
  all <- all[order(vapply(all, function(x) x$glyph, 1))]
  wrap <- sprintf('class="%s-t" fill="%s"', prefix, col)
  lapply(all, function(x) {
    if (is.null(x$image)) {
      prop <- "fill-opacity"
      render <- function(k) sprintf('<path style="animation-name:%s" d="%s"/>', k, x$d)
    } else {
      prop <- "opacity"
      render <- function(k) sprintf('<image style="animation-name:%s" %s/>', k, x$image)
    }
    list(phase = "write", len = ink / length(all), prop = prop, wrap = wrap, render = render)
  })
}

raster_data_uri <- function(r) {
  if (!requireNamespace("png", quietly = TRUE)) return(NULL)
  rgba <- grDevices::col2rgb(r, alpha = TRUE) / 255
  img <- array(t(rgba), c(nrow(r), ncol(r), 4))
  paste0("data:image/png;base64,", gsub("\n", "", jsonlite::base64_enc(png::writePNG(img))))
}

image_pieces <- function(it, el, files, prefix) {
  b <- it$box
  rot <- if (b[5] != 0) {
    sprintf(' transform="rotate(%s %s %s)"', fmt_num(b[5] * 180 / pi, 3), fmt_num(b[1] + b[3] / 2),
            fmt_num(b[2] + b[4] / 2))
  } else {
    ""
  }
  box <- sprintf('x="%s" y="%s" width="%s" height="%s"%s', fmt_num(b[1]), fmt_num(b[2]), fmt_num(b[3]),
                 fmt_num(b[4]), rot)
  href <- files[[el$fileId %||% ""]]$dataURL
  list(list(phase = "fade", len = 100, prop = "opacity", render = function(k) {
    if (is.null(href)) {
      sprintf('<rect %s %s fill="#f1f3f5" stroke="#ced4da" stroke-dasharray="4 3"/>',
              animated_attrs(prefix, k), box)
    } else {
      sprintf('<image %s href="%s" %s/>', animated_attrs(prefix, k), xml_attr(href), box)
    }
  }))
}

frame_pieces <- function(it, text, prefix) {
  b <- it$box
  outline <- stroke_piece(round_rect_xy(b[1], b[2], b[3], b[4], .frame_style$radius),
                          .frame_style$strokeColor, .frame_style$strokeWidth, prefix)
  name <- if (!is.null(it$name) && nzchar(it$name)) text_pieces(text_layout(frame_label(it)), text, prefix)
  c(list(outline), name)
}

round_rect_xy <- function(x, y, w, h, r) {
  r <- min(r, w / 2, h / 2)
  arc <- function(cx, cy, from) {
    a <- seq(from, from + pi / 2, length.out = 7)
    c(rbind(cx + r * cos(a), cy + r * sin(a)))
  }
  c(x + r, y, arc(x + w - r, y + r, -pi / 2), arc(x + w - r, y + h - r, 0),
    arc(x + r, y + h - r, pi / 2), arc(x + r, y + r, pi))
}

# Give every element a time slot in z-order, as long as the work it does
# (plus a little, so tiny elements still show), and time its pieces within it.
schedule_units <- function(units, duration, fade) {
  work <- vapply(units, function(u) {
    sum(vapply(u$pieces, function(p) if (p$phase == "after") 0 else p$len, 1))
  }, 1)
  weight <- work + 40
  ends <- (duration - fade) * cumsum(weight) / sum(weight)
  starts <- c(0, ends[-length(ends)])
  for (i in seq_along(units)) {
    units[[i]]$pieces <- time_pieces(units[[i]]$pieces, starts[i], ends[i], fade, duration)
  }
  units
}

time_pieces <- function(pieces, s, e, fade, duration) {
  phase <- vapply(pieces, function(p) p$phase, "")
  len <- vapply(pieces, function(p) p$len, 1)
  drawn <- phase == "draw"
  written <- phase == "write"
  if (!any(drawn | written)) phase[phase == "after"] <- "fade"
  a <- b <- numeric(length(pieces))
  dl <- sum(len[drawn])
  wl <- sum(len[written])
  # Outlines (a frame's border) come before writing (its name).
  m <- if (!any(written)) {
    e
  } else if (!any(drawn)) {
    s
  } else {
    s + (e - s) * (if (dl + wl > 0) dl / (dl + wl) else 0.5)
  }
  if (any(drawn)) {
    l <- len[drawn]
    if (sum(l) == 0) l[] <- 1
    b[drawn] <- s + (m - s) * cumsum(l) / sum(l)
    a[drawn] <- c(s, b[drawn][-sum(drawn)])
  }
  if (any(written)) {
    n <- sum(written)
    each <- min(e - m, max(3 * (e - m) / n, 0.05))
    a[written] <- m + (e - m - each) * (seq_len(n) - 1) / max(1, n - 1)
    b[written] <- a[written] + each
  }
  faded <- phase == "fade"
  a[faded] <- s
  b[faded] <- min(duration, max(e, s + fade))
  after <- phase == "after"
  a[after] <- e
  b[after] <- min(duration, e + fade)
  for (i in seq_along(pieces)) {
    pieces[[i]]$a <- a[i]
    pieces[[i]]$b <- b[i]
  }
  pieces
}

# Keyframes for one piece: hidden until `a`, shown from `b` (fractions of the
# cycle) to the end, where the implicit 100% keyframe is the shown, static
# value. Paths fade with fill-/stroke-opacity: Chrome mishandles `opacity` on
# paths with an empty bounding box (dots, straight lines).
anim_keyframes <- function(name, a, b, prop, hidden = 0) {
  # Keyframes at the same offset merge, so keep the two apart.
  a <- round(100 * a, 2)
  b <- max(round(100 * b, 2), a + 0.01)
  if (b > 100) {
    a <- 99.99
    b <- 100
  }
  shown <- if (prop == "stroke-dashoffset") "0" else "1"
  sprintf("@keyframes %s{%s{%s:%s}%s%%{%s:%s}}", name,
          if (a == 0) "0%" else paste0("0%,", fmt_num(a), "%"), prop, fmt_num(hidden),
          fmt_num(b), prop, shown)
}

animated_attrs <- function(prefix, k) {
  sprintf('class="%s-a" style="animation-name:%s"', prefix, k)
}

paper_svg <- function(p, cv) {
  out <- vapply(paper_shapes(p, cv), function(sh) {
    if (sh$type == "segments") {
      if (length(sh$x0) == 0) return("")
      d <- paste0("M", fmt_num(sh$x0), " ", fmt_num(sh$y0), "L", fmt_num(sh$x1), " ", fmt_num(sh$y1),
                  collapse = "")
      sprintf('<path d="%s" stroke="%s" stroke-width="%s" fill="none"/>', d, xml_attr(sh$col),
              fmt_num(sh$width))
    } else {
      if (length(sh$x) == 0) return("")
      r <- rep_len(sh$r, length(sh$x))
      rr <- paste0(fmt_num(r), " ", fmt_num(r), " 0 1 0 ")
      d <- paste0("M", fmt_num(sh$x - r), " ", fmt_num(sh$y), "a", rr, fmt_num(2 * r), " 0a", rr,
                  fmt_num(-2 * r), " 0Z", collapse = "")
      sprintf('<path d="%s" fill="%s"/>', d, xml_attr(sh$col))
    }
  }, "")
  out[nzchar(out)]
}

# Path data with relative line-tos. Coordinates are already rounded (tidy_xy),
# so the steps add up exactly.
svg_path_d <- function(paths, close = FALSE) {
  d <- vapply(paths, function(xy) {
    n <- length(xy) %/% 2
    x <- xy[2 * seq_len(n) - 1]
    y <- xy[2 * seq_len(n)]
    paste0("M", fmt_num(x[1]), " ", fmt_num(y[1]),
           if (n > 1) paste0("l", paste(fmt_num(diff(x)), fmt_num(diff(y)), collapse = " ")),
           if (close) "Z")
  }, "")
  gsub(" -", "-", paste(d, collapse = ""), fixed = TRUE)
}

# Drop points that sit within `tol` px of the line through their neighbours
# (Douglas-Peucker; rough.js samples every curve finely) and round to 0.01 px.
tidy_xy <- function(xy, tol = 0.1) {
  n <- length(xy) %/% 2
  if (n > 2) {
    x <- xy[2 * seq_len(n) - 1]
    y <- xy[2 * seq_len(n)]
    keep <- logical(n)
    keep[c(1, n)] <- TRUE
    todo <- list(c(1L, n))
    while (length(todo)) {
      ij <- todo[[length(todo)]]
      todo[[length(todo)]] <- NULL
      if (ij[2] - ij[1] < 2) next
      k <- (ij[1] + 1L):(ij[2] - 1L)
      dx <- x[ij[2]] - x[ij[1]]
      dy <- y[ij[2]] - y[ij[1]]
      t <- if (dx == 0 && dy == 0) 0 else ((x[k] - x[ij[1]]) * dx + (y[k] - y[ij[1]]) * dy) / (dx^2 + dy^2)
      t <- pmin(pmax(t, 0), 1)
      dist <- sqrt((x[k] - x[ij[1]] - t * dx)^2 + (y[k] - y[ij[1]] - t * dy)^2)
      m <- which.max(dist)
      if (dist[m] > tol) {
        keep[k[m]] <- TRUE
        todo <- c(todo, list(c(ij[1], k[m]), c(k[m], ij[2])))
      }
    }
    xy <- c(rbind(x[keep], y[keep]))
  }
  round(xy, 2)
}

polyline_length <- function(xy) {
  n <- length(xy) %/% 2
  if (n < 2) return(0)
  x <- xy[2 * seq_len(n) - 1]
  y <- xy[2 * seq_len(n)]
  sum(sqrt(diff(x)^2 + diff(y)^2))
}

# Numbers for SVG: at most `digits` decimals, no trailing zeros.
fmt_num <- function(x, digits = 2) {
  s <- sub("\\.?0+$", "", sprintf(paste0("%.", digits, "f"), x))
  s[s == "-0"] <- "0"
  s
}

xml_attr <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

# ---- GIFs ---------------------------------------------------------------------

gif_encoder <- function() {
  if (requireNamespace("gifski", quietly = TRUE)) return("gifski")
  if (requireNamespace("magick", quietly = TRUE)) return("magick")
  cli::cli_abort(c("Saving a GIF needs the {.pkg gifski} or {.pkg magick} package.",
                   i = "Install one with {.code install.packages(\"gifski\")}."))
}

# Step the SVG's animations through time in headless Chrome, one screenshot
# per frame. Frames of the finished drawing (while a loop holds it) are taken
# once and repeated.
record_gif <- function(svg_file, gif_file, anim, scale, fps, loop, encoder, transparent) {
  if (loop) {
    times <- (seq_len(max(1, round(anim$cycle * fps))) - 1) / fps
  } else {
    times <- seq(0, anim$duration, by = 1 / fps)
    if (anim$duration - times[length(times)] > 1e-9) times <- c(times, anim$duration)
  }
  held <- times > anim$duration & times < anim$cycle - anim$fade_out - 1e-9
  first <- which(times >= anim$duration)[1]
  same_as <- ifelse(held & seq_along(times) > first, first, NA_integer_)
  dir <- tempfile("exc-frames-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  frames <- capture_frames(svg_file, times, anim$width, anim$height, scale, transparent, dir, same_as)
  width <- round(anim$width * scale)
  height <- round(anim$height * scale)
  if (encoder == "gifski") {
    gifski::gifski(frames, gif_file = gif_file, width = width, height = height, delay = 1 / fps,
                   loop = loop, progress = FALSE)
  } else {
    img <- magick::image_read(frames)
    gif <- magick::image_animate(img, delay = round(100 / fps), loop = if (loop) 0 else 1,
                                 optimize = !transparent)
    magick::image_write(gif, gif_file, format = "gif")
  }
  invisible(gif_file)
}

capture_frames <- function(svg_file, times, width, height, scale, transparent, dir, same_as) {
  rlang::check_installed("chromote")
  b <- chromote::ChromoteSession$new(width = width, height = height)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  b$Emulation$setDeviceMetricsOverride(width = width, height = height, deviceScaleFactor = scale,
                                       mobile = FALSE)
  if (transparent) b$Emulation$setDefaultBackgroundColorOverride(color = list(r = 0, g = 0, b = 0, a = 0))
  b$go_to(file_url(svg_file))
  js <- function(code) {
    res <- b$Runtime$evaluate(code, awaitPromise = TRUE, returnByValue = TRUE)
    if (!is.null(res$exceptionDetails)) {
      cli::cli_abort(c("Chrome couldn't play the animation:",
                       x = res$exceptionDetails$exception$description %||% res$exceptionDetails$text))
    }
    res$result$value
  }
  js("window.excAnimations = document.getAnimations(); window.excAnimations.forEach(a => a.pause()); 0")
  files <- file.path(dir, sprintf("frame%05d.png", seq_along(times)))
  for (i in seq_along(times)) {
    if (!is.na(same_as[i])) {
      files[i] <- files[same_as[i]]
      next
    }
    js(sprintf(paste0(
      "window.excAnimations.forEach(a => { a.currentTime = %s; });",
      "new Promise(r => { requestAnimationFrame(() => requestAnimationFrame(r)); setTimeout(r, 200); })"
    ), format(times[i] * 1000, scientific = FALSE)))
    shot <- b$Page$captureScreenshot(format = "png",
                                     clip = list(x = 0, y = 0, width = width, height = height, scale = 1))
    writeBin(jsonlite::base64_dec(shot$data), files[i])
  }
  files
}

file_url <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!startsWith(path, "/")) path <- paste0("/", path)
  paste0("file://", utils::URLencode(path))
}
