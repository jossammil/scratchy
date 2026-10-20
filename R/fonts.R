.onLoad <- function(libname, pkgname) {
  register_fonts()
  register_downloaded_fonts()
}

#' Register the bundled handwriting fonts
#'
#' Called automatically when the package loads. Registered fonts work on
#' devices that use 'systemfonts', such as [ragg::agg_png()] and
#' [svglite::svglite()]. Other devices (for example [grDevices::pdf()]) get
#' text drawn as glyph outlines by the native renderer instead.
#'
#' @return Invisibly, the names of the registered font families.
#' @export
register_fonts <- function() {
  dir <- system.file("fonts", package = "excalidrawer")
  if (!nzchar(dir)) return(invisible(character()))
  for (fam in names(.font_files)) {
    files <- file.path(dir, .font_files[[fam]])
    names(files) <- names(.font_files[[fam]])
    if (!file.exists(files[["plain"]])) next
    bold <- if ("bold" %in% names(files)) files[["bold"]] else files[["plain"]]
    try(systemfonts::register_font(fam, plain = files[["plain"]], bold = bold,
                                   italic = files[["plain"]], bolditalic = bold),
        silent = TRUE)
  }
  invisible(names(.font_files))
}

#' Fonts available to excalidrawer
#'
#' Lists Excalidraw's own fonts and the extra handwriting fonts bundled with
#' the package. Fonts without an Excalidraw id still work in R; when the file
#' is opened in Excalidraw they display as Excalifont.
#'
#' @return A data frame with the font `name`, its Excalidraw `id`, whether a
#'   font file is bundled, and the licence.
#' @export
#' @examples
#' exc_fonts()
exc_fonts <- function() {
  lic <- c("Virgil" = "OFL-1.1", "Helvetica" = "system", "Cascadia" = "OFL-1.1",
           "Excalifont" = "OFL-1.1", "Nunito" = "OFL-1.1", "Lilita One" = "OFL-1.1",
           "Comic Shanns" = "MIT", "Liberation Sans" = "system", "Caveat" = "OFL-1.1",
           "Patrick Hand" = "OFL-1.1", "Architects Daughter" = "OFL-1.1",
           "Gochi Hand" = "OFL-1.1")
  data.frame(
    name = .fonts$name,
    excalidraw_id = .fonts$id,
    bundled = .fonts$family %in% names(.font_files),
    license = unname(lic[.fonts$name]),
    stringsAsFactors = FALSE
  )
}

.fonts_extra <- new.env(parent = emptyenv())

#' Download extra fonts
#'
#' Some fun fonts can't be bundled because of their licence, so they are
#' downloaded on request, stored in your user data folder and registered for
#' this and future sessions.
#'
#' * `"xkcd"`: the xkcd Script handwriting font by the iPython team, made
#'   from Randall Munroe's handwriting (CC BY-NC 3.0: non-commercial use).
#'
#' @param name Which font to download.
#' @return The font's family name, invisibly. Use it as `font =`.
#' @export
#' @examples
#' \dontrun{
#' exc_font_fetch("xkcd")
#' sketch(p, preset = "xkcd", font = "xkcd Script")
#' }
exc_font_fetch <- function(name = c("xkcd")) {
  name <- match.arg(name)
  spec <- list(xkcd = list(
    family = "xkcd Script",
    url = "https://github.com/ipython/xkcd-font/raw/master/xkcd-script/font/xkcd-script.ttf",
    file = "xkcd-script.ttf"
  ))[[name]]
  dir <- tools::R_user_dir("excalidrawer", "data")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(dir, spec$file)
  if (!file.exists(path)) {
    cli::cli_inform("Downloading {spec$family} from {.url {spec$url}}")
    utils::download.file(spec$url, path, mode = "wb", quiet = TRUE)
  }
  register_extra_font(spec$family, path)
  invisible(spec$family)
}

register_extra_font <- function(family, path) {
  systemfonts::register_font(family, plain = path, bold = path, italic = path, bolditalic = path)
  .fonts_extra[[family]] <- path
}

# Fonts downloaded in earlier sessions.
register_downloaded_fonts <- function() {
  dir <- tools::R_user_dir("excalidrawer", "data")
  xkcd <- file.path(dir, "xkcd-script.ttf")
  if (file.exists(xkcd)) try(register_extra_font("xkcd Script", xkcd), silent = TRUE)
}

