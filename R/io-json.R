#' Write a scene to a file
#'
#' The format follows the file extension:
#' * `.excalidraw` or `.json`: Excalidraw's JSON format, for excalidraw.com
#'   and the VS Code extension.
#' * `.excalidraw.md`: a drawing for the Obsidian Excalidraw plugin. Images
#'   are saved in a folder next to it.
#' * `.excalidraw.svg`, `.excalidraw.png` (or any `.svg` / `.png`): a
#'   rendered image with the scene embedded, so it can be opened again as an
#'   editable drawing in excalidraw.com, VS Code or with [read_excalidraw()].
#'
#' @param scene An `exc_scene`.
#' @param path File path.
#' @param pretty Indent the JSON (JSON and Obsidian files).
#' @param compress For Obsidian files, store the drawing compressed, as the
#'   plugin does by default.
#' @param ... For images, options passed to [exc_save()] such as `scale` or
#'   `paper`.
#' @return `path`, invisibly.
#' @export
#' @examples
#' s <- exc_scene(exc_rect(0, 0, 100, 60, label = "hi"))
#' f <- tempfile(fileext = ".excalidraw")
#' write_excalidraw(s, f)
#' read_excalidraw(f)
#'
#' # an image that stays editable
#' f2 <- tempfile(fileext = ".excalidraw.png")
#' write_excalidraw(s, f2, scale = 2)
#' read_excalidraw(f2)
write_excalidraw <- function(scene, path, pretty = TRUE, compress = TRUE, ...) {
  check_scene(scene)
  format <- file_format(path)
  switch(format,
    json = writeLines(scene_to_json(scene, pretty = pretty), path, useBytes = TRUE),
    obsidian = write_obsidian(scene, path, compress = compress),
    svg = , png = exc_save(scene, path, embed_scene = TRUE, ...),
    library = cli::cli_abort("Use {.fn write_excalidraw_lib} for library files."),
    cli::cli_abort("Writing {.val {format}} files isn't supported.")
  )
  invisible(path)
}

#' Read a scene from a file
#'
#' Reads Excalidraw JSON files (`.excalidraw`, `.json`), Obsidian drawings
#' (`.excalidraw.md`), and SVG or PNG images with an embedded scene (such as
#' Excalidraw exports made with "Embed scene", or files from
#' [write_excalidraw()]).
#'
#' @param path File path.
#' @return An `exc_scene`.
#' @export
read_excalidraw <- function(path) {
  if (!file.exists(path)) cli::cli_abort("File {.file {path}} doesn't exist.")
  format <- file_format(path)
  switch(format,
    json = scene_from_json(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")),
    obsidian = read_obsidian(path),
    svg = read_scene_svg(path),
    png = read_scene_png(path),
    library = cli::cli_abort("Use {.fn read_excalidraw_lib} for library files."),
    cli::cli_abort("Reading {.val {format}} files isn't supported.")
  )
}

file_format <- function(path) {
  p <- tolower(path)
  if (grepl("\\.excalidraw\\.md$", p)) return("obsidian")
  if (grepl("\\.excalidraw\\.svg$", p) || grepl("\\.svg$", p)) return("svg")
  if (grepl("\\.excalidraw\\.png$", p) || grepl("\\.png$", p)) return("png")
  if (grepl("\\.excalidrawlib$", p)) return("library")
  if (grepl("\\.(excalidraw|json)$", p)) return("json")
  cli::cli_abort("Can't tell the file format of {.file {path}} from its extension.")
}

# JSON helpers -----------------------------------------------------------------

empty_object <- function() structure(list(), names = character(0))

as_json_object <- function(x) {
  if (is.null(x) || length(x) == 0) return(empty_object())
  x
}

to_json <- function(x, pretty = FALSE) {
  jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA,
                   pretty = pretty)
}

scene_payload <- function(scene) {
  list(
    type = "excalidraw",
    version = 2,
    source = "excalidrawer",
    elements = unname(scene$elements),
    appState = as_json_object(scene$appState),
    files = as_json_object(scene$files)
  )
}

scene_to_json <- function(scene, pretty = FALSE) {
  as.character(to_json(scene_payload(scene), pretty = pretty))
}

scene_from_json <- function(json) {
  data <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  if (!identical(data$type, "excalidraw")) {
    cli::cli_abort("This isn't an Excalidraw scene (type is {.val {data$type %||% 'missing'}}).")
  }
  scene_from_list(data)
}

scene_from_list <- function(data) {
  els <- lapply(data$elements %||% list(), normalize_read_element)
  app <- data$appState %||% list()
  structure(
    list(elements = ensure_indices(els), appState = app, files = data$files %||% list()),
    class = "exc_scene"
  )
}

