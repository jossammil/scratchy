#' Data-driven templates
#'
#' Design a card, poster or slide in Excalidraw, with placeholders in the
#' text, and fill it from R:
#' * `{{column}}` in any text is replaced by that value.
#' * A shape whose label is `{{chart:name}}` gets a sketched chart drawn to
#'   fit inside it (a ggplot, or a function of the data row returning one).
#' * A shape whose label is `{{image:name}}` gets an image file fitted
#'   inside it.
#'
#' `exc_template_fill()` fills one copy; `exc_template_render()` fills and
#' saves one image (or `.excalidraw` file) per row of a data frame.
#'
#' @param template An `exc_scene` or a path to a template file (any format
#'   [read_excalidraw()] reads).
#' @param data A named list or a one-row data frame of values.
#' @param charts A named list of charts: ggplots, scenes, or functions that
#'   take the data row and return one.
#' @param images A named list of image file paths (or functions of the row).
#'   Values in `data` with the placeholder's name work too.
#' @return `exc_template_fill()`: the filled `exc_scene`.
#' @export
#' @examples
#' \donttest{
#' card <- exc_template_fill(
#'   exc_template_example(),
#'   data = list(metric = "Sketches drawn", value = "1,204", change = "+18% this month"),
#'   charts = list(trend = ggplot2::ggplot(data.frame(x = 1:12, y = cumsum(rnorm(12))),
#'                                         ggplot2::aes(x, y)) + ggplot2::geom_line())
#' )
#' plot(card)
#' }
exc_template_fill <- function(template, data = list(), charts = list(), images = list()) {
  scene <- if (inherits(template, "exc_scene")) template else read_excalidraw(template)
  data <- as_row(data)
  els <- scene$elements
  ids <- vapply(els, function(e) e$id, "")
  inserts <- list()
  drop <- character()
  for (i in seq_along(els)) {
    e <- els[[i]]
    if (e$type != "text") next
    txt <- e$originalText %||% e$text %||% ""
    slot <- regmatches(txt, regexec("^\\s*\\{\\{\\s*(chart|image):\\s*([^}\\s]+)\\s*\\}\\}\\s*$", txt))[[1]]
    if (length(slot) == 3) {
      box_i <- match(e$containerId %||% "", ids)
      box <- if (is.na(box_i)) e else els[[box_i]]
      content <- slot_content(slot[2], slot[3], box, data, charts, images)
      drop <- c(drop, e$id)
      if (!is.na(box_i)) {
        els[[box_i]]$boundElements <- Filter(function(b) b$id != e$id, els[[box_i]]$boundElements)
        if (length(els[[box_i]]$boundElements) == 0) els[[box_i]] <- set_null(els[[box_i]], "boundElements")
      }
      if (!is.null(content)) inserts[[if (is.na(box_i)) e$id else box$id]] <- content
      next
    }
    new <- fill_text(txt, data)
    if (!identical(new, txt)) {
      e$originalText <- new
      e$text <- new
      e <- refit_text_in_place(e, els, ids)
      e$version <- (e$version %||% 1) + 1
      els[[i]] <- e
    }
  }
  out <- list()
  files <- scene$files
  for (e in els) {
    if (e$id %in% drop) {
      if (!is.null(inserts[[e$id]])) out <- c(out, unclass(inserts[[e$id]]))
      next
    }
    out <- c(out, list(e))
    ins <- inserts[[e$id]]
    if (!is.null(ins)) {
      out <- c(out, unclass(ins))
      files <- c(files, attr(ins, "files"))
    }
  }
  for (ins in inserts) files <- c(files, attr(ins, "files"))
  files <- files[!duplicated(names(files))]
  out <- lapply(out, function(e) set_null(e, "index"))
  new_scene(out, scene$appState, files, scene$meta)
}

as_row <- function(data) {
  if (is.data.frame(data)) {
    if (nrow(data) != 1) cli::cli_abort("{.arg data} must have exactly one row.")
    data <- lapply(data, function(v) if (is.factor(v)) as.character(v) else v)
  }
  as.list(data)
}

format_value <- function(v) {
  if (is.null(v) || length(v) == 0 || (length(v) == 1 && is.na(v))) return("")
  if (is.numeric(v)) return(format(v, big.mark = ",", trim = TRUE, scientific = FALSE))
  as.character(v)
}

fill_text <- function(txt, data) {
  keys <- regmatches(txt, gregexpr("\\{\\{\\s*[^}:]+?\\s*\\}\\}", txt))[[1]]
  for (k in unique(keys)) {
    name <- trimws(gsub("[{}]", "", k))
    if (name %in% names(data)) txt <- gsub(k, format_value(data[[name]]), txt, fixed = TRUE)
  }
  txt
}

