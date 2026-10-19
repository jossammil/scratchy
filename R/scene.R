#' Create an Excalidraw scene
#'
#' A scene holds elements (shapes, text, arrows, images, frames), the
#' canvas settings (`appState`) and any embedded image files. It is stored
#' exactly as Excalidraw's JSON, so reading and writing files loses nothing.
#'
#' @param ... Elements: results of [exc_rect()], [exc_text()] and friends,
#'   other scenes, or lists of these.
#' @param background Canvas background colour.
#' @param app_state Extra `appState` settings to store in the file.
#' @return An `exc_scene` object.
#' @export
#' @examples
#' scene <- exc_scene(
#'   exc_rect(0, 0, 160, 80, label = "Idea", fill = "yellow"),
#'   exc_arrow(c(160, 260), c(40, 40)),
#'   exc_ellipse(260, 0, 140, 80, label = "Chart")
#' )
#' scene
exc_scene <- function(..., background = "#ffffff", app_state = list()) {
  parts <- list(...)
  els <- if (length(parts)) do.call(c.exc_elements, parts) else new_elements()
  app <- utils::modifyList(list(gridSize = 20, viewBackgroundColor = norm_color(background)),
                           app_state)
  if (is_transparent(app$viewBackgroundColor)) app$viewBackgroundColor <- "transparent"
  new_scene(unclass(els), app, attr(els, "files") %||% list())
}

new_scene <- function(elements, app_state, files) {
  structure(
    list(elements = ensure_indices(unname(elements)),
         appState = app_state,
         files = files),
    class = "exc_scene"
  )
}

ensure_indices <- function(elements) {
  keys <- lapply(elements, function(e) e$index)
  if (length(elements) == 0 || keys_in_order(keys)) return(elements)
  new <- index_keys(length(elements))
  for (i in seq_along(elements)) elements[[i]]$index <- new[[i]]
  elements
}

#' Add elements to a scene
#'
#' @param scene An `exc_scene`.
#' @param ... Elements to add on top of the existing ones.
#' @return The updated scene.
#' @export
#' @examples
#' exc_scene() |> exc_add(exc_text("Hello", 0, 0))
exc_add <- function(scene, ...) {
  check_scene(scene)
  add <- c.exc_elements(...)
  files <- c(scene$files, attr(add, "files"))
  new_scene(c(scene$elements, unclass(add)), scene$appState,
            files[!duplicated(names(files))])
}

check_scene <- function(x, arg = rlang::caller_arg(x)) {
  if (!inherits(x, "exc_scene")) cli::cli_abort("{.arg {arg}} must be an {.cls exc_scene}.")
  invisible(x)
}

live_elements <- function(scene) {
  Filter(function(e) !isTRUE(e$isDeleted), scene$elements)
}

#' @export
print.exc_scene <- function(x, ...) {
  els <- live_elements(x)
  cat("<exc_scene> ", length(els), " element", if (length(els) != 1) "s", sep = "")
  if (length(els)) {
    tab <- table(vapply(els, function(e) e$type, ""))
    cat(" (", paste(names(tab), tab, sep = ": ", collapse = ", "), ")", sep = "")
    bb <- exc_bbox(x)
    cat("\n  size: ", round(bb[["width"]]), " x ", round(bb[["height"]]), " px", sep = "")
  }
  cat("\n  background: ", x$appState$viewBackgroundColor %||% "#ffffff", sep = "")
  if (length(x$files)) cat("\n  images: ", length(x$files), sep = "")
  cat("\n")
  invisible(x)
}

#' Tidy view of a scene's elements
#'
#' One row per element with its main properties. Useful for finding
#' elements to change with [exc_modify()].
#'
#' @param x An `exc_scene`.
#' @param row.names,optional Ignored.
#' @param ... Ignored.
#' @return A data frame.
#' @export
as.data.frame.exc_scene <- function(x, row.names = NULL, optional = FALSE, ...) {
  els <- x$elements
  get <- function(name, na = NA) {
    vapply(els, function(e) {
      v <- e[[name]]
      if (is.null(v) || length(v) != 1) na else v
    }, na)
  }
  if (length(els) == 0) {
    return(data.frame(id = character(), type = character(), x = numeric(), y = numeric()))
  }
  data.frame(
    id = get("id", NA_character_),
    type = get("type", NA_character_),
    x = get("x", NA_real_),
    y = get("y", NA_real_),
    width = get("width", NA_real_),
    height = get("height", NA_real_),
    angle = get("angle", NA_real_) * 180 / pi,
    strokeColor = get("strokeColor", NA_character_),
    backgroundColor = get("backgroundColor", NA_character_),
    fillStyle = get("fillStyle", NA_character_),
    strokeWidth = get("strokeWidth", NA_real_),
    strokeStyle = get("strokeStyle", NA_character_),
    roughness = get("roughness", NA_real_),
    opacity = get("opacity", NA_real_),
    text = get("text", NA_character_),
    fontSize = get("fontSize", NA_real_),
    fontFamily = get("fontFamily", NA_real_),
    containerId = get("containerId", NA_character_),
    frameId = get("frameId", NA_character_),
    groupIds = vapply(els, function(e) paste(unlist(e$groupIds), collapse = ","), ""),
    role = vapply(els, function(e) e$customData$excalidrawer$role %||% NA_character_, ""),
    isDeleted = get("isDeleted", NA),
    stringsAsFactors = FALSE
  )
}

