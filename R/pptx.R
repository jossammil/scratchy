#' Hand-drawn PowerPoint slides
#'
#' Writes one slide per scene (or per chart, or per Excalidraw frame) to a
#' PowerPoint file. By default each drawing is placed as **editable vector
#' shapes** (with the rvg package), so strokes can be recoloured or moved in
#' PowerPoint; use `vector = FALSE` for a picture instead.
#'
#' Text is drawn as shapes by default so it keeps the handwriting font on any
#' computer. With `text = "font"` it stays editable text, which shows in the
#' handwriting font only where the fonts are installed (see
#' [exc_install_fonts()]).
#'
#' @param x An `exc_scene`, a ggplot, a [sketch()], or a list of these. A
#'   scene with frames becomes one slide per frame.
#' @param path Output `.pptx` file.
#' @param titles Slide titles (recycled). `NULL` or `NA` keeps the frame
#'   name for frame slides and leaves other slides without a title.
#' @param vector Place drawings as editable vector shapes (`TRUE`) or as
#'   PNG pictures (`FALSE`).
#' @param text `"outline"` or `"font"`; see above.
#' @param template Optional `.pptx`/`.potx` file to use as the template.
#' @param scale Pixel density for pictures when `vector = FALSE`.
#' @return `path`, invisibly.
#' @export
#' @examples
#' \dontrun{
#' library(ggplot2)
#' p <- ggplot(mpg, aes(class)) + geom_bar(fill = "#a5d8ff")
#' exc_pptx(list(p, exc_mermaid("flowchart LR\n A --> B")), "talk.pptx",
#'          titles = c("What people drive", "How it works"))
#' }
exc_pptx <- function(x, path, titles = NULL, vector = TRUE, text = c("outline", "font"),
                     template = NULL, scale = 2) {
  rlang::check_installed(c("officer", "rvg"))
  text <- match.arg(text)
  slides <- pptx_slides(x)
  if (!is.null(titles)) {
    titles <- rep_len(titles, length(slides))
    for (i in seq_along(slides)) {
      if (!is.na(titles[[i]])) slides[[i]]$title <- titles[[i]]
    }
  }
  doc <- if (is.null(template)) officer::read_pptx() else officer::read_pptx(template)
  size <- officer::slide_size(doc)
  for (sl in slides) {
    has_title <- !is.null(sl$title) && !is.na(sl$title) && nzchar(sl$title)
    doc <- officer::add_slide(doc, layout = if (has_title) "Title Only" else "Blank",
                              master = "Office Theme")
    top <- 0.3
    if (has_title) {
      doc <- officer::ph_with(
        doc, officer::fpar(officer::ftext(sl$title, officer::fp_text(font.family = "Excalifont",
                                                                    font.size = 36))),
        location = officer::ph_location_type("title")
      )
      top <- 1.5
    }
    box <- c(w = size$width - 0.8, h = size$height - top - 0.4)
    bb <- slide_canvas(sl$scene)
    fit <- min(box[["w"]] / bb[["w"]], box[["h"]] / bb[["h"]])
    w <- bb[["w"]] * fit
    h <- bb[["h"]] * fit
    loc <- officer::ph_location(left = (size$width - w) / 2, top = top + (box[["h"]] - h) / 2,
                                width = w, height = h)
    value <- if (vector) {
      g <- exc_grob(sl$scene, text = text, background = FALSE)
      rvg::dml(code = grid::grid.draw(g), bg = "transparent")
    } else {
      png_file <- tempfile(fileext = ".png")
      exc_save(sl$scene, png_file, scale = scale, background = FALSE)
      officer::external_img(png_file, width = w, height = h)
    }
    doc <- officer::ph_with(doc, value, location = loc)
  }
  print(doc, target = path)
  invisible(path)
}

# Canvas size of a scene in inches (as exc_grob lays it out).
slide_canvas <- function(scene) {
  g <- exc_grob(scene)
  c(w = g$canvas[["w"]] / 96, h = g$canvas[["h"]] / 96)
}

pptx_slides <- function(x) {
  if (inherits(x, c("exc_scene", "ggplot", "exc_sketch")) || !is.list(x)) x <- list(x)
  out <- list()
  for (item in x) {
    scene <- if (inherits(item, "exc_scene")) item else as_excalidraw(item, width = 1100, height = 560)
    frames <- Filter(function(e) e$type %in% c("frame", "magicframe") && !isTRUE(e$isDeleted),
                     scene$elements)
    if (length(frames) == 0) {
      out[[length(out) + 1]] <- list(scene = scene, title = NULL)
      next
    }
    for (fr in frames) {
      kids <- Filter(function(e) identical(e$frameId, fr$id), scene$elements)
      kids <- lapply(kids, function(e) set_null(e, "frameId"))
      sub <- new_scene(kids, scene$appState, scene$files, scene$meta[setdiff(names(scene$meta), "size")])
      out[[length(out) + 1]] <- list(scene = sub, title = fr$name)
    }
  }
  out
}

#' Install the handwriting fonts on this computer
#'
#' Copies the bundled fonts (Excalifont, Virgil, Comic Shanns, Caveat and
#' the others in [exc_fonts()]) into your user font folder, so other
#' programs such as PowerPoint, Keynote or Word can show them. Nothing is
#' installed unless you call this.
#'
#' @param dir Font folder. Defaults to `~/Library/Fonts` on macOS,
#'   `%LOCALAPPDATA%/Microsoft/Windows/Fonts` on Windows and
#'   `~/.local/share/fonts` elsewhere.
#' @param overwrite Replace fonts that are already there.
#' @return The installed file paths, invisibly.
#' @export
exc_install_fonts <- function(dir = NULL, overwrite = FALSE) {
  dir <- dir %||% switch(
    Sys.info()[["sysname"]],
    Darwin = "~/Library/Fonts",
    Windows = file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"),
    "~/.local/share/fonts"
  )
  dir <- path.expand(dir)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  src <- list.files(pkg_file("fonts"), pattern = "\\.ttf$", full.names = TRUE)
  dst <- file.path(dir, basename(src))
  ok <- file.copy(src, dst, overwrite = overwrite)
  cli::cli_inform(c(v = "Installed {sum(ok)} font{?s} in {.path {dir}}.",
                    i = if (any(!ok)) "{sum(!ok)} were already there (use {.code overwrite = TRUE} to replace)."))
  invisible(dst[ok])
}
