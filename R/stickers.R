#' Stickers: hand-drawn icons, people and doodles
#'
#' scratchy bundles a dozen community libraries from
#' <https://libraries.excalidraw.com> (all MIT licensed): R and RStudio
#' icons, stick figures, storytelling faces, speech bubbles, sticky notes,
#' stars, hearts, emojis, data-viz icons, hand-drawn signs, general icons and
#' data-science logos. They arrive as native Excalidraw elements, so they
#' are hand-drawn, recolourable and editable.
#'
#' * `exc_stickers()` lists them; `exc_sticker_sheet()` draws a numbered
#'   preview of one library.
#' * `exc_sticker()` adds one to a scene.
#' * [exc_peep()] adds a hand-drawn person from Open Peeps.
#' * [read_excalidraw_lib()] and [exc_library_item()] work with any other
#'   library file.
#'
#' @param library Library name, such as `"emojis"` or `"stick-figures"`.
#' @return `exc_stickers()`: a data frame with one row per sticker
#'   (`library`, `item`, `name`, `sticker`). Use the `sticker` column with
#'   `exc_sticker()`.
#' @export
#' @examples
#' head(exc_stickers())
#' exc_stickers("stick-figures")
exc_stickers <- function(library = NULL) {
  man <- sticker_manifest()
  libs <- library %||% man$library
  unknown <- setdiff(libs, man$library)
  if (length(unknown)) cli::cli_abort("Unknown sticker library {.val {unknown}}. See {.fn exc_stickers}.")
  rows <- lapply(libs, function(lib) {
    items <- sticker_library(lib)
    nm <- vapply(items, function(it) it$name, "")
    data.frame(library = lib, item = seq_along(items), name = nm,
               sticker = paste0(lib, ":", ifelse(nzchar(nm), nm, seq_along(items))),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

sticker_manifest <- function() {
  utils::read.csv(pkg_file("stickers", "manifest.csv"), stringsAsFactors = FALSE)
}

.sticker_cache <- new.env(parent = emptyenv())

sticker_library <- function(lib) {
  hit <- .sticker_cache[[lib]]
  if (!is.null(hit)) return(hit)
  items <- read_excalidraw_lib(pkg_file("stickers", paste0(lib, ".excalidrawlib")))
  .sticker_cache[[lib]] <- items
  items
}

#' @rdname exc_stickers
#' @param scene An `exc_scene` to add the sticker to.
#' @param sticker `"library:item"`, where item is a number or a name, such
#'   as `"emojis:12"` or `"stick-figures:Girl"`.
#' @param x,y Where to put the sticker's top-left corner. Data values work
#'   for scenes made from a ggplot; px otherwise (or in [I()]).
#' @param width Width to scale the sticker to, in px.
#' @param ... Style properties to apply to every element of the sticker,
#'   such as `stroke`, `fill` or `roughness`.
#' @param panel Panel number for faceted plots.
#' @export
exc_sticker <- function(scene, sticker, x = 0, y = 0, width = NULL, ..., panel = 1) {
  check_scene(scene)
  parts <- strsplit(sticker, ":", fixed = TRUE)[[1]]
  if (length(parts) != 2) cli::cli_abort("Use {.val library:item}, for example {.val emojis:12}.")
  items <- sticker_library(parts[1])
  item <- suppressWarnings(as.integer(parts[2]))
  if (is.na(item)) item <- parts[2]
  pos <- if (is.null(scene$meta$coord) || inherits(x, "AsIs")) {
    list(x = as.numeric(unclass(x)), y = as.numeric(unclass(y)))
  } else {
    exc_data_to_px(scene, x, y, panel)
  }
  els <- exc_library_item(items, item, x = pos$x, y = pos$y, width = width)
  style <- list(...)
  if (length(style)) {
    st <- normalize_style(rename_style(style))
    els <- new_elements(lapply(unclass(els), function(e) {
      e[names(st)] <- st
      e
    }))
  }
  els <- exc_group(els)
  exc_add(scene, annotation(els))
}

#' @rdname exc_stickers
#' @param columns Number of columns in the preview grid.
#' @return `exc_sticker_sheet()`: a scene with every sticker of the library
#'   and its number; draw it with `plot()`.
#' @export
exc_sticker_sheet <- function(library, columns = 6) {
  items <- sticker_library(library)
  cell <- 140
  out <- exc_scene()
  for (i in seq_along(items)) {
    col <- (i - 1) %% columns
    row <- (i - 1) %/% columns
    x0 <- col * cell
    y0 <- row * (cell + 24)
    els <- exc_library_item(items, i, x = 0, y = 0)
    bb <- exc_bbox(els, stroke = FALSE)
    scale <- min(1, (cell - 30) / max(bb[["width"]], bb[["height"]], 1))
    els <- exc_translate(els, scale = scale)
    bb <- exc_bbox(els, stroke = FALSE)
    els <- exc_translate(els, dx = x0 + (cell - bb[["width"]]) / 2 - bb[["xmin"]],
                         dy = y0 + (cell - 24 - bb[["height"]]) / 2 - bb[["ymin"]])
    nm <- items[[i]]$name
    label <- exc_text(if (nzchar(nm)) paste0(i, ": ", nm) else as.character(i),
                      x0 + cell / 2, y0 + cell - 14, hjust = 0.5, font_size = 14, stroke = "gray")
    out <- exc_add(out, els, label)
  }
  out
}

#' Hand-drawn people from Open Peeps
#'
#' Draws a person in Pablo Stanley's Open Peeps style (CC0), generated
#' offline with the DiceBear Open Peeps generator (MIT). The same `seed`
#' always gives the same person. Peeps are SVG images: crisp in Excalidraw
#' and in SVG/PDF output (the native renderer needs the rsvg package).
#'
#' @param scene An `exc_scene` to add the person to, or `NULL` to just
#'   return the element.
#' @param x,y Top-left corner, in px (or data values for converted ggplots).
#' @param size Width and height in px.
#' @param seed Any string or number; each gives a different person.
#' @param face,head,accessories,facial_hair Optional choices, such as
#'   `face = "smile"` or `head = "afro"`. See `exc_peep_options()`.
#' @param skin,clothing Colours (hex, without or with `#`).
#' @param ... Other DiceBear Open Peeps options.
#' @param panel Panel number for faceted plots.
#' @return The scene with the person added, or an `exc_elements` object if
#'   `scene` is `NULL`.
#' @export
#' @examples
#' exc_scene() |>
#'   exc_peep(0, 0, seed = "Ada", face = "smile") |>
#'   exc_peep(170, 0, seed = "Grace", clothing = "#a5d8ff")
exc_peep <- function(scene = NULL, x = 0, y = 0, size = 160, seed = NULL, face = NULL, head = NULL,
                     accessories = NULL, facial_hair = NULL, skin = NULL, clothing = NULL, ...,
                     panel = 1) {
  hex <- function(col) if (is.null(col)) NULL else list(sub("^#", "", norm_color(col)))
  opts <- compact(c(list(
    seed = as.character(seed %||% new_id()),
    size = size,
    face = if (!is.null(face)) list(face),
    head = if (!is.null(head)) list(head),
    accessories = if (!is.null(accessories)) list(accessories),
    accessoriesProbability = if (!is.null(accessories)) 100,
    facialHair = if (!is.null(facial_hair)) list(facial_hair),
    facialHairProbability = if (!is.null(facial_hair)) 100,
    skinColor = hex(skin),
    clothingColor = hex(clothing)
  ), list(...)))
  svg <- peeps_context()$call("ExcPeeps.svg", opts)
  pos <- if (is.null(scene) || is.null(scene$meta$coord) || inherits(x, "AsIs")) {
    list(x = as.numeric(unclass(x)), y = as.numeric(unclass(y)))
  } else {
    exc_data_to_px(scene, x, y, panel)
  }
  el <- image_element(charToRaw(enc2utf8(svg)), "image/svg+xml", pos$x, pos$y, size, size)
  if (is.null(scene)) return(el)
  exc_add(scene, annotation(el))
}

#' @rdname exc_peep
#' @return `exc_peep_options()`: a named list of the allowed values for each
#'   option.
#' @export
exc_peep_options <- function() {
  props <- jsonlite::fromJSON(peeps_context()$call("ExcPeeps.options"), simplifyVector = FALSE)
  lapply(props, function(p) unlist(p$items$enum %||% p$default))
}

peeps_context <- function() {
  if (is.null(.v8$peeps)) {
    ctx <- V8::v8()
    ctx$source(pkg_file("js", "peeps.js"))
    .v8$peeps <- ctx
  }
  .v8$peeps
}

#' Load an Excalidraw library from a file or the web
#'
#' @param path A `.excalidrawlib` file, or its URL (for example from
#'   <https://libraries.excalidraw.com>). Downloads are cached.
#' @return An `exc_library`; place items with [exc_library_item()].
#' @export
exc_library <- function(path) {
  if (grepl("^https?://", path)) {
    cache <- tools::R_user_dir("scratchy", "cache")
    dir.create(cache, recursive = TRUE, showWarnings = FALSE)
    dest <- file.path(cache, paste0(digest_string(path), ".excalidrawlib"))
    if (!file.exists(dest)) utils::download.file(path, dest, mode = "wb", quiet = TRUE)
    path <- dest
  }
  read_excalidraw_lib(path)
}
