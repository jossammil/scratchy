# Element constructors. Each returns an `exc_elements` object: a list of
# Excalidraw element lists (a shape with a label is two elements). Elements
# are plain lists with Excalidraw's own JSON property names.

new_elements <- function(elements = list(), files = list()) {
  structure(elements, class = "exc_elements", files = files)
}

#' @export
c.exc_elements <- function(...) {
  parts <- list(...)
  els <- unlist(lapply(parts, function(p) as_element_list(p)), recursive = FALSE)
  files <- do.call(c, c(list(list()), lapply(parts, function(p) attr(p, "files") %||% p$files)))
  new_elements(els, files[!duplicated(names(files))])
}

#' @export
print.exc_elements <- function(x, ...) {
  types <- vapply(x, function(e) e$type, "")
  cat("<exc_elements> ", length(x), " element", if (length(x) != 1) "s", ": ",
      paste(types, collapse = ", "), "\n", sep = "")
  invisible(x)
}

# Anything holding elements -> plain list of element lists.
as_element_list <- function(x) {
  if (inherits(x, "exc_scene")) return(x$elements)
  if (inherits(x, "exc_elements")) return(unclass(x))
  if (is.list(x) && !is.null(x$type) && !is.null(x$id)) return(list(x))
  if (is.list(x)) return(unlist(lapply(x, as_element_list), recursive = FALSE))
  cli::cli_abort("Can't turn {.cls {class(x)}} into Excalidraw elements.")
}

base_element <- function(type, x, y, width, height, s, angle = 0, roundness = NULL,
                         group = NULL, id = NULL, seed = NULL, custom = NULL,
                         link = NULL, locked = FALSE) {
  el <- list(
    id = id %||% new_id(),
    type = type,
    x = x, y = y, width = width, height = height,
    angle = deg2rad(angle),
    strokeColor = s$strokeColor,
    backgroundColor = s$backgroundColor,
    fillStyle = s$fillStyle,
    strokeWidth = s$strokeWidth,
    strokeStyle = s$strokeStyle,
    roughness = s$roughness,
    opacity = s$opacity,
    groupIds = as.list(group %||% character()),
    frameId = NULL,
    index = NULL,
    roundness = roundness,
    seed = seed %||% new_seed(),
    version = 1,
    versionNonce = new_seed(),
    isDeleted = FALSE,
    boundElements = NULL,
    updated = timestamp_ms(),
    link = link,
    locked = locked
  )
  # list() keeps NULL entries only when written literally; re-assert them.
  for (n in c("frameId", "index", "roundness", "boundElements", "link")) {
    if (is.null(el[[n]])) el <- set_null(el, n)
  }
  if (!is.null(custom)) el$customData <- custom
  el
}

tag_element <- function(el, ...) {
  tags <- list(...)
  el$customData$excalidrawer[names(tags)] <- tags
  el
}

# A text element; `x`/`y` are the top-left of the text box.
text_element <- function(text, x, y, s, text_align = "left", vertical_align = "top",
                         angle = 0, container_id = NULL, group = NULL, id = NULL,
                         custom = NULL, wrap_width = NULL) {
  font <- resolve_font(s$fontFamily)
  size <- s$fontSize
  original <- normalize_text(text)
  shown <- if (!is.null(wrap_width)) wrap_text(original, wrap_width, font, size) else original
  m <- measure_text(shown, font, size)
  s$fontFamily <- font$id
  el <- base_element("text", x, y, m$width, m$height, s, angle = angle,
                     group = group, id = id, custom = custom)
  el$text <- shown
  el$fontSize <- size
  el$fontFamily <- font$id
  el$textAlign <- text_align
  el$verticalAlign <- vertical_align
  el$containerId <- container_id
  if (is.null(container_id)) el <- set_null(el, "containerId")
  el$originalText <- original
  el$autoResize <- TRUE
  el$lineHeight <- font_metrics(font)$line_height
  if (!is.null(font$custom)) el <- tag_element(el, font = font$custom)
  el
}

