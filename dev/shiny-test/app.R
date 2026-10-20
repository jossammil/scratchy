# Dev app: exercise the excalidraw widget's Shiny bindings and proxy.
library(shiny)
library(ggplot2)

bars <- function(fill) {
  as_excalidraw(ggplot(mpg, aes(class)) + geom_bar(fill = fill) + labs(title = "Cars", x = NULL),
                width = 640, height = 400, id = "main")
}

ui <- fluidPage(
  tags$style("body { padding: 8px; } .btn { margin: 2px; }"),
  div(
    actionButton("note", "Add note"),
    actionButton("chart", "Replace chart"),
    actionButton("mermaid", "Mermaid"),
    actionButton("export", "Export PNG"),
    span(id = "status", textOutput("status", inline = TRUE))
  ),
  excalidrawOutput("canvas", height = "520px")
)

server <- function(input, output, session) {
  output$canvas <- renderExcalidraw(excalidraw(bars("#a5d8ff")))
  proxy <- excalidraw_proxy("canvas")
  observeEvent(input$note, {
    exc_proxy_add(proxy, exc_rect(700, 40, 180, 90, label = "Hand note!", fill = "yellow", rounded = TRUE))
  })
  observeEvent(input$chart, exc_proxy_replace_chart(proxy, bars("#ffc9c9"), chart = "main"))
  observeEvent(input$mermaid, exc_proxy_mermaid(proxy, "flowchart LR\n  A[Data] --> B[Sketch] --> C[Share]"))
  observeEvent(input$export, exc_proxy_export(proxy, "png"))
  exported <- reactiveVal("none")
  observeEvent(input$canvas_export, {
    f <- file.path(tempdir(), "export.png")
    writeBin(jsonlite::base64_dec(input$canvas_export$data), f)
    exported(paste0(input$canvas_export$type, " ", file.size(f), " bytes"))
  })
  output$status <- renderText({
    s <- exc_scene_from_json(input$canvas_scene)
    types <- table(vapply(s$elements, function(e) e$type, ""))
    paste0("elements=", length(s$elements), " [", paste(names(types), types, sep = ":", collapse = " "),
           "] mermaid=", if (is.null(input$canvas_mermaid)) "-" else input$canvas_mermaid$ok,
           " export=", exported())
  })
}

shinyApp(ui, server)
