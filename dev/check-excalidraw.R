# Dev helper: load scenes into the real Excalidraw (from a CDN, in headless
# Chrome) to check they are accepted, and fetch Excalidraw's own SVG export
# for side-by-side comparison with the native renderer.
#
#   source("dev/check-excalidraw.R")
#   res <- excalidraw_check(scene)

excalidraw_check_session <- local({
  state <- new.env()
  function() {
    if (!is.null(state$b) && isTRUE(tryCatch(state$b$Runtime$evaluate("1")$result$value == 1, error = function(e) FALSE))) {
      return(state$b)
    }
    port <- httpuv::randomPort()
    state$server <- httpuv::startServer("127.0.0.1", port, list(staticPaths = list("/" = normalizePath("dev"))))
    b <- chromote::ChromoteSession$new()
    b$Page$navigate(sprintf("http://127.0.0.1:%d/excalidraw-check.html", port))
    for (i in 1:120) {
      ready <- tryCatch(b$Runtime$evaluate("window.excalidrawReady === true")$result$value, error = function(e) FALSE)
      if (isTRUE(ready)) break
      Sys.sleep(0.5)
    }
    if (!isTRUE(ready)) stop("Excalidraw did not load in headless Chrome")
    state$b <- b
    b
  }
})

excalidraw_check <- function(scene, svg_file = NULL) {
  b <- excalidraw_check_session()
  json <- excalidrawer:::scene_to_json(scene)
  js <- sprintf("window.checkScene(%s)", jsonlite::toJSON(json, auto_unbox = TRUE))
  res <- b$Runtime$evaluate(js, awaitPromise = TRUE, returnByValue = TRUE)$result$value
  if (!is.null(svg_file) && isTRUE(res$ok)) writeLines(res$svg, svg_file)
  res
}

# Rasterise an SVG file with headless Chrome (for eyeballing parity).
svg_to_png <- function(svg_file, png_file, zoom = 2) {
  b <- chromote::ChromoteSession$new()
  on.exit(b$close(), add = TRUE)
  svg <- paste(readLines(svg_file, warn = FALSE), collapse = "\n")
  html <- sprintf('<html><body style="margin:0;background:#fff">%s</body></html>', svg)
  tmp <- tempfile(fileext = ".html")
  writeLines(html, tmp)
  b$Page$navigate(paste0("file://", tmp))
  Sys.sleep(1.5)
  b$screenshot(png_file, selector = "svg", scale = zoom, show = FALSE)
  invisible(png_file)
}

# Load a file through Excalidraw's own loadFromBlob (decodes embedded scenes).
excalidraw_check_file <- function(path) {
  b <- excalidraw_check_session()
  mime <- switch(tolower(tools::file_ext(path)), svg = "image/svg+xml", png = "image/png",
                 "application/json")
  b64 <- gsub("\n", "", jsonlite::base64_enc(readBin(path, "raw", file.info(path)$size)))
  js <- sprintf("window.checkFile(%s, %s)", jsonlite::toJSON(b64, auto_unbox = TRUE),
                jsonlite::toJSON(mime, auto_unbox = TRUE))
  b$Runtime$evaluate(js, awaitPromise = TRUE, returnByValue = TRUE)$result$value
}