# Bind a centred label to a container element (rectangle, ellipse, diamond, arrow).
bind_label <- function(container, label, s, center) {
  s_text <- s
  s_text$backgroundColor <- "transparent"
  font <- resolve_font(s$fontFamily)
  max_w <- switch(container$type,
    ellipse = round(container$width / 2 * sqrt(2)) - .bound_text_padding * 2,
    diamond = round(container$width / 2) - .bound_text_padding * 2,
    arrow = max(0.7 * container$width, s$fontSize * 11),
    container$width - .bound_text_padding * 2
  )
  txt <- text_element(label, 0, 0, s_text, text_align = "center", vertical_align = "middle",
                      container_id = container$id, group = unlist(container$groupIds),
                      wrap_width = max_w)
  txt$x <- center[1] - txt$width / 2
  txt$y <- center[2] - txt$height / 2
  txt$angle <- container$angle
  container$boundElements <- c(container$boundElements, list(list(type = "text", id = txt$id)))
  list(container, txt)
}

shape_constructor <- function(type, x, y, width, height, label, args, style, roundness,
                              angle, group, id, custom, seed = NULL) {
  s <- resolve_style(style, args)
  el <- base_element(type, x, y, width, height, s, angle = angle, roundness = roundness,
                     group = group, id = id, custom = custom, seed = seed)
  if (is.null(label)) return(new_elements(list(el)))
  new_elements(bind_label(el, label, s, c(x + width / 2, y + height / 2)))
}

#' Excalidraw shapes: rectangles, ellipses and diamonds
#'
#' @param x,y Top-left corner of the shape's bounding box, in px.
#' @param width,height Size in px.
#' @param label Optional text drawn centred inside the shape. It stays
#'   attached to the shape when you edit it in Excalidraw.
#' @param ... Style properties such as `stroke`, `fill`, `fill_style`,
#'   `stroke_width`, `stroke_style`, `roughness`, `opacity`, `font` and
#'   `font_size`. See [exc_style()].
#' @param style An [exc_style()] to start from.
#' @param rounded Round the corners (rectangles and diamonds).
#' @param angle Rotation in degrees, clockwise, around the shape's centre.
#' @param group Group id(s) to put the element in. See [exc_group()].
#' @param id Element id. Generated if `NULL`.
#' @param custom A list stored in the element's `customData`.
#' @param seed The rough.js seed that decides the element's wobble. Random
#'   (from R's RNG) if `NULL`; change it to "re-roll" the hand-drawn look.
#' @return An `exc_elements` object.
#' @export
#' @examples
#' exc_rect(0, 0, 160, 80, label = "Hello", fill = "yellow", fill_style = "solid")
#' exc_ellipse(200, 0, 120, 80, fill = "#a5d8ff", fill_style = "hachure")
#' exc_diamond(360, 0, 120, 100, rounded = TRUE)
exc_rect <- function(x, y, width, height, label = NULL, ..., style = NULL,
                     rounded = FALSE, angle = 0, group = NULL, id = NULL, custom = NULL,
                     seed = NULL) {
  shape_constructor("rectangle", x, y, width, height, label, list(...), style,
                    if (rounded) list(type = 3) else NULL, angle, group, id, custom, seed)
}

#' @rdname exc_rect
#' @export
exc_ellipse <- function(x, y, width, height, label = NULL, ..., style = NULL,
                        angle = 0, group = NULL, id = NULL, custom = NULL, seed = NULL) {
  shape_constructor("ellipse", x, y, width, height, label, list(...), style,
                    NULL, angle, group, id, custom, seed)
}

#' @rdname exc_rect
#' @export
exc_diamond <- function(x, y, width, height, label = NULL, ..., style = NULL,
                        rounded = FALSE, angle = 0, group = NULL, id = NULL, custom = NULL,
                        seed = NULL) {
  shape_constructor("diamond", x, y, width, height, label, list(...), style,
                    if (rounded) list(type = 2) else NULL, angle, group, id, custom, seed)
}

