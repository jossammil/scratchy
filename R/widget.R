#' The Excalidraw editor as an htmlwidget
#'
#' Shows a scene in the real Excalidraw editor, in the RStudio viewer, a
#' browser, R Markdown/Quarto HTML or a Shiny app. In `"edit"` mode you can
#' draw, annotate and restyle; in Shiny the edited scene comes back as
#' `input$<id>_scene` (see [excalidrawOutput()]).
#'
#' The editor and its fonts are bundled with the package, so it works
#' offline. Because the bundle is a JavaScript module made of several files,
#' save it with `htmlwidgets::saveWidget(w, file, selfcontained = FALSE)`.
#'
#' @param scene An `exc_scene`, or anything [as_excalidraw()] accepts (such
#'   as a ggplot).
#' @param mode `"edit"` or `"view"` (read-only, pan and zoom).
#' @param theme `"light"` or `"dark"`.
#' @param grid Show the grid.
#' @param zen Zen mode: hide most of the toolbar.
#' @param width,height Widget size (CSS units or pixels).
#' @param elementId Optional element id.
#' @param debounce Milliseconds to wait after the last edit before sending
#'   the scene to Shiny.
#' @return An htmlwidget.
#' @export
#' @examples
#' if (interactive()) {
#'   excalidraw(exc_scene(exc_rect(0, 0, 160, 80, label = "Edit me!", fill = "yellow")))
#' }
excalidraw <- function(scene = exc_scene(), mode = c("edit", "view"), theme = c("light", "dark"),
                       grid = FALSE, zen = FALSE, width = NULL, height = NULL,
                       elementId = NULL, debounce = 400) {
  mode <- match.arg(mode)
  theme <- match.arg(theme)
  scene <- as_excalidraw(scene)
  htmlwidgets::createWidget(
    "excalidraw",
    x = list(scene = scene_to_json(scene), mode = mode, theme = theme, grid = grid,
             zen = zen, debounce = debounce),
    width = width, height = height, package = "excalidrawer", elementId = elementId,
    dependencies = list(excalidraw_dependency()),
    sizingPolicy = htmlwidgets::sizingPolicy(
      defaultWidth = "100%", defaultHeight = 600, padding = 0,
      viewer.fill = TRUE, browser.fill = TRUE, knitr.figure = FALSE
    )
  )
}

excalidraw_dependency <- function() {
  htmltools::htmlDependency(
    name = "excalidraw-widget",
    version = "0.18.1",
    src = c(file = pkg_file("htmlwidgets", "lib", "excalidraw-widget")),
    script = list(src = "excalidraw-widget.js", type = "module"),
    stylesheet = "excalidraw-widget.css",
    all_files = TRUE
  )
}

#' Excalidraw in Shiny
#'
#' Output and render functions for the [excalidraw()] widget. The widget
#' reports back to the server as:
#' * `input$<outputId>_scene`: the scene as Excalidraw JSON, shortly after
#'   each edit. Turn it into a scene with [exc_scene_from_json()].
#' * `input$<outputId>_selection`: ids of the selected elements.
#' * `input$<outputId>_export`: the result of [exc_proxy_export()].
#' * `input$<outputId>_mermaid`: whether a [exc_proxy_mermaid()] call worked.
#'
#' @param outputId Output id.
#' @param width,height Size of the editor.
#' @param expr An expression that returns an [excalidraw()] widget.
#' @param env,quoted Standard htmlwidgets arguments.
#' @return A Shiny output or render function.
#' @export
excalidrawOutput <- function(outputId, width = "100%", height = "600px") {
  htmlwidgets::shinyWidgetOutput(outputId, "excalidraw", width, height, package = "excalidrawer")
}

#' @rdname excalidrawOutput
#' @export
renderExcalidraw <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  htmlwidgets::shinyRenderWidget(expr, excalidrawOutput, env, quoted = TRUE)
}

#' Turn Excalidraw JSON into a scene
#'
#' Useful for the `input$<id>_scene` value sent by the editor in Shiny.
#'
#' @param json A JSON string in Excalidraw's file format.
#' @return An `exc_scene`.
#' @export
exc_scene_from_json <- function(json) {
  if (is.null(json) || !nzchar(json)) return(exc_scene())
  scene_from_json(json)
}

#' Control an Excalidraw editor from the Shiny server
#'
#' Create a proxy for an [excalidrawOutput()] and send it commands without
#' re-rendering the editor (so hand-drawn changes are kept).
#'
#' @param outputId The editor's output id.
#' @param session The Shiny session.
#' @return `excalidraw_proxy()` returns a proxy object; the other functions
#'   return the proxy invisibly, so they can be piped.
#' @name excalidraw_proxy
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   output$canvas <- renderExcalidraw(excalidraw())
#'   observeEvent(input$add_note, {
#'     excalidraw_proxy("canvas") |>
#'       exc_proxy_add(exc_rect(0, 0, 160, 80, label = "New note", fill = "yellow"))
#'   })
#' }
#' }
NULL

#' @rdname excalidraw_proxy
#' @export
excalidraw_proxy <- function(outputId, session = shiny::getDefaultReactiveDomain()) {
  if (is.null(session)) cli::cli_abort("{.fn excalidraw_proxy} must be called from a Shiny server function.")
  structure(list(id = session$ns(outputId), session = session), class = "excalidraw_proxy")
}

