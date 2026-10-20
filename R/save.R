#' Save a scene as an image
#'
#' Renders the scene offline with the native renderer (rough.js in V8 plus
#' grid) and saves it. The file type follows the extension:
#' * `.png`, `.jpg`: bitmap via ragg, with the handwriting fonts.
#' * `.svg`: vector via svglite, with the fonts embedded so the file looks
#'   the same everywhere.
#' * `.pdf`: vector via cairo, with text drawn as outlines.
#'
#' @param scene An `exc_scene`.
#' @param file Output path.
#' @param scale Pixel density: 1 = one image pixel per scene px, 2 for
#'   sharper "retina" images. For vector formats it scales the page size.
#' @param padding Space around the drawing, in px.
#' @param background Draw the background colour (`FALSE` = transparent).
#' @param paper Optional paper background; see [exc_papers()].
#' @param text Text drawing mode; see [exc_grob()].
#' @param embed_scene For SVG and PNG, also store the scene inside the image
#'   so it can be reopened as an editable drawing (like Excalidraw's "Embed
#'   scene" export). On by default for `.excalidraw.svg` / `.excalidraw.png`
#'   file names.
#' @return `file`, invisibly.
#' @export
#' @examples
#' s <- exc_scene(exc_ellipse(0, 0, 120, 80, label = "sketchy!", fill = "blue",
#'                            fill_style = "hachure"))
#' f <- tempfile(fileext = ".png")
#' exc_save(s, f, scale = 2)
exc_save <- function(scene, file, scale = 1, padding = 10, background = TRUE,
                     paper = NULL, text = c("auto", "outline", "font"),
                     embed_scene = grepl("\\.excalidraw\\.(svg|png)$", tolower(file))) {
  check_scene(scene)
  text <- match.arg(text)
  ext <- tolower(tools::file_ext(file))
  g <- exc_grob(scene, padding = padding, background = background, text = text, paper = paper)
  w_in <- g$canvas[["w"]] / 96 * scale
  h_in <- g$canvas[["h"]] / 96 * scale
  open_device(ext, file, w_in, h_in, scale, scene)
  dev <- grDevices::dev.cur()
  tryCatch({
    grid::grid.newpage()
    grid::grid.draw(g)
  }, finally = grDevices::dev.off(dev))
  if (isTRUE(embed_scene)) {
    if (ext == "svg") embed_scene_svg(file, scene)
    else if (ext == "png") embed_scene_png(file, scene)
    else cli::cli_warn("Scenes can only be embedded in SVG and PNG files.")
  }
  invisible(file)
}

open_device <- function(ext, file, w_in, h_in, scale, scene) {
  switch(ext,
    png = {
      rlang::check_installed("ragg")
      ragg::agg_png(file, width = round(w_in * 96), height = round(h_in * 96), units = "px",
                    res = 96 * scale, background = "transparent")
    },
    jpg = , jpeg = {
      rlang::check_installed("ragg")
      ragg::agg_jpeg(file, width = round(w_in * 96), height = round(h_in * 96), units = "px",
                     res = 96 * scale, background = "white", quality = 92)
    },
    svg = {
      rlang::check_installed("svglite")
      svglite::svglite(file, width = w_in, height = h_in, bg = "transparent",
                       web_fonts = scene_font_faces(scene), fix_text_size = FALSE)
    },
    pdf = grDevices::cairo_pdf(file, width = w_in, height = h_in, bg = "transparent"),
    cli::cli_abort("Can't save {.val {ext}} files. Use png, jpg, svg or pdf.")
  )
}

# Embedded @font-face rules for the fonts a scene's text uses.
scene_font_faces <- function(scene) {
  fams <- unique(unlist(lapply(live_elements(scene), function(e) {
    if (e$type == "text") element_font(e)$family else NULL
  })))
  dir <- system.file("fonts", package = "excalidrawer")
  faces <- lapply(fams, function(fam) {
    files <- .font_files[[fam]]
    if (is.null(files)) return(NULL)
    woff2 <- file.path(dir, sub("\\.ttf$", ".woff2", files[["plain"]]))
    embedded_font_face(fam, if (file.exists(woff2)) woff2 else file.path(dir, files[["plain"]]))
  })
  compact(faces)
}

# svglite::font_face(embed = TRUE) fails unless every source type is given,
# so build the rule directly.
embedded_font_face <- function(family, path) {
  type <- tolower(tools::file_ext(path))
  mime <- switch(type, woff2 = "font/woff2", woff = "font/woff", otf = "font/otf", "font/ttf")
  fmt <- switch(type, woff2 = "woff2", woff = "woff", otf = "opentype", "truetype")
  b64 <- jsonlite::base64_enc(readBin(path, "raw", file.size(path)))
  rule <- paste0("    @font-face {\n      font-family: \"", family, "\";\n      src: url(data:", mime,
                 ";base64,", gsub("\n", "", b64), ") format(\"", fmt, "\");\n    }")
  structure(rule, class = c("font_face", "character"))
}