#' Text
#'
#' @param text The text. Use `"\n"` for line breaks.
#' @param x,y Position of the anchor point in px.
#' @param ... Style properties: `stroke` (text colour), `font`, `font_size`,
#'   `opacity`. See [exc_style()].
#' @param hjust,vjust Where the anchor sits on the text box: 0 = left/top,
#'   0.5 = centre, 1 = right/bottom.
#' @param text_align `"left"`, `"center"` or `"right"`. Defaults from `hjust`.
#' @inheritParams exc_rect
#' @return An `exc_elements` object.
#' @export
#' @examples
#' exc_text("Hand-drawn!", 100, 50, font_size = 28, hjust = 0.5)
exc_text <- function(text, x, y, ..., hjust = 0, vjust = 0, text_align = NULL,
                     style = NULL, angle = 0, group = NULL, id = NULL, custom = NULL) {
  s <- resolve_style(style, list(...))
  s$backgroundColor <- "transparent"
  text_align <- text_align %||% (if (hjust >= 0.75) "right" else if (hjust >= 0.25) "center" else "left")
  el <- text_element(text, 0, 0, s, text_align = text_align, angle = angle,
                     group = group, id = id, custom = custom)
  el$x <- x - hjust * el$width
  el$y <- y - vjust * el$height
  new_elements(list(el))
}

linear_element <- function(type, pts, s, angle, roundness, group, id, custom, seed = NULL) {
  origin <- pts[1, ]
  rel <- sweep(pts, 2, origin)
  el <- base_element(type, origin[[1]], origin[[2]], diff(range(rel[, 1])), diff(range(rel[, 2])),
                     s, angle = angle, roundness = roundness, group = group, id = id,
                     custom = custom, seed = seed)
  el$points <- xy_to_points(rel)
  el <- set_null(el, "lastCommittedPoint")
  el <- set_null(el, "startBinding")
  el <- set_null(el, "endBinding")
  el
}

#' Lines, arrows and freehand strokes
#'
#' Points are absolute positions in px. Give `x` and `y` vectors, or a
#' two-column matrix or data frame as `x`.
#'
#' @param x,y Point coordinates.
#' @param closed Join the last point back to the first. Closed lines can be
#'   filled with `fill`.
#' @param curved Draw a smooth curve through the points instead of straight
#'   segments.
#' @param start,end Arrowheads: `NULL` for none, or one of `"arrow"`, `"bar"`,
#'   `"circle"`, `"circle_outline"`, `"triangle"`, `"triangle_outline"`,
#'   `"diamond"`, `"diamond_outline"`.
#' @param elbowed Draw the arrow with right-angle elbows.
#' @param label Optional text placed at the middle of the arrow.
#' @param pressures Optional pen pressures (0-1), one per point. If `NULL`,
#'   Excalidraw simulates pressure.
#' @inheritParams exc_rect
#' @return An `exc_elements` object.
#' @export
#' @examples
#' exc_line(c(0, 50, 100), c(0, 40, 0))
#' exc_line(c(0, 80, 40), c(0, 0, 60), closed = TRUE, fill = "green")
#' exc_arrow(c(0, 150), c(0, 0), label = "next")
#' exc_freedraw(cos(seq(0, 6, 0.2)) * 30, sin(seq(0, 6, 0.2)) * 30)
exc_line <- function(x, y = NULL, ..., style = NULL, closed = FALSE, curved = FALSE,
                     angle = 0, group = NULL, id = NULL, custom = NULL, seed = NULL) {
  pts <- as_xy(x, y)
  if (nrow(pts) < 2) cli::cli_abort("A line needs at least two points.")
  if (closed && any(pts[1, ] != pts[nrow(pts), ])) pts <- rbind(pts, pts[1, ])
  s <- resolve_style(style, list(...))
  el <- linear_element("line", pts, s, angle, if (curved) list(type = 2) else NULL,
                       group, id, custom, seed)
  el <- set_null(el, "startArrowhead")
  el <- set_null(el, "endArrowhead")
  el$polygon <- closed
  new_elements(list(el))
}

