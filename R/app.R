#' Sketch Studio: a point-and-click app for hand-drawn charts
#'
#' A Shiny app built on excalidrawer:
#' 1. **Data**: pick a built-in dataset, upload a CSV or paste from a
#'    spreadsheet.
#' 2. **Chart**: choose a chart type and what goes on each axis.
#' 3. **Style**: preset, sloppiness, fill, font, grid, and a new wobble.
#' 4. **Add**: sticky notes, stickers, hand-drawn people and Mermaid
#'    diagrams, straight onto the canvas.
#' 5. **Templates**: fill an Excalidraw template from a CSV, one image per row.
#' 6. **Export**: PNG, SVG, PDF, `.excalidraw`, Obsidian `.excalidraw.md`, an
#'    editable `.excalidraw.svg`, and the R code that recreates the chart.
#'
#' The canvas is the real Excalidraw editor: draw, move and annotate freely.
#' Changing chart settings swaps only the chart; your drawing stays.
#'
#' @param ... Options passed to [shiny::shinyApp()], such as `port`.
#' @param launch.browser Open the app in a browser.
#' @return A Shiny app object; printing it (or calling the function at the
#'   console) runs the app.
#' @export
#' @examples
#' if (interactive()) run_sketch_studio()
run_sketch_studio <- function(..., launch.browser = interactive()) {
  rlang::check_installed(c("shiny", "bslib"))
  shiny::shinyApp(studio_ui(), studio_server,
                  options = c(list(launch.browser = launch.browser), list(...)))
}

studio_fonts <- c("Excalifont", "Virgil", "Comic Shanns", "Nunito", "Lilita One",
                  "Caveat *" = "Caveat", "Patrick Hand *" = "Patrick Hand",
                  "Architects Daughter *" = "Architects Daughter", "Gochi Hand *" = "Gochi Hand")

