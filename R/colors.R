#' Excalidraw's colour palette
#'
#' Excalidraw's palette is built on [Open Color](https://yeun.github.io/open-color/).
#' Each hue has five shades, from very light (1) to strong (5). Excalidraw uses
#' shade 5 for strokes and shade 2 for fills.
#'
#' @param type `"stroke"` (strong colours for lines and text), `"background"`
#'   (light fills), or `"all"` for the full table.
#' @param n Number of colours to return. Colours repeat if `n` is larger than
#'   the number of hues.
#' @return A named character vector of hex colours, or a data frame for
#'   `type = "all"`.
#' @export
#' @examples
#' excalidraw_colors("stroke", 4)
#' excalidraw_colors("background", 4)
#' head(excalidraw_colors("all"))
excalidraw_colors <- function(type = c("stroke", "background", "all"), n = NULL) {
  type <- match.arg(type)
  if (type == "all") {
    hues <- names(.palette)[lengths(.palette) == 5]
    return(data.frame(
      hue = rep(hues, each = 5),
      shade = rep(1:5, length(hues)),
      color = unlist(.palette[hues], use.names = FALSE),
      stringsAsFactors = FALSE
    ))
  }
  shade <- if (type == "stroke") 5L else 2L
  cols <- vapply(.chart_hues, function(h) .palette[[h]][shade], character(1))
  if (!is.null(n)) cols <- rep_len(cols, n)
  cols
}

#' Look up a colour by Excalidraw hue name
#'
#' @param hue One of `"black"`, `"white"`, `"transparent"`, or a hue such as
#'   `"blue"`, `"red"` or `"bronze"`.
#' @param shade Shade from 1 (lightest) to 5 (strongest).
#' @return A hex colour string.
#' @export
#' @examples
#' exc_color("blue")
#' exc_color("yellow", 2)
exc_color <- function(hue, shade = 5) {
  pal <- .palette[[hue]]
  if (is.null(pal)) cli::cli_abort("Unknown hue {.val {hue}}. Use one of {.val {names(.palette)}}.")
  if (length(pal) == 1) return(pal)
  pal[[shade]]
}

# Normalise a colour to lower-case hex (or "transparent"). Excalidraw hue
# names use the strong shade for strokes and the light shade for fills.
norm_color <- function(col, shade = 5) {
  if (is.null(col) || length(col) == 0) return("transparent")
  if (is.na(col) || identical(col, "none") || identical(col, "transparent")) return("transparent")
  if (col %in% names(.palette)) return(exc_color(col, shade))
  if (grepl("^#[0-9a-fA-F]{6}$", col) || grepl("^#[0-9a-fA-F]{3}$", col)) return(tolower(col))
  if (grepl("^#[0-9a-fA-F]{8}$", col)) return(tolower(col))
  rgb <- grDevices::col2rgb(col, alpha = TRUE)
  if (rgb[4] == 0) return("transparent")
  hex <- grDevices::rgb(rgb[1], rgb[2], rgb[3], maxColorValue = 255)
  if (rgb[4] < 255) hex <- grDevices::rgb(rgb[1], rgb[2], rgb[3], rgb[4], maxColorValue = 255)
  tolower(hex)
}

is_transparent <- function(col) {
  is.null(col) || identical(col, "transparent") || (grepl("^#[0-9a-fA-F]{8}$", col) && grepl("00$", col))
}
