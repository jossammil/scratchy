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