studio_ui <- function() {
  shiny::addResourcePath("excalidrawer-fonts", pkg_file("fonts"))
  shiny::addResourcePath("excalidrawer-studio", pkg_file("app", "www"))
  theme <- bslib::bs_theme(
    version = 5, bg = "#fdfcf7", fg = "#1e1e1e", primary = "#1971c2", secondary = "#868e96",
    success = "#2f9e44", danger = "#e03131", warning = "#f08c00",
    base_font = "Nunito, system-ui, sans-serif", heading_font = "Excalifont, cursive",
    code_font = "'Cascadia Code', monospace"
  )
  faces <- tryCatch(exc_peep_options()$face, error = function(e) "smile")
  bslib::page_sidebar(
    title = shiny::tags$span(class = "studio-title", "Sketch Studio",
                             shiny::tags$small(" hand-drawn charts with excalidrawer")),
    window_title = "Sketch Studio",
    theme = theme,
    shiny::tags$head(shiny::tags$link(rel = "stylesheet", href = "excalidrawer-studio/studio.css")),
    sidebar = bslib::sidebar(
      width = 340, open = "always",
      bslib::accordion(
        id = "steps", open = c("1. Data", "2. Chart"),
        bslib::accordion_panel(
          "1. Data",
          shiny::selectInput("dataset", NULL, c(names(studio_datasets()), "Upload a CSV", "Paste data")),
          shiny::conditionalPanel(
            "input.dataset == 'Upload a CSV'",
            shiny::fileInput("upload", NULL, accept = c(".csv", ".tsv", ".txt"))
          ),
          shiny::conditionalPanel(
            "input.dataset == 'Paste data'",
            shiny::textAreaInput("paste", NULL, rows = 5,
                                 placeholder = "Paste from a spreadsheet, with a header row")
          ),
          shiny::uiOutput("data_info")
        ),
        bslib::accordion_panel(
          "2. Chart",
          shiny::selectInput("type", "Chart type", .studio_charts),
          shiny::selectInput("x", "x", NULL),
          shiny::selectInput("y", "y", NULL),
          shiny::selectInput("group", "Colour by", NULL),
          shiny::selectInput("facet", "Small multiples by", NULL),
          shiny::textInput("title", "Title", "My hand-drawn chart"),
          shiny::textInput("subtitle", "Subtitle", "")
        ),
        bslib::accordion_panel(
          "3. Style",
          shiny::selectInput("preset", "Preset", names(.presets)),
          shiny::sliderInput("roughness", "Sloppiness", min = 0, max = 2, value = 1, step = 0.25),
          shiny::radioButtons("fill_style", "Fill", c("hachure", "cross-hatch", "solid", "zigzag"),
                              inline = TRUE),
          shiny::selectInput("font", "Font", studio_fonts),
          shiny::helpText("* shows in exports; the editor uses Excalifont for it."),
          shiny::selectInput("grid", "Grid lines", c("y", "x", "xy", "none")),
          shiny::actionButton("reroll", paste("\U0001f3b2", "New wobble"), class = "btn-outline-primary w-100")
        ),
        bslib::accordion_panel(
          "4. Add",
          shiny::textInput("note_text", "Sticky note", "Look here!"),
          shiny::actionButton("add_note", "Add note", class = "w-100"),
          shiny::hr(),
          shiny::selectInput("sticker_lib", "Sticker library", sticker_manifest()$library),
          shiny::imageOutput("sticker_preview", height = "auto"),
          shiny::numericInput("sticker_item", "Sticker number", value = 1, min = 1),
          shiny::actionButton("add_sticker", "Add sticker", class = "w-100"),
          shiny::hr(),
          shiny::textInput("peep_seed", "Person (any name)", "Ada"),
          shiny::selectInput("peep_face", NULL, faces, selected = if ("smile" %in% faces) "smile" else faces[1]),
          shiny::actionButton("add_peep", "Add person", class = "w-100"),
          shiny::hr(),
          shiny::textAreaInput("mermaid", "Diagram (Mermaid)", rows = 4,
                               value = "flowchart LR\n  A[Data] --> B[Sketch] --> C[Share]"),
          shiny::actionButton("add_mermaid", "Add diagram", class = "w-100")
        ),
        bslib::accordion_panel(
          "5. Templates",
          shiny::helpText("Text {{column}}, slots {{chart:name}} and {{image:name}}."),
          shiny::fileInput("tpl_file", "Template (.excalidraw)", accept = c(".excalidraw", ".json", ".md", ".svg", ".png")),
          shiny::fileInput("tpl_csv", "Data (CSV)", accept = c(".csv", ".tsv", ".txt")),
          shiny::textInput("tpl_name", "File names", "card-{.row}"),
          shiny::selectInput("tpl_format", "Format", c("png", "svg", "pdf", "excalidraw")),
          shiny::downloadButton("tpl_download", "Render all (zip)", class = "w-100")
        ),
        bslib::accordion_panel(
          "6. Export",
          shiny::selectInput("paper", "Paper (images)", exc_papers()),
          shiny::div(
            class = "d-grid gap-2",
            shiny::downloadButton("dl_png", "PNG"),
            shiny::downloadButton("dl_svg", "SVG"),
            shiny::downloadButton("dl_pdf", "PDF"),
            shiny::downloadButton("dl_excalidraw", ".excalidraw"),
            shiny::downloadButton("dl_obsidian", "Obsidian .excalidraw.md"),
            shiny::downloadButton("dl_editable_svg", "Editable .excalidraw.svg"),
            shiny::downloadButton("dl_code", "R code")
          )
        )
      )
    ),
    bslib::navset_card_underline(
      bslib::nav_panel("Canvas", excalidrawOutput("canvas", height = "calc(100vh - 170px)")),
      bslib::nav_panel("R code", shiny::verbatimTextOutput("code")),
      bslib::nav_panel("Data", shiny::tableOutput("table"))
    )
  )
}

