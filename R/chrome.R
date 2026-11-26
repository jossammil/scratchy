# Headless Chrome helpers: run the bundled Excalidraw (the same build as the
# widget) for Mermaid conversion and pixel-exact exports.

.chrome <- new.env(parent = emptyenv())

chrome_session <- function() {
  rlang::check_installed(c("chromote", "httpuv"))
  b <- .chrome$session
  alive <- !is.null(b) && isTRUE(tryCatch(b$Runtime$evaluate("1")$result$value == 1,
                                          error = function(e) FALSE))
  if (alive) return(b)
  if (is.null(.chrome$server)) {
    port <- httpuv::randomPort()
    .chrome$server <- httpuv::startServer(
      "127.0.0.1", port,
      list(staticPaths = list("/" = httpuv::staticPath(pkg_file("htmlwidgets", "lib", "excalidraw-widget"),
                                                        indexhtml = FALSE)))
    )
    .chrome$port <- port
  }
  b <- chromote::ChromoteSession$new()
  b$Page$navigate(sprintf("http://127.0.0.1:%d/headless.html", .chrome$port))
  ready <- FALSE
  for (i in 1:120) {
    ready <- isTRUE(tryCatch(
      b$Runtime$evaluate("typeof window.scratchyHeadless === 'object'")$result$value,
      error = function(e) FALSE))
    if (ready) break
    Sys.sleep(0.25)
  }
  if (!ready) cli::cli_abort("The Excalidraw editor didn't load in headless Chrome.")
  .chrome$session <- b
  b
}

chrome_call <- function(js) {
  b <- chrome_session()
  res <- b$Runtime$evaluate(js, awaitPromise = TRUE, returnByValue = TRUE, timeout = 60000)
  if (!is.null(res$exceptionDetails)) {
    msg <- res$exceptionDetails$exception$description %||% res$exceptionDetails$text
    cli::cli_abort(c("Excalidraw reported an error:", x = msg))
  }
  res$result$value
}

js_arg <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))

#' Mermaid diagrams as editable Excalidraw elements
#'
#' Converts Mermaid text (flowcharts, sequence and class diagrams) to
#' Excalidraw elements with Excalidraw's own converter, run in headless
#' Chrome (needs the chromote package and Chrome or Chromium). Other diagram
#' types come back as an embedded image.
#'
#' @param code Mermaid diagram text.
#' @param font_size Font size for the diagram text.
#' @return An `exc_scene`.
#' @export
#' @examples
#' \dontrun{
#' exc_mermaid("flowchart LR\n  idea[Idea] --> sketch[Sketch] --> chart{{Chart!}}") |>
#'   exc_save("flow.png")
#' }
exc_mermaid <- function(code, font_size = 20) {
  json <- chrome_call(sprintf("window.scratchyHeadless.mermaid(%s, %s)", js_arg(code), js_arg(font_size)))
  fit_containers(scene_from_json(json))
}

# Widen shapes whose label would have to break a word, and re-wrap labels.
fit_containers <- function(scene) {
  els <- scene$elements
  ids <- vapply(els, function(e) e$id, "")
  for (i in seq_along(els)) {
    t <- els[[i]]
    if (t$type != "text" || is.null(t$containerId)) next
    j <- match(t$containerId, ids)
    if (is.na(j)) next
    box <- els[[j]]
    if (!box$type %in% c("rectangle", "ellipse", "diamond")) next
    font <- element_font(t)
    words <- strsplit(t$originalText %||% t$text, "\\s+")[[1]]
    longest <- max(text_widths(words, font, t$fontSize)) + 2
    pad <- .bound_text_padding * 2
    need <- switch(box$type,
      ellipse = (longest + pad) * sqrt(2),
      diamond = (longest + pad) * 2,
      longest + pad
    )
    if (need > box$width) {
      box$x <- box$x - (need - box$width) / 2
      box$width <- need
    }
    max_w <- switch(box$type,
      ellipse = round(box$width / 2 * sqrt(2)) - pad,
      diamond = round(box$width / 2) - pad,
      box$width - pad
    )
    t$text <- wrap_text(t$originalText %||% t$text, max_w, font, t$fontSize)
    m <- measure_text(t$text, font, t$fontSize, t$lineHeight)
    t$width <- m$width
    t$height <- m$height
    t$x <- box$x + box$width / 2 - m$width / 2
    t$y <- box$y + box$height / 2 - m$height / 2
    els[[j]] <- box
    els[[i]] <- t
  }
  scene$elements <- els
  scene
}

# Export through the real Excalidraw (exportToSvg / exportToBlob).
excalidraw_export <- function(scene, file, type, scale = 2, padding = 10, background = TRUE,
                              embed = FALSE) {
  opts <- list(type = type, scale = scale, padding = padding, background = background, embed = embed)
  res <- chrome_call(sprintf("window.scratchyHeadless.export(%s, %s)",
                             js_arg(scene_to_json(scene)), js_arg(opts)))
  if (type == "png") {
    writeBin(jsonlite::base64_dec(res$data), file)
  } else {
    con <- file(file, open = "wb")
    on.exit(close(con))
    writeBin(charToRaw(enc2utf8(res$data)), con)
  }
  invisible(file)
}

chrome_close <- function() {
  if (!is.null(.chrome$session)) try(.chrome$session$close(), silent = TRUE)
  if (!is.null(.chrome$server)) try(httpuv::stopServer(.chrome$server), silent = TRUE)
  .chrome$session <- NULL
  .chrome$server <- NULL
  invisible()
}