# Resolve a font given by name or Excalidraw id.
# Returns list(id, name, family, custom) where `custom` is the non-Excalidraw
# font name to record in customData (or NULL).
resolve_font <- function(font) {
  if (is.null(font)) font <- .default_style$fontFamily
  if (is.numeric(font)) {
    row <- match(font, .fonts$id)
    if (is.na(row)) row <- match(5, .fonts$id)
  } else {
    key <- tolower(gsub("[ _-]", "", font))
    row <- match(key, tolower(gsub("[ _-]", "", .fonts$name)))
    if (is.na(row)) row <- match(key, tolower(gsub("[ _-]", "", .fonts$family)))
    if (is.na(row)) {
      extra <- names(.fonts_extra)[tolower(gsub("[ _-]", "", names(.fonts_extra))) == key]
      if (length(extra)) return(list(id = 5, name = extra[1], family = extra[1], custom = extra[1]))
    }
    if (is.na(row)) {
      cli::cli_abort(c("Unknown font {.val {font}}.",
                       i = "See {.fn exc_fonts} for the available fonts."))
    }
  }
  f <- .fonts[row, ]
  list(
    id = if (is.na(f$id)) 5 else f$id,
    name = f$name,
    family = f$family,
    custom = if (is.na(f$id)) f$name else NULL
  )
}

# The font to draw a text element with, honouring a custom font in customData.
element_font <- function(el) {
  custom <- el$customData$excalidrawer$font
  if (!is.null(custom)) return(resolve_font(custom))
  resolve_font(el$fontFamily %||% 5)
}

# Metrics (ascender/descender in em units) for vertical placement.
font_metrics <- function(font) {
  row <- match(font$name, .fonts$name)
  if (!is.na(row) && !is.na(.fonts$units_per_em[row])) {
    return(list(ascender = .fonts$ascender[row] / .fonts$units_per_em[row],
                descender = .fonts$descender[row] / .fonts$units_per_em[row],
                line_height = .fonts$line_height[row]))
  }
  info <- systemfonts::font_info(family = font$family, size = 100, res = 72)
  list(ascender = info$max_ascend / 100, descender = info$max_descend / 100,
       line_height = if (is.na(row)) 1.25 else .fonts$line_height[row])
}

# Excalidraw's getVerticalOffset(): distance from the top of a line box to the
# alphabetic baseline.
vertical_offset <- function(font, font_size, line_height_px) {
  m <- font_metrics(font)
  line_gap <- (line_height_px - font_size * m$ascender + font_size * m$descender) / 2
  font_size * m$ascender + line_gap
}

# Width in px of each line (canvas measureText equivalent: advance width).
text_widths <- function(lines, font, font_size) {
  lines[!nzchar(lines)] <- " "
  as.numeric(textshaping::text_width(lines, family = font$family, size = font_size, res = 72))
}

# Excalidraw's measureText(): width = widest line, height = lines * lineHeight.
measure_text <- function(text, font, font_size, line_height = NULL) {
  line_height <- line_height %||% font_metrics(font)$line_height
  lines <- strsplit(normalize_text(text), "\n", fixed = TRUE)[[1]]
  if (length(lines) == 0) lines <- ""
  list(width = max(text_widths(lines, font, font_size)),
       height = length(lines) * font_size * line_height,
       lines = lines)
}

normalize_text <- function(text) {
  text <- gsub("\r\n?", "\n", text)
  gsub("\t", "        ", text, fixed = TRUE)
}

# Greedy word wrap so labels fit their container (like Excalidraw's wrapText).
wrap_text <- function(text, max_width, font, font_size) {
  if (!is.finite(max_width) || max_width <= 0) return(text)
  paras <- strsplit(normalize_text(text), "\n", fixed = TRUE)[[1]]
  out <- character()
  for (p in paras) {
    words <- strsplit(p, " ", fixed = TRUE)[[1]]
    if (length(words) == 0) {
      out <- c(out, "")
      next
    }
    line <- words[1]
    for (w in words[-1]) {
      cand <- paste(line, w)
      if (text_widths(cand, font, font_size) <= max_width) {
        line <- cand
      } else {
        out <- c(out, line)
        line <- w
      }
    }
    out <- c(out, line)
  }
  paste(out, collapse = "\n")
}