# Points arrive as lists of lists; store them as numeric pairs (same JSON).
normalize_read_element <- function(el) {
  if (!is.null(el$points)) el$points <- lapply(el$points, function(p) as.numeric(unlist(p)))
  el
}

#' Excalidraw libraries
#'
#' Libraries (`.excalidrawlib` files) are collections of reusable drawings,
#' such as the ones at <https://libraries.excalidraw.com>.
#' `read_excalidraw_lib()` returns the items; [exc_library_item()] places one
#' in a scene; `write_excalidraw_lib()` saves elements as a library.
#'
#' @param path File path.
#' @return `read_excalidraw_lib()`: a list of items, each with a `name` and
#'   `elements`.
#' @export
read_excalidraw_lib <- function(path) {
  data <- jsonlite::fromJSON(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
                             simplifyVector = FALSE)
  if (!identical(data$type, "excalidrawlib")) cli::cli_abort("{.file {path}} isn't an Excalidraw library.")
  items <- if (!is.null(data$libraryItems)) {
    lapply(data$libraryItems, function(it) {
      list(name = it$name %||% it$id %||% "", id = it$id %||% new_id(),
           elements = lapply(it$elements, normalize_read_element))
    })
  } else {
    lapply(data$library, function(els) {
      list(name = "", id = new_id(), elements = lapply(els, normalize_read_element))
    })
  }
  structure(items, class = "exc_library")
}

#' @export
print.exc_library <- function(x, ...) {
  nm <- vapply(x, function(it) if (nzchar(it$name)) it$name else "(unnamed)", "")
  cat("<exc_library> ", length(x), " item", if (length(x) != 1) "s", "\n", sep = "")
  if (length(x)) cat(paste0("  ", seq_along(nm), ". ", nm, collapse = "\n"), "\n", sep = "")
  invisible(x)
}

#' @param items A named list of `exc_elements` (one per library item), or an
#'   `exc_library`.
#' @rdname read_excalidraw_lib
#' @export
write_excalidraw_lib <- function(items, path) {
  if (inherits(items, "exc_library")) {
    lib_items <- lapply(items, function(it) list(status = "unpublished", elements = it$elements,
                                                  id = it$id, created = timestamp_ms(),
                                                  name = it$name))
  } else {
    nms <- names(items) %||% rep("", length(items))
    lib_items <- Map(function(it, nm) {
      list(status = "unpublished", elements = unname(as_element_list(it)), id = new_id(),
           created = timestamp_ms(), name = nm)
    }, items, nms)
  }
  payload <- list(type = "excalidrawlib", version = 2, source = "excalidrawer",
                  libraryItems = unname(lib_items))
  writeLines(as.character(to_json(payload, pretty = TRUE)), path, useBytes = TRUE)
  invisible(path)
}

#' @param library An `exc_library` from `read_excalidraw_lib()`.
#' @param item Item number or name.
#' @param x,y Where to put the item's top-left corner, in px.
#' @param width Optional width to scale the item to.
#' @rdname read_excalidraw_lib
#' @export
exc_library_item <- function(library, item, x = 0, y = 0, width = NULL) {
  if (is.character(item)) {
    i <- match(item, vapply(library, function(it) it$name, ""))
    if (is.na(i)) cli::cli_abort("No library item called {.val {item}}.")
    item <- i
  }
  els <- library[[item]]$elements
  els <- new_elements(fresh_copies(els))
  bb <- exc_bbox(els, stroke = FALSE)
  scale <- if (is.null(width)) 1 else width / bb[["width"]]
  out <- exc_translate(els, dx = -bb[["xmin"]], dy = -bb[["ymin"]])
  out <- exc_translate(out, scale = scale)
  exc_translate(out, dx = x, dy = y)
}

# New ids, seeds and group ids for copied elements, keeping internal links.
fresh_copies <- function(els) {
  old_ids <- vapply(els, function(e) e$id, "")
  new_ids <- stats::setNames(new_id(length(old_ids)), old_ids)
  groups <- unique(unlist(lapply(els, function(e) unlist(e$groupIds))))
  new_groups <- stats::setNames(new_id(length(groups)), groups)
  remap <- function(id) if (!is.null(id) && id %in% names(new_ids)) new_ids[[id]] else id
  lapply(els, function(e) {
    e$id <- new_ids[[e$id]]
    e$seed <- new_seed()
    e$versionNonce <- new_seed()
    if (length(e$groupIds)) e$groupIds <- as.list(unname(new_groups[unlist(e$groupIds)]))
    if (!is.null(e$containerId)) e$containerId <- remap(e$containerId)
    if (length(e$boundElements)) {
      e$boundElements <- lapply(e$boundElements, function(b) {
        b$id <- remap(b$id)
        b
      })
    }
    e <- set_null(e, "index")
    if (!is.null(e$frameId)) e <- set_null(e, "frameId")
    e
  })
}