studio_server <- function(input, output, session) {
  data <- shiny::reactive({
    ds <- studio_datasets()
    if (input$dataset %in% names(ds)) return(ds[[input$dataset]]())
    if (input$dataset == "Upload a CSV") {
      shiny::req(input$upload)
      return(studio_read_text(paste(readLines(input$upload$datapath, warn = FALSE), collapse = "\n")))
    }
    shiny::req(nzchar(trimws(input$paste)))
    studio_read_text(input$paste)
  })

  output$data_info <- shiny::renderUI({
    d <- data()
    shiny::helpText(sprintf("%s rows, %s columns", format(nrow(d), big.mark = ","), ncol(d)))
  })
  output$table <- shiny::renderTable(utils::head(data(), 100))

  shiny::observeEvent(data(), {
    d <- data()
    cols <- names(d)
    def <- studio_defaults(d)
    shiny::updateSelectInput(session, "x", choices = cols, selected = def$x)
    shiny::updateSelectInput(session, "y", choices = cols, selected = def$y)
    shiny::updateSelectInput(session, "group", choices = c("(none)", cols), selected = "(none)")
    shiny::updateSelectInput(session, "facet", choices = c("(none)", cols), selected = "(none)")
  })

  shiny::observeEvent(input$preset, {
    p <- .presets[[input$preset]]
    shiny::updateSliderInput(session, "roughness", value = p$roughness)
    shiny::updateRadioButtons(session, "fill_style", selected = p$fill_style)
    shiny::updateSelectInput(session, "font", selected = p$font)
  }, ignoreInit = TRUE)

  seed <- shiny::reactiveVal(1)
  shiny::observeEvent(input$reroll, seed(sample.int(100000, 1)))

  spec <- shiny::debounce(shiny::reactive({
    shiny::req(input$x, input$y)
    list(type = input$type, x = input$x, y = input$y, group = input$group, facet = input$facet,
         title = input$title, subtitle = input$subtitle, font = input$font, grid = input$grid)
  }), 500)

  code <- shiny::reactive(studio_code(spec()))

  scene <- shiny::reactive({
    d <- data()
    shiny::req(all(c(spec()$x, spec()$y) %in% names(d)) || spec()$type %in% c("bar", "histogram"))
    p <- tryCatch(studio_plot(code(), d), error = function(e) {
      shiny::showNotification(conditionMessage(e), type = "error")
      NULL
    })
    shiny::req(p)
    s <- tryCatch(
      as_excalidraw(p, width = 820, height = 520, theme = NULL, fill_style = input$fill_style,
                    roughness = input$roughness, font = input$font, seed = seed(), id = "chart"),
      error = function(e) {
        shiny::showNotification(conditionMessage(e), type = "error")
        NULL
      })
    shiny::req(s)
    if (input$preset != "whiteboard") {
      s <- exc_restyle(s, input$preset, font = input$font, roughness = input$roughness,
                       fill_style = input$fill_style)
    }
    s
  })

  # The editor is rendered once; the chart arrives (and is later swapped)
  # through the proxy so hand-drawn additions are never lost.
  output$canvas <- renderExcalidraw(excalidraw(exc_scene(), extras = FALSE))
  proxy <- excalidraw_proxy("canvas")
  shiny::observeEvent(scene(), {
    exc_proxy_replace_chart(proxy, scene(), chart = "chart")
    exc_proxy_set(proxy, background = scene()$appState$viewBackgroundColor)
  })

  current <- shiny::reactive({
    s <- exc_scene_from_json(input$canvas_scene)
    if (length(s$elements) == 0) s <- scene()
    s$meta$paper <- if (input$paper == "plain") NULL else input$paper
    s
  })

  # --- add things to the canvas ---
  shiny::observeEvent(input$add_note, {
    note <- exc_rect(0, 0, 200, 90, label = input$note_text, fill = "yellow", fill_style = "solid",
                     rounded = TRUE, angle = -2, stroke = "#f08c00")
    exc_proxy_add(proxy, note, placement = "right")
  })
  output$sticker_preview <- shiny::renderImage({
    f <- file.path(tempdir(), paste0("sheet-", input$sticker_lib, ".png"))
    if (!file.exists(f)) exc_save(exc_sticker_sheet(input$sticker_lib, columns = 6), f, scale = 0.6)
    list(src = f, width = "100%", alt = paste("Stickers in", input$sticker_lib))
  }, deleteFile = FALSE)
  shiny::observeEvent(input$sticker_lib, {
    n <- nrow(exc_stickers(input$sticker_lib))
    shiny::updateNumericInput(session, "sticker_item", max = n, value = min(input$sticker_item %||% 1, n))
  })
  shiny::observeEvent(input$add_sticker, {
    st <- exc_sticker(exc_scene(), paste0(input$sticker_lib, ":", input$sticker_item), width = 120)
    exc_proxy_add(proxy, st, placement = "right")
  })
  shiny::observeEvent(input$add_peep, {
    exc_proxy_add(proxy, exc_peep(exc_scene(), seed = input$peep_seed, face = input$peep_face),
                  placement = "right")
  })
  shiny::observeEvent(input$add_mermaid, exc_proxy_mermaid(proxy, input$mermaid))
  shiny::observeEvent(input$canvas_mermaid, {
    if (!isTRUE(input$canvas_mermaid$ok)) {
      shiny::showNotification(paste("Mermaid:", input$canvas_mermaid$message), type = "error")
    }
  })

  # --- code ---
  data_code <- shiny::reactive({
    switch(input$dataset,
      "Cars (mpg)" = "data <- ggplot2::mpg",
      "Penguins" = "data <- na.omit(datasets::penguins)",
      "Economics" = "data <- ggplot2::economics",
      "Old Faithful" = "data <- faithful",
      "Iris" = "data <- iris",
      "Motor cars (mtcars)" = "data <- cbind(car = rownames(mtcars), mtcars)",
      'data <- read.csv("your-data.csv")'
    )
  })
  full_code <- shiny::reactive({
    paste0(
      "library(ggplot2)\nlibrary(excalidrawer)\n\n", data_code(), "\n\n",
      "p <- ", code(), "\n\n",
      sprintf("s <- as_excalidraw(p, width = 820, height = 520, theme = NULL, fill_style = %s,\n                   roughness = %s, font = %s, seed = %s)\n",
              deparse(input$fill_style), input$roughness, deparse(input$font), seed()),
      if (input$preset != "whiteboard") sprintf("s <- exc_restyle(s, %s)\n", deparse(input$preset)) else "",
      "exc_save(s, \"chart.png\", scale = 2)\n",
      "# edit by hand: s <- exc_edit(s)\n",
      "# or open the canvas you saved from the app: s <- read_excalidraw(\"drawing.excalidraw\")\n"
    )
  })
  output$code <- shiny::renderText(full_code())

  # --- downloads ---
  save_as <- function(name, writer) {
    shiny::downloadHandler(
      filename = function() name,
      content = function(file) {
        tmp <- file.path(tempfile("studio"), name)
        dir.create(dirname(tmp), recursive = TRUE)
        writer(current(), tmp)
        file.copy(tmp, file, overwrite = TRUE)
      }
    )
  }
  output$dl_png <- save_as("drawing.png", function(s, f) exc_save(s, f, scale = 2))
  output$dl_svg <- save_as("drawing.svg", function(s, f) exc_save(s, f))
  output$dl_pdf <- save_as("drawing.pdf", function(s, f) exc_save(s, f))
  output$dl_excalidraw <- save_as("drawing.excalidraw", function(s, f) write_excalidraw(s, f))
  output$dl_obsidian <- save_as("drawing.excalidraw.md", function(s, f) write_excalidraw(s, f))
  output$dl_editable_svg <- save_as("drawing.excalidraw.svg", function(s, f) write_excalidraw(s, f))
  output$dl_code <- shiny::downloadHandler(
    filename = function() "sketch.R",
    content = function(file) writeLines(full_code(), file)
  )

  output$tpl_download <- shiny::downloadHandler(
    filename = function() "cards.zip",
    content = function(file) {
      shiny::req(input$tpl_csv)
      tpl <- if (is.null(input$tpl_file)) exc_template_example() else {
        tmp <- file.path(tempfile("tpl"), input$tpl_file$name)
        dir.create(dirname(tmp), recursive = TRUE)
        file.copy(input$tpl_file$datapath, tmp)
        read_excalidraw(tmp)
      }
      rows <- studio_read_text(paste(readLines(input$tpl_csv$datapath, warn = FALSE), collapse = "\n"))
      dir <- tempfile("cards")
      paths <- exc_template_render(tpl, rows, dir = dir,
                                   file = paste0(input$tpl_name, ".", input$tpl_format), scale = 2)
      old <- setwd(dir)
      on.exit(setwd(old), add = TRUE)
      utils::zip(file, basename(paths), flags = "-q")
    }
  )
}