proxy_send <- function(proxy, method, args = list()) {
  if (!inherits(proxy, "excalidraw_proxy")) cli::cli_abort("{.arg proxy} must come from {.fn excalidraw_proxy}.")
  proxy$session$sendCustomMessage("excalidrawer-proxy",
                                  list(id = proxy$id, method = method, args = args))
  invisible(proxy)
}

as_scene_json <- function(x) {
  if (inherits(x, "exc_scene")) return(scene_to_json(x))
  if (inherits(x, "exc_elements")) return(scene_to_json(exc_scene(x)))
  scene_to_json(as_excalidraw(x))
}

#' @rdname excalidraw_proxy
#' @param scene A scene, elements, or anything [as_excalidraw()] accepts.
#' @param keep_app_state Keep the editor's current canvas settings.
#' @export
exc_proxy_update <- function(proxy, scene, keep_app_state = FALSE) {
  proxy_send(proxy, "update", list(scene = as_scene_json(scene), keepAppState = keep_app_state))
}

#' @rdname excalidraw_proxy
#' @param placement `"as-is"` keeps the elements' coordinates; `"right"`
#'   places them to the right of what's already there.
#' @export
exc_proxy_add <- function(proxy, scene, placement = c("as-is", "right")) {
  proxy_send(proxy, "add", list(scene = as_scene_json(scene), placement = match.arg(placement)))
}

#' @rdname excalidraw_proxy
#' @param chart A name for the chart. Elements from an earlier call with the
#'   same name are replaced (in the same place); everything else stays.
#' @export
exc_proxy_replace_chart <- function(proxy, scene, chart = "chart") {
  proxy_send(proxy, "replaceChart", list(scene = as_scene_json(scene), chart = chart))
}

#' @rdname excalidraw_proxy
#' @export
exc_proxy_scroll_to <- function(proxy) proxy_send(proxy, "scrollTo")

#' @rdname excalidraw_proxy
#' @param theme,view_mode,zen,grid,background Editor settings to change.
#' @export
exc_proxy_set <- function(proxy, theme = NULL, view_mode = NULL, zen = NULL, grid = NULL,
                          background = NULL) {
  proxy_send(proxy, "set", compact(list(theme = theme, viewMode = view_mode, zen = zen,
                                        grid = grid, background = background)))
}

#' @rdname excalidraw_proxy
#' @export
exc_proxy_reset <- function(proxy) proxy_send(proxy, "reset")

#' @rdname excalidraw_proxy
#' @param type Export format, `"png"` or `"svg"`. The result arrives as
#'   `input$<outputId>_export`: a list with `type` and `data` (base64 PNG or
#'   SVG text).
#' @param embed Embed the scene in the image so it stays editable.
#' @param scale PNG pixel density.
#' @export
exc_proxy_export <- function(proxy, type = c("png", "svg"), embed = FALSE, scale = 2) {
  proxy_send(proxy, "export", list(type = match.arg(type), embed = embed, scale = scale,
                                   nonce = as.numeric(Sys.time())))
}

#' @rdname excalidraw_proxy
#' @param code Mermaid diagram text, such as `"flowchart LR\n A --> B"`.
#' @param font_size Font size for the diagram text.
#' @export
exc_proxy_mermaid <- function(proxy, code, font_size = 20) {
  proxy_send(proxy, "mermaid", list(code = code, fontSize = font_size))
}

#' Edit a scene by hand in the Excalidraw editor
#'
#' Opens the scene in the real Excalidraw editor (in the RStudio viewer or a
#' browser). Draw, move things around, add notes, then click **Done** to get
#' the edited scene back in R.
#'
#' @param scene An `exc_scene`, or anything [as_excalidraw()] accepts.
#' @param viewer Where to open the editor; see [shiny::runGadget()].
#' @param title Title shown above the editor.
#' @return The edited `exc_scene`, or the original if nothing was changed.
#'   `NULL` (invisibly) if you click Cancel.
#' @export
#' @examples
#' if (interactive()) {
#'   s <- exc_edit(exc_scene(exc_text("Draw something!", 0, 0, font_size = 28)))
#'   write_excalidraw(s, "drawing.excalidraw")
#' }
exc_edit <- function(scene = exc_scene(), viewer = shiny::paneViewer(minHeight = 650),
                     title = "Edit drawing") {
  rlang::check_installed(c("shiny", "miniUI"))
  scene <- as_excalidraw(scene)
  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(title),
    miniUI::miniContentPanel(excalidrawOutput("canvas", height = "100%"), padding = 0)
  )
  server <- function(input, output, session) {
    output$canvas <- renderExcalidraw(excalidraw(scene))
    shiny::observeEvent(input$done, {
      json <- input$canvas_scene
      shiny::stopApp(if (is.null(json)) scene else keep_meta(scene_from_json(json), scene))
    })
    shiny::observeEvent(input$cancel, shiny::stopApp(invisible(NULL)))
  }
  shiny::runGadget(ui, server, viewer = viewer, stopOnCancel = FALSE)
}

# R-only settings (paper, data coordinates) survive a trip through the editor.
keep_meta <- function(new, old) {
  new$meta <- old$meta
  new
}
