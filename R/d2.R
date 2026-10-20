#' Diagrams from D2 in sketch mode
#'
#' Renders [D2](https://d2lang.com) diagram text with D2's hand-drawn
#' `--sketch` mode and returns it as a scene holding the SVG as an image
#' (so you can annotate it, place it next to charts or save it). Needs the
#' `d2` command-line tool (on macOS: `brew install d2`). For diagrams made of
#' editable Excalidraw shapes, use [exc_mermaid()] instead.
#'
#' @param code D2 diagram text, such as `"idea -> sketch -> chart"`.
#' @param sketch Use D2's hand-drawn style.
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
exc_d2 <- function(code, sketch = TRUE, theme = NULL, layout = NULL, pad = 20, scale = 1) {
  d2 <- Sys.which("d2")
  if (!nzchar(d2)) {
    cli::cli_abort(c("The {.code d2} command-line tool isn't installed.",
                     i = "Install it from {.url https://d2lang.com} (on macOS: {.code brew install d2})."))
  }
  input <- tempfile(fileext = ".d2")
  output <- tempfile(fileext = ".svg")
  on.exit(unlink(c(input, output)))
  writeLines(code, input)
  args <- c(if (sketch) "--sketch", "--pad", pad,
            if (!is.null(theme)) c("--theme", theme),
            if (!is.null(layout)) c("--layout", layout),
            shQuote(input), shQuote(output))
  out <- suppressWarnings(system2(d2, args, stdout = TRUE, stderr = TRUE))
  if (!file.exists(output)) cli::cli_abort(c("d2 failed:", x = paste(out, collapse = "\n")))
  bytes <- readBin(output, "raw", file.info(output)$size)
  dims <- image_size(bytes, "svg") %||% c(400, 300)
  exc_scene(image_element(bytes, "image/svg+xml", 0, 0, dims[1] * scale, dims[2] * scale))
}
