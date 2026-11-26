#' Diagrams from D2 in sketch mode
#'
#' Renders [D2](https://d2lang.com) diagram text with D2's hand-drawn
#' `--sketch` mode and returns it as a scene holding the SVG as an image
#' (so you can annotate it, place it next to charts or save it). Needs the
#' `d2` command-line tool (on macOS: `brew install d2`). For diagrams made of
#' editable Excalidraw shapes, use [exc_mermaid()] instead.
#'
#' The labels use a handwriting font (Excalifont by default), embedded in the
#' SVG so the diagram looks the same in the Excalidraw editor, in browsers
#' and in SVG exports. R's own PNG and PDF output draws SVG images with rsvg,
#' which ignores embedded fonts: there the labels use the font only if it is
#' installed on the computer (see [exc_install_fonts()]).
#'
#' @param code D2 diagram text, such as `"idea -> sketch -> chart"`.
#' @param sketch Use D2's hand-drawn style.
#' @param font Font for the labels (see [exc_fonts()]), or `NULL` for D2's
#'   default (Source Sans Pro).
#' @param theme D2 theme id (see `d2 themes`).
#' @param layout Layout engine, such as `"dagre"` or `"elk"`.
#' @param pad Padding around the diagram, in px.
#' @param scale Size multiplier for the image.
#' @return An `exc_scene`.
#' @export
#' @examples
#' \dontrun{
#' exc_d2("data -> sketch: ggplot2\nsketch -> share: excalidraw") |> plot()
#' }
exc_d2 <- function(code, sketch = TRUE, font = "Excalifont", theme = NULL, layout = NULL,
                   pad = 20, scale = 1) {
  d2 <- Sys.which("d2")
  if (!nzchar(d2)) {
    cli::cli_abort(c("The {.code d2} command-line tool isn't installed.",
                     i = "Install it from {.url https://d2lang.com} (on macOS: {.code brew install d2})."))
  }
  font_files <- if (is.null(font)) NULL else d2_font_files(font)
  input <- tempfile(fileext = ".d2")
  output <- tempfile(fileext = ".svg")
  on.exit(unlink(c(input, output)))
  writeLines(code, input)
  args <- c(if (sketch) "--sketch", "--pad", pad,
            if (!is.null(theme)) c("--theme", theme),
            if (!is.null(layout)) c("--layout", layout),
            if (!is.null(font_files)) c(
              "--font-regular", shQuote(font_files[["plain"]]),
              "--font-italic", shQuote(font_files[["plain"]]),
              "--font-bold", shQuote(font_files[["bold"]]),
              "--font-semibold", shQuote(font_files[["bold"]])
            ),
            shQuote(input), shQuote(output))
  out <- suppressWarnings(system2(d2, args, stdout = TRUE, stderr = TRUE))
  if (!file.exists(output)) {
    # Keep d2's error lines (not its "font loaded" notes), and name the
    # temporary input file "d2" in them.
    out <- out[!grepl("^\\s*info:", out)]
    out <- gsub(paste0("[^ ]*", basename(input)), "d2", out, fixed = FALSE)
    cli::cli_abort(c("d2 couldn't draw the diagram:", x = paste(out, collapse = "\n")))
  }
  svg <- paste(readLines(output, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (!is.null(font_files)) {
    # D2 names the embedded fonts d2-<id>-font-<style>; use the real family
    # name so renderers that ignore embedded fonts can find an installed copy.
    svg <- gsub('"?d2-[0-9]+-font-(regular|italic|bold|semibold)"?',
                paste0('"', font_files[["family"]], '"'), svg)
  }
  bytes <- charToRaw(enc2utf8(svg))
  dims <- image_size(bytes, "svg") %||% c(400, 300)
  exc_scene(image_element(bytes, "image/svg+xml", 0, 0, dims[1] * scale, dims[2] * scale))
}

# TrueType files (and the family name) for a bundled or downloaded font.
d2_font_files <- function(font) {
  f <- resolve_font(font)
  extra <- .fonts_extra[[f$family]]
  if (!is.null(extra)) return(c(family = f$family, plain = extra, bold = extra))
  files <- .font_files[[f$family]]
  if (is.null(files)) {
    cli::cli_abort(c("{.arg font} must be a font bundled with scratchy, not {.val {font}}.",
                     i = "See {.fn exc_fonts}, or use {.code font = NULL} for D2's own font."))
  }
  dir <- system.file("fonts", package = "scratchy")
  plain <- file.path(dir, files[["plain"]])
  bold <- if ("bold" %in% names(files)) file.path(dir, files[["bold"]]) else plain
  c(family = f$family, plain = plain, bold = bold)
}
