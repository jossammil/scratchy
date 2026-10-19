#' An Excalidraw-style ggplot2 theme
#'
#' A clean, whiteboard-like theme: handwriting font, ink-coloured axis lines
#' and ticks, no grey panel, and text sizes that land on Excalidraw's own
#' font sizes (16, 20 and 28 px at the default `base_size`). It works with
#' plain ggplot2 output and is the default theme used by [as_excalidraw()]
#' and [sketch()]. It also pairs well with sketchy geoms from other packages
#' such as ggsketch.
#'
#' The handwriting fonts are registered with 'systemfonts', so a plot printed
#' directly with this theme needs a device that uses it: ragg (in RStudio,
#' set Tools > Global Options > Graphics > Backend to "AGG") or svglite.
#' [sketch()] works on every device because it draws text as outlines.
#'
#' @param base_size Base font size in points. 15 pt = 20 px, Excalidraw's
#'   default.
#' @param base_family Font family; see [exc_fonts()].
#' @param ink Colour for text, axes and ticks.
#' @param grid Which grid lines to draw: `"none"`, `"x"`, `"y"` or `"xy"`.
#'   Grid lines are dashed and light.
#' @param background Plot background colour, or `"transparent"`.
#' @param preset Optional [exc_preset()] whose font and ink to use.
#' @return A ggplot2 theme.
#' @export
#' @examples
#' \donttest{
#' library(ggplot2)
#' p <- ggplot(mpg, aes(class)) + geom_bar(fill = "#a5d8ff") + theme_excalidraw(grid = "y")
#' sketch(p, theme = NULL)
#' }
theme_excalidraw <- function(base_size = 15, base_family = "Excalifont", ink = "#1e1e1e",
                             grid = c("none", "y", "x", "xy"), background = "white",
                             preset = NULL) {
  rlang::check_installed("ggplot2")
  grid <- match.arg(grid)
  if (!is.null(preset)) {
    pr <- exc_preset(preset)
    base_family <- resolve_font(pr$font)$family
    ink <- pr$ink
    background <- "transparent"
  }
  base_family <- resolve_font(base_family)$family
  grid_line <- ggplot2::element_line(colour = grDevices::adjustcolor(ink, alpha.f = 0.25),
                                     linewidth = 0.35, linetype = "dashed")
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      text = ggplot2::element_text(colour = ink),
      axis.text = ggplot2::element_text(colour = ink, size = ggplot2::rel(0.85)),
      axis.title = ggplot2::element_text(colour = ink),
      axis.line = ggplot2::element_line(colour = ink, linewidth = 0.6),
      axis.ticks = ggplot2::element_line(colour = ink, linewidth = 0.45),
      axis.ticks.length = grid::unit(5, "pt"),
      panel.grid = ggplot2::element_blank(),
      panel.grid.major.x = if (grid %in% c("x", "xy")) grid_line else ggplot2::element_blank(),
      panel.grid.major.y = if (grid %in% c("y", "xy")) grid_line else ggplot2::element_blank(),
      plot.title = ggplot2::element_text(size = ggplot2::rel(1.4), colour = ink,
                                         margin = ggplot2::margin(b = 6)),
      plot.subtitle = ggplot2::element_text(size = ggplot2::rel(0.95), colour = ink,
                                            margin = ggplot2::margin(b = 10)),
      plot.caption = ggplot2::element_text(size = ggplot2::rel(0.75), colour = ink),
      plot.title.position = "plot",
      legend.title = ggplot2::element_text(colour = ink, size = ggplot2::rel(0.9)),
      legend.text = ggplot2::element_text(colour = ink, size = ggplot2::rel(0.85)),
      legend.key.size = grid::unit(18, "pt"),
      strip.text = ggplot2::element_text(colour = ink, size = ggplot2::rel(0.95)),
      plot.background = ggplot2::element_rect(fill = background, colour = NA),
      plot.margin = ggplot2::margin(12, 14, 10, 10)
    )
}

#' Excalidraw colour scales for ggplot2
#'
#' Discrete scales use Excalidraw's palette: light fills for `fill`, strong
#' colours for `colour`. The continuous versions run through the five shades
#' of one hue.
#'
#' @param ... Passed to the underlying ggplot2 scale.
#' @param type For the discrete scales, `"background"` (light) or
#'   `"stroke"` (strong) colours.
#' @param hue For the continuous scales, an Excalidraw hue such as `"blue"`.
#' @return A ggplot2 scale.
#' @export
#' @examples
#' \donttest{
#' library(ggplot2)
#' p <- ggplot(mpg, aes(class, fill = drv)) + geom_bar() + scale_fill_excalidraw()
#' sketch(p)
#' }
scale_fill_excalidraw <- function(..., type = c("background", "stroke")) {
  rlang::check_installed("ggplot2")
  type <- match.arg(type)
  ggplot2::discrete_scale("fill", palette = function(n) unname(excalidraw_colors(type, n)), ...)
}

#' @rdname scale_fill_excalidraw
#' @export
scale_colour_excalidraw <- function(..., type = c("stroke", "background")) {
  rlang::check_installed("ggplot2")
  type <- match.arg(type)
  ggplot2::discrete_scale("colour", palette = function(n) unname(excalidraw_colors(type, n)), ...)
}

#' @rdname scale_fill_excalidraw
#' @export
scale_color_excalidraw <- scale_colour_excalidraw

#' @rdname scale_fill_excalidraw
#' @export
scale_fill_excalidraw_c <- function(..., hue = "blue") {
  rlang::check_installed("ggplot2")
  ggplot2::scale_fill_gradientn(colours = .palette[[hue]], ...)
}

#' @rdname scale_fill_excalidraw
#' @export
scale_colour_excalidraw_c <- function(..., hue = "blue") {
  rlang::check_installed("ggplot2")
  ggplot2::scale_colour_gradientn(colours = .palette[[hue]], ...)
}