check_arrowhead <- function(a, arg) {
  if (is.null(a)) return(NULL)
  if (!a %in% .arrowheads) cli::cli_abort("{.arg {arg}} must be NULL or one of {.val {(.arrowheads)}}.")
  a
}

#' @rdname exc_line
#' @export
exc_arrow <- function(x, y = NULL, ..., start = NULL, end = "arrow", curved = FALSE,
                      elbowed = FALSE, label = NULL, style = NULL, angle = 0,
                      group = NULL, id = NULL, custom = NULL, seed = NULL) {
  pts <- as_xy(x, y)
  if (nrow(pts) < 2) cli::cli_abort("An arrow needs at least two points.")
  s <- resolve_style(style, list(...))
  el <- linear_element("arrow", pts, s, angle, if (curved) list(type = 2) else NULL,
                       group, id, custom, seed)
  el$startArrowhead <- check_arrowhead(start, "start")
  el$endArrowhead <- check_arrowhead(end, "end")
  if (is.null(start)) el <- set_null(el, "startArrowhead")
  if (is.null(end)) el <- set_null(el, "endArrowhead")
  el$elbowed <- elbowed
  if (is.null(label)) return(new_elements(list(el)))
  n <- nrow(pts)
  mid <- if (n %% 2 == 1) pts[(n + 1) / 2, ] else colMeans(pts[c(n / 2, n / 2 + 1), , drop = FALSE])
  new_elements(bind_label(el, label, s, mid))
}

#' @rdname exc_line
#' @export
exc_freedraw <- function(x, y = NULL, ..., pressures = NULL, style = NULL, angle = 0,
                         group = NULL, id = NULL, custom = NULL, seed = NULL) {
  pts <- as_xy(x, y)
  s <- resolve_style(style, list(...))
  el <- linear_element("freedraw", pts, s, angle, NULL, group, id, custom, seed)
  el$startBinding <- NULL
  el$endBinding <- NULL
  el$pressures <- as.list(pressures %||% numeric())
  el$simulatePressure <- is.null(pressures)
  # Excalidraw sets this when a stroke is finished; it closes the end cap.
  el$lastCommittedPoint <- el$points[[length(el$points)]]
  new_elements(list(el))
}

#' Images
#'
#' Embeds an image file (PNG, JPEG, GIF, SVG or WebP) in the scene.
#'
#' @param file Path to the image file.
#' @param x,y Top-left corner in px.
#' @param width,height Size in px. If only one is given the other keeps the
#'   image's aspect ratio; if neither, the image's own size is used (PNG, GIF
#'   and SVG only).
#' @inheritParams exc_rect
#' @return An `exc_elements` object carrying the image data.
#' @export
exc_image <- function(file, x, y, width = NULL, height = NULL, ..., angle = 0,
                      group = NULL, id = NULL, custom = NULL) {
  ext <- tolower(tools::file_ext(file))
  mime <- switch(ext, png = "image/png", jpg = , jpeg = "image/jpeg", gif = "image/gif",
                 svg = "image/svg+xml", webp = "image/webp",
                 cli::cli_abort("Unsupported image type {.val {ext}}."))
  bytes <- readBin(file, "raw", file.info(file)$size)
  dims <- image_size(bytes, ext)
  if (is.null(width) && is.null(height)) {
    if (is.null(dims)) cli::cli_abort("Give {.arg width} or {.arg height} for {.val {ext}} images.")
    width <- dims[1]
    height <- dims[2]
  } else if (is.null(height)) {
    height <- if (is.null(dims)) width else width * dims[2] / dims[1]
  } else if (is.null(width)) {
    width <- if (is.null(dims)) height else height * dims[1] / dims[2]
  }
  image_element(bytes, mime, x, y, width, height, ..., angle = angle, group = group,
                id = id, custom = custom)
}

