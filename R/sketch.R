#' Draw any plot in Excalidraw style
#'
#' `sketch()` wraps a plot so that printing it converts it with
#' [as_excalidraw()] and draws the result with the native renderer. The plot
#' is laid out at the size of the device it is drawn on, so it works in the
#' RStudio plot pane, in knitr/Quarto chunks, and with
#' `ggplot2::ggsave("plot.png", sketch(p), width = 7, height = 4)`.
#'
#' @param plot A ggplot, a formula such as `~ hist(x)`, a function that draws
#'   with base graphics, or a grob.
#' @param ... Options passed to [as_excalidraw()], such as `fill_style`,
#'   `roughness`, `font`, `theme` or `seed`.
#' @param preset Optional [exc_preset()] name.
#' @param paper Optional paper background; see [exc_papers()].
#' @param width,height Fixed layout size in px. By default the device size
#'   is used.
#' @return An `exc_sketch` object. Print it to draw it, or turn it into a
#'   scene with [as_excalidraw()].
#' @export
#' @examples
#' \donttest{
#' library(ggplot2)
#' p <- ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_point(size = 3) +
#'   scale_colour_excalidraw()
#' sketch(p)
#' sketch(p, preset = "chalkboard")
#' sketch(~ barplot(VADeaths, beside = TRUE))
#' }
sketch <- function(plot, ..., preset = NULL, paper = NULL, width = NULL, height = NULL) {
  structure(list(plot = plot, args = list(...), preset = preset, paper = paper,
                 width = width, height = height),
            class = "exc_sketch")
}

sketch_scene <- function(x, size_in = c(800, 500) / 96) {
  w <- x$width %||% (size_in[1] * 96)
  h <- x$height %||% (size_in[2] * 96)
  do.call(as_excalidraw, c(list(x$plot, width = w, height = h, preset = x$preset), x$args))
}

#' @export
as_excalidraw.exc_sketch <- function(x, width = NULL, height = NULL, ...) {
  if (!is.null(width)) x$width <- width
  if (!is.null(height)) x$height <- height
  sketch_scene(x)
}

#' @export
print.exc_sketch <- function(x, ...) {
  grid::grid.newpage()
  grid::grid.draw(x)
  invisible(x)
}

#' @export
plot.exc_sketch <- function(x, ...) print.exc_sketch(x, ...)

#' @export
grid.draw.exc_sketch <- function(x, recording = TRUE) {
  scene <- sketch_scene(x, grDevices::dev.size("in"))
  grid::grid.draw(exc_grob(scene, paper = x$paper), recording = recording)
}

#' @exportS3Method knitr::knit_print
knit_print.exc_sketch <- function(x, ...) {
  print(x)
  invisible(x)
}
