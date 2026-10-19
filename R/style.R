.style_aliases <- c(
  stroke = "strokeColor", stroke_color = "strokeColor", strokeColor = "strokeColor",
  color = "strokeColor", colour = "strokeColor",
  fill = "backgroundColor", background = "backgroundColor",
  background_color = "backgroundColor", backgroundColor = "backgroundColor",
  fill_style = "fillStyle", fillStyle = "fillStyle",
  stroke_width = "strokeWidth", strokeWidth = "strokeWidth",
  stroke_style = "strokeStyle", strokeStyle = "strokeStyle", linetype = "strokeStyle",
  roughness = "roughness", sloppiness = "roughness",
  opacity = "opacity",
  font = "fontFamily", font_family = "fontFamily", fontFamily = "fontFamily",
  font_size = "fontSize", fontSize = "fontSize"
)

#' Describe an Excalidraw style
#'
#' A style is a set of element properties (stroke colour, fill, sloppiness, and
#' so on). Pass one to any element constructor with `style =`, or set a
#' session default with [exc_set_style()]. Arguments given directly to a
#' constructor override the style.
#'
#' @param stroke Stroke (and text) colour: a hex colour, an R colour name, or
#'   an Excalidraw hue name such as `"blue"`. Hue names win over R colour
#'   names and give Excalidraw's strong shade (see [excalidraw_colors()]).
#' @param fill Background fill colour, or `"transparent"`. Hue names give
#'   Excalidraw's light fill shade, so `fill = "blue"` is `"#a5d8ff"`.
#' @param fill_style `"hachure"`, `"cross-hatch"`, `"solid"` or `"zigzag"`.
#'   rough.js also understands `"dots"`, `"dashed"` and `"zigzag-line"`.
#' @param stroke_width A number, or `"thin"` (1), `"bold"` (2) or
#'   `"extra_bold"` (4).
#' @param stroke_style `"solid"`, `"dashed"` or `"dotted"`.
#' @param roughness Sloppiness: a number, or `"architect"` (0), `"artist"` (1)
#'   or `"cartoonist"` (2).
#' @param opacity Opacity from 0 to 100.
#' @param font Font name (see [exc_fonts()]) or Excalidraw font id.
#' @param font_size Font size in px. Excalidraw's presets are 16, 20, 28 and 36.
#' @return A list of class `exc_style`.
#' @export
#' @examples
#' exc_style(stroke = "blue", fill = "blue", fill_style = "hachure")
exc_style <- function(stroke = NULL, fill = NULL, fill_style = NULL, stroke_width = NULL,
                      stroke_style = NULL, roughness = NULL, opacity = NULL,
                      font = NULL, font_size = NULL) {
  s <- compact(list(strokeColor = stroke, backgroundColor = fill, fillStyle = fill_style,
                    strokeWidth = stroke_width, strokeStyle = stroke_style,
                    roughness = roughness, opacity = opacity, fontFamily = font,
                    fontSize = font_size))
  structure(normalize_style(s), class = "exc_style")
}

#' @export
print.exc_style <- function(x, ...) {
  cat("<exc_style>\n")
  for (n in names(x)) cat("  ", n, ": ", format(x[[n]]), "\n", sep = "")
  invisible(x)
}

#' Set the default style for new elements
#'
#' @param ... Style properties, as in [exc_style()], or a single `exc_style`.
#'   Call with no arguments to reset to Excalidraw's defaults.
#' @return Invisibly, the previous default style.
#' @export
#' @examples
#' old <- exc_set_style(roughness = "cartoonist", stroke = "blue")
#' exc_set_style() # back to defaults
exc_set_style <- function(...) {
  old <- getOption("excalidrawer.style")
  args <- list(...)
  if (length(args) == 0) {
    options(excalidrawer.style = NULL)
  } else if (length(args) == 1 && inherits(args[[1]], "exc_style")) {
    options(excalidrawer.style = unclass(args[[1]]))
  } else {
    options(excalidrawer.style = unclass(do.call(exc_style, args)))
  }
  invisible(old)
}

# Map user-facing argument names to Excalidraw property names.
rename_style <- function(args) {
  if (length(args) == 0) return(list())
  nm <- names(args)
  if (is.null(nm) || any(!nzchar(nm))) cli::cli_abort("Style arguments must be named.")
  known <- nm %in% names(.style_aliases)
  if (any(!known)) {
    cli::cli_abort(c("Unknown style argument{?s}: {.arg {nm[!known]}}.",
                     i = "Use e.g. {.arg stroke}, {.arg fill}, {.arg fill_style}, {.arg roughness}."))
  }
  names(args) <- unname(.style_aliases[nm])
  args
}

normalize_style <- function(s) {
  if (!is.null(s$strokeColor)) s$strokeColor <- norm_color(s$strokeColor)
  if (!is.null(s$backgroundColor)) s$backgroundColor <- norm_color(s$backgroundColor, shade = 2)
  if (!is.null(s$roughness) && is.character(s$roughness)) {
    r <- .roughness[tolower(s$roughness)]
    if (is.na(r)) cli::cli_abort("{.arg roughness} must be a number or one of {.val {names(.roughness)}}.")
    s$roughness <- unname(r)
  }
  if (!is.null(s$strokeWidth) && is.character(s$strokeWidth)) {
    w <- .stroke_widths[gsub("[ -]", "_", tolower(s$strokeWidth))]
    if (is.na(w)) cli::cli_abort("{.arg stroke_width} must be a number or one of {.val {names(.stroke_widths)}}.")
    s$strokeWidth <- unname(w)
  }
  if (!is.null(s$fillStyle)) {
    fs <- gsub("_", "-", tolower(s$fillStyle))
    if (fs == "crosshatch") fs <- "cross-hatch"
    if (!fs %in% .fill_styles) cli::cli_abort("{.arg fill_style} must be one of {.val {(.fill_styles)}}.")
    s$fillStyle <- fs
  }
  if (!is.null(s$strokeStyle)) {
    if (!s$strokeStyle %in% .stroke_styles) cli::cli_abort("{.arg stroke_style} must be one of {.val {(.stroke_styles)}}.")
  }
  if (!is.null(s$opacity)) s$opacity <- max(0, min(100, s$opacity))
  s
}

# Combine: package defaults < session default < `style` argument < direct args.
resolve_style <- function(style = NULL, args = list()) {
  s <- .default_style
  sess <- getOption("excalidrawer.style")
  if (!is.null(sess)) s[names(sess)] <- sess
  if (!is.null(style)) s[names(style)] <- unclass(style)
  args <- normalize_style(rename_style(args))
  s[names(args)] <- args
  s
}