image_element <- function(bytes, mime, x, y, width, height, ..., angle = 0, group = NULL,
                          id = NULL, custom = NULL) {
  f <- tempfile()
  on.exit(unlink(f))
  writeBin(bytes, f)
  file_id <- unname(tools::md5sum(f))
  s <- resolve_style(NULL, list(...))
  s$strokeColor <- "transparent"
  s$backgroundColor <- "transparent"
  el <- base_element("image", x, y, width, height, s, angle = angle, group = group,
                     id = id, custom = custom)
  el$fileId <- file_id
  el$status <- "saved"
  el$scale <- list(1, 1)
  el <- set_null(el, "crop")
  files <- list()
  files[[file_id]] <- list(
    mimeType = mime, id = file_id,
    dataURL = paste0("data:", mime, ";base64,", jsonlite::base64_enc(bytes)),
    created = timestamp_ms(), lastRetrieved = timestamp_ms()
  )
  new_elements(list(el), files)
}

image_size <- function(bytes, ext) {
  be <- function(b) sum(as.integer(b) * 256^(rev(seq_along(b)) - 1))
  le <- function(b) sum(as.integer(b) * 256^(seq_along(b) - 1))
  if (ext == "png" && length(bytes) > 24) return(c(be(bytes[17:20]), be(bytes[21:24])))
  if (ext == "gif" && length(bytes) > 10) return(c(le(bytes[7:8]), le(bytes[9:10])))
  if (ext == "svg") {
    txt <- rawToChar(bytes[seq_len(min(length(bytes), 4000))])
    vb <- regmatches(txt, regexec("viewBox=[\"']([^\"']+)[\"']", txt))[[1]]
    if (length(vb) == 2) {
      v <- as.numeric(strsplit(trimws(vb[2]), "[ ,]+")[[1]])
      if (length(v) == 4) return(v[3:4])
    }
    w <- regmatches(txt, regexec("width=[\"']([0-9.]+)", txt))[[1]]
    h <- regmatches(txt, regexec("height=[\"']([0-9.]+)", txt))[[1]]
    if (length(w) == 2 && length(h) == 2) return(as.numeric(c(w[2], h[2])))
  }
  NULL
}

#' Frames
#'
#' A frame is a named box that holds other elements. Excalidraw uses frames
#' for slides and for exporting part of a drawing.
#'
#' @param x,y,width,height Position and size in px.
#' @param name Frame title shown above it.
#' @param contents Elements to place inside the frame.
#' @inheritParams exc_rect
#' @return An `exc_elements` object: the contents followed by the frame.
#' @export
#' @examples
#' exc_frame(0, 0, 400, 300, "Slide 1", contents = exc_text("Hi", 20, 20))
exc_frame <- function(x, y, width, height, name = NULL, contents = NULL, id = NULL,
                      custom = NULL) {
  s <- resolve_style(NULL, list(stroke = .frame_style$strokeColor, roughness = 0,
                                fill = "transparent", fill_style = "solid"))
  fr <- base_element("frame", x, y, width, height, s, id = id, custom = custom)
  fr$name <- name
  if (is.null(name)) fr <- set_null(fr, "name")
  kids <- if (is.null(contents)) list() else as_element_list(contents)
  kids <- lapply(kids, function(e) {
    e$frameId <- fr$id
    e
  })
  new_elements(c(kids, list(fr)), attr(contents, "files") %||% list())
}

#' Group elements together
#'
#' Grouped elements select and move together in Excalidraw.
#'
#' @param ... `exc_elements` objects.
#' @param id Group id. Generated if `NULL`.
#' @return An `exc_elements` object.
#' @export
#' @examples
#' exc_group(exc_rect(0, 0, 50, 50), exc_text("box", 0, 60))
exc_group <- function(..., id = NULL) {
  els <- c.exc_elements(...)
  gid <- id %||% new_id()
  out <- lapply(unclass(els), function(e) {
    e$groupIds <- c(e$groupIds, list(gid))
    e
  })
  new_elements(out, attr(els, "files"))
}