# Re-measure a text after its words changed: labels re-wrap inside their
# container, free text keeps its alignment.
refit_text_in_place <- function(e, els, ids) {
  j <- match(e$containerId %||% "", ids)
  if (is.na(j)) return(refit_text(e))
  box <- els[[j]]
  font <- element_font(e)
  max_w <- switch(box$type,
    ellipse = round(box$width / 2 * sqrt(2)) - .bound_text_padding * 2,
    diamond = round(box$width / 2) - .bound_text_padding * 2,
    arrow = max(0.7 * box$width, e$fontSize * 11),
    box$width - .bound_text_padding * 2
  )
  e$text <- wrap_text(e$originalText, max_w, font, e$fontSize)
  m <- measure_text(e$text, font, e$fontSize, e$lineHeight)
  e$width <- m$width
  e$height <- m$height
  if (box$type != "arrow") {
    e$x <- box$x + box$width / 2 - m$width / 2
    e$y <- box$y + box$height / 2 - m$height / 2
  }
  e
}

slot_content <- function(kind, name, box, data, charts, images) {
  val <- if (kind == "chart") charts[[name]] else images[[name]] %||% data[[name]]
  if (is.function(val)) val <- val(data)
  if (is.null(val)) {
    cli::cli_warn("No {kind} given for placeholder {.val {name}}; leaving it empty.")
    return(NULL)
  }
  pad <- 6
  bx <- c(box$x + pad, box$y + pad, max(10, box$width - 2 * pad), max(10, box$height - 2 * pad))
  if (kind == "image") {
    el <- exc_image(val, 0, 0, width = bx[3])
    if (el[[1]]$height > bx[4]) el <- exc_image(val, 0, 0, height = bx[4])
    return(exc_translate(el, dx = bx[1] + (bx[3] - el[[1]]$width) / 2,
                         dy = bx[2] + (bx[4] - el[[1]]$height) / 2))
  }
  sc <- if (inherits(val, "exc_scene")) val else as_excalidraw(val, width = bx[3], height = bx[4], id = name)
  bb <- if (!is.null(sc$meta$size)) {
    c(xmin = 0, ymin = 0, width = sc$meta$size[["width"]], height = sc$meta$size[["height"]])
  } else {
    exc_bbox(sc, stroke = FALSE)
  }
  scale <- min(bx[3] / bb[["width"]], bx[4] / bb[["height"]])
  moved <- exc_translate(new_elements(sc$elements, sc$files), dx = -bb[["xmin"]], dy = -bb[["ymin"]])
  moved <- exc_translate(moved, scale = scale)
  exc_translate(moved, dx = bx[1] + (bx[3] - bb[["width"]] * scale) / 2,
                dy = bx[2] + (bx[4] - bb[["height"]] * scale) / 2)
}

#' @rdname exc_template_fill
#' @param dir Folder to write the files to.
#' @param file File name pattern. `{.row}` is the row number and `{column}`
#'   any column's value. The extension picks the format (`.png`, `.svg`,
#'   `.pdf`, `.excalidraw`, ...).
#' @param ... Options passed to [exc_save()], such as `scale`.
#' @return `exc_template_render()`: the file paths, invisibly.
#' @export
exc_template_render <- function(template, data, dir = ".", file = "card-{.row}.png",
                                charts = list(), images = list(), ...) {
  scene <- if (inherits(template, "exc_scene")) template else read_excalidraw(template)
  data <- as.data.frame(data, stringsAsFactors = FALSE)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  paths <- character(nrow(data))
  for (i in seq_len(nrow(data))) {
    row <- data[i, , drop = FALSE]
    filled <- exc_template_fill(scene, row, charts = charts, images = images)
    name <- gsub("{.row}", i, file, fixed = TRUE)
    for (col in names(row)) {
      name <- gsub(paste0("{", col, "}"), gsub("[^A-Za-z0-9._-]+", "-", format_value(row[[col]])),
                   name, fixed = TRUE)
    }
    paths[i] <- file.path(dir, name)
    if (file_format_or_image(paths[i]) == "image") exc_save(filled, paths[i], ...)
    else write_excalidraw(filled, paths[i])
  }
  invisible(paths)
}

file_format_or_image <- function(path) {
  if (grepl("\\.excalidraw(\\.md)?$", tolower(path))) "scene" else "image"
}

#' An example template
#'
#' A KPI card with `{{metric}}`, `{{value}}` and `{{change}}` text and a
#' `{{chart:trend}}` slot, for trying [exc_template_fill()]. Write it out
#' with [write_excalidraw()] to open it in Excalidraw and make it your own.
#'
#' @return An `exc_scene`.
#' @export
exc_template_example <- function() {
  read_excalidraw(pkg_file("templates", "kpi-card.excalidraw"))
}