#' Change elements in a scene
#'
#' Select elements with a condition on the columns of
#' `as.data.frame(scene)` and set new property values.
#'
#' @param scene An `exc_scene`.
#' @param where A condition using columns such as `type`, `text`,
#'   `strokeColor` or `role`. `TRUE` selects everything.
#' @param ... Properties to set: style names as in [exc_style()] (`stroke`,
#'   `fill`, `roughness`, ...) or raw Excalidraw property names (`fontSize`,
#'   `text`, `x`, ...).
#' @return The updated scene.
#' @export
#' @examples
#' s <- exc_scene(exc_text("a", 0, 0), exc_rect(0, 30, 50, 50))
#' exc_modify(s, type == "rectangle", fill = "red", fill_style = "solid")
exc_modify <- function(scene, where = TRUE, ...) {
  check_scene(scene)
  df <- as.data.frame(scene)
  sel <- rlang::eval_tidy(rlang::enquo(where), df)
  sel <- rep_len(as.logical(sel), nrow(df))
  sel[is.na(sel)] <- FALSE
  props <- list(...)
  is_style <- names(props) %in% names(.style_aliases)
  style <- normalize_style(rename_style(props[is_style]))
  if (!is.null(style$fontFamily)) style$fontFamily <- resolve_font(style$fontFamily)$id
  raw <- props[!is_style]
  if (!is.null(raw$angle)) raw$angle <- deg2rad(raw$angle)
  changes <- c(style, raw)
  for (i in which(sel)) {
    el <- scene$elements[[i]]
    el[names(changes)] <- changes
    if (el$type == "text" && any(c("text", "fontSize", "fontFamily") %in% names(changes))) {
      el <- refit_text(el)
    }
    el$version <- (el$version %||% 1) + 1
    el$versionNonce <- new_seed()
    el$updated <- timestamp_ms()
    scene$elements[[i]] <- el
  }
  scene
}

# Re-measure a text element after its text or font changed, keeping its centre
# for centred text and its left edge otherwise.
refit_text <- function(el) {
  font <- element_font(el)
  if (!is.null(el$text) && is.null(el$originalText)) el$originalText <- el$text
  m <- measure_text(el$text, font, el$fontSize, el$lineHeight)
  if (identical(el$textAlign, "center")) el$x <- el$x + (el$width - m$width) / 2
  if (identical(el$textAlign, "right")) el$x <- el$x + (el$width - m$width)
  if (identical(el$verticalAlign, "middle")) el$y <- el$y + (el$height - m$height) / 2
  el$width <- m$width
  el$height <- m$height
  el
}

# Axis-aligned bounds of one element, accounting for rotation and points.
element_bounds <- function(el, stroke = TRUE) {
  if (!is.null(el$points) && length(el$points)) {
    p <- points_to_xy(el$points)
    x0 <- el$x + min(p[, 1]); x1 <- el$x + max(p[, 1])
    y0 <- el$y + min(p[, 2]); y1 <- el$y + max(p[, 2])
  } else {
    x0 <- el$x; x1 <- el$x + el$width
    y0 <- el$y; y1 <- el$y + el$height
  }
  a <- el$angle %||% 0
  if (a != 0) {
    cx <- (x0 + x1) / 2; cy <- (y0 + y1) / 2
    xs <- c(x0, x1, x1, x0) - cx; ys <- c(y0, y0, y1, y1) - cy
    rx <- xs * cos(a) - ys * sin(a) + cx
    ry <- xs * sin(a) + ys * cos(a) + cy
    x0 <- min(rx); x1 <- max(rx); y0 <- min(ry); y1 <- max(ry)
  }
  pad <- if (stroke) (el$strokeWidth %||% 0) / 2 else 0
  c(x0 - pad, y0 - pad, x1 + pad, y1 + pad)
}

#' Bounding box of a scene
#'
#' @param scene An `exc_scene` or `exc_elements`.
#' @param stroke Include half the stroke width around each element.
#' @return A named numeric vector: `xmin`, `ymin`, `xmax`, `ymax`, `width`,
#'   `height`, in px.
#' @export
exc_bbox <- function(scene, stroke = TRUE) {
  els <- if (inherits(scene, "exc_scene")) live_elements(scene) else as_element_list(scene)
  if (length(els) == 0) return(c(xmin = 0, ymin = 0, xmax = 0, ymax = 0, width = 0, height = 0))
  b <- vapply(els, element_bounds, numeric(4), stroke = stroke)
  out <- c(xmin = min(b[1, ]), ymin = min(b[2, ]), xmax = max(b[3, ]), ymax = max(b[4, ]))
  c(out, width = out[["xmax"]] - out[["xmin"]], height = out[["ymax"]] - out[["ymin"]])
}

#' Move or scale a whole scene
#'
#' @param scene An `exc_scene` or `exc_elements`.
#' @param dx,dy Offset in px.
#' @param scale Scale factor applied around the scene's top-left corner
#'   (after moving). Sizes, points and font sizes scale; stroke widths stay the same.
#' @return The transformed object.
#' @export
exc_translate <- function(scene, dx = 0, dy = 0, scale = 1) {
  is_scene <- inherits(scene, "exc_scene")
  els <- as_element_list(scene)
  origin <- if (is_scene) exc_bbox(scene)[c("xmin", "ymin")] else c(0, 0)
  out <- lapply(els, function(e) {
    e$x <- (e$x - origin[[1]]) * scale + origin[[1]] + dx
    e$y <- (e$y - origin[[2]]) * scale + origin[[2]] + dy
    if (scale != 1) {
      e$width <- e$width * scale
      e$height <- e$height * scale
      if (!is.null(e$points)) e$points <- lapply(e$points, function(p) p * scale)
      if (!is.null(e$fontSize)) e$fontSize <- e$fontSize * scale
    }
    e
  })
  if (is_scene) {
    scene$elements <- out
    return(scene)
  }
  new_elements(out, attr(scene, "files"))
}
