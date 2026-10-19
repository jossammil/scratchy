.v8 <- new.env(parent = emptyenv())

# One V8 context per session with rough.js, perfect-freehand and our shape port.
v8_context <- function() {
  if (is.null(.v8$ctx)) {
    ctx <- V8::v8()
    ctx$source(pkg_file("js", "rough.js"))
    ctx$source(pkg_file("js", "perfect-freehand.js"))
    ctx$source(pkg_file("js", "exc-shapes.js"))
    ctx$eval("ExcShapes.renderJSON = function (els, bg, tol) { return JSON.stringify(ExcShapes.render(els, bg, tol)); };")
    .v8$ctx <- ctx
  }
  .v8$ctx
}

.rough_types <- c("rectangle", "diamond", "ellipse", "line", "arrow", "freedraw",
                  "iframe", "embeddable")

# Sketchy geometry for each drawable element: a list (one entry per element)
# of parts, each with `kind` ("stroke" or "fill"), `color`, `width`, `rule`
# and `paths` (a list of numeric vectors x1, y1, x2, y2, ... in scene px).
rough_parts <- function(elements, canvas_bg = "#ffffff", tolerance = 1) {
  if (length(elements) == 0) return(list())
  json <- as.character(to_json(unname(elements)))
  out <- v8_context()$call("ExcShapes.renderJSON", V8::JS(json), canvas_bg, tolerance)
  res <- jsonlite::fromJSON(out, simplifyVector = TRUE, simplifyDataFrame = FALSE,
                            simplifyMatrix = FALSE)
  for (r in res) {
    if (!is.null(r$error)) cli::cli_warn("Couldn't draw element {.val {r$id}}: {r$error}")
  }
  lapply(res, function(r) {
    lapply(r$parts, function(p) {
      p$paths <- lapply(p$paths, as.numeric)
      p
    })
  })
}
