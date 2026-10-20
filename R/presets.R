.presets <- list(
  whiteboard = list(roughness = 1, font = "Excalifont", ink = "#1e1e1e", paper = NULL,
                    background = "#ffffff", fill_style = "hachure", stroke_width = 2),
  xkcd = list(roughness = 2, font = "Comic Shanns", ink = "#1e1e1e", paper = NULL,
              background = "#ffffff", fill_style = "solid", stroke_width = 2, bowing = 3),
  blueprint = list(roughness = 1, font = "Virgil", ink = "#f8f9fa", paper = "blueprint",
                   background = "#1d4f86", fill_style = "cross-hatch", stroke_width = 2),
  chalkboard = list(roughness = 2, font = "Architects Daughter", ink = "#f1f3f5",
                    paper = "chalkboard", background = "#2f3d33", fill_style = "hachure",
                    stroke_width = 2),
  pencil = list(roughness = 1, font = "Patrick Hand", ink = "#495057", paper = "lines",
                background = "#ffffff", fill_style = "hachure", stroke_width = 1),
  marker = list(roughness = 1, font = "Lilita One", ink = "#1e1e1e", paper = NULL,
                background = "#ffffff", fill_style = "solid", stroke_width = 4)
)

#' Style presets
#'
#' A preset bundles sloppiness, font, ink colour, fill style and paper into a
#' named look:
#' * `"whiteboard"`: Excalidraw's own look.
#' * `"xkcd"`: wobblier, bowed lines and a comic font.
#' * `"blueprint"`: white ink on blueprint paper.
#' * `"chalkboard"`: chalky lines on a dark board.
#' * `"pencil"`: thin grey lines on lined notebook paper.
#' * `"marker"`: thick marker strokes and a bold font.
#'
#' @param name Preset name.
#' @return An `exc_preset` object (a list).
#' @export
#' @examples
#' exc_preset("blueprint")
exc_preset <- function(name = c("whiteboard", "xkcd", "blueprint", "chalkboard", "pencil", "marker")) {
  if (inherits(name, "exc_preset")) return(name)
  name <- match.arg(name)
  structure(c(list(name = name), .presets[[name]]), class = "exc_preset")
}

#' @export
print.exc_preset <- function(x, ...) {
  cat("<exc_preset> ", x$name, ": ", x$font, ", roughness ", x$roughness, ", ink ", x$ink,
      if (!is.null(x$paper)) paste0(", ", x$paper, " paper"), "\n", sep = "")
  invisible(x)
}

#' Restyle a whole scene
#'
#' Applies a preset (or individual settings) to every element: sloppiness,
#' stroke width, handwriting font, fill style and ink colour. Dark strokes and
#' text become the preset's ink colour; coloured strokes are kept.
#'
#' @param scene An `exc_scene`.
#' @param preset A preset name or [exc_preset()].
#' @param ... Settings to override: `roughness`, `font`, `ink`, `fill_style`,
#'   `stroke_width`, `paper`, `background`, `bowing`.
#' @return The restyled scene. The paper is remembered for [exc_save()] and
#'   `plot()`.
#' @export
#' @examples
#' s <- exc_scene(exc_rect(0, 0, 120, 60, label = "hi", fill = "blue"))
#' exc_restyle(s, "chalkboard")
exc_restyle <- function(scene, preset = "whiteboard", ...) {
  check_scene(scene)
  p <- utils::modifyList(unclass(exc_preset(preset)), list(...))
  font <- resolve_font(p$font)
  rough <- normalize_style(list(roughness = p$roughness))$roughness
  sw <- normalize_style(list(strokeWidth = p$stroke_width))$strokeWidth
  fs <- normalize_style(list(fillStyle = p$fill_style))$fillStyle
  scene$elements <- lapply(scene$elements, function(e) {
    if (e$type %in% c("frame", "magicframe", "image")) return(e)
    if (!is.null(e$strokeColor) && is_dark(e$strokeColor)) e$strokeColor <- p$ink
    if (e$type == "text") {
      e$fontFamily <- font$id
      e$customData$excalidrawer$font <- font$custom
      if (is.null(font$custom) && !is.null(e$customData$excalidrawer)) e$customData$excalidrawer$font <- NULL
      return(refit_text(e))
    }
    e$roughness <- rough
    if (e$type != "freedraw") e$strokeWidth <- sw
    # small shapes (scatter points, legend dots) stay solid
    small <- e$type == "ellipse" && max(e$width, e$height) < 16
    if (!is_transparent(e$backgroundColor) && !small) e$fillStyle <- fs
    if (!is.null(p$bowing)) e$customData$excalidrawer$bowing <- p$bowing
    e
  })
  scene$appState$viewBackgroundColor <- p$background
  scene$meta$paper <- p$paper
  scene
}

is_dark <- function(col) {
  if (is_transparent(col)) return(FALSE)
  rgb <- grDevices::col2rgb(col)[, 1] / 255
  (0.2126 * rgb[1] + 0.7152 * rgb[2] + 0.0722 * rgb[3]) < 0.3
}
