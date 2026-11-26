skip_if_not_installed("shiny")
skip_if_not_installed("bslib")

test_that("chart code is generated for every chart type", {
  d <- as.data.frame(ggplot2::mpg)
  for (type in .studio_charts) {
    spec <- list(type = type, x = if (type %in% c("histogram", "point", "line", "area")) "displ" else "class",
                 y = "hwy", group = "drv", facet = "(none)", title = "T", subtitle = "", font = "Excalifont",
                 grid = "y")
    code <- studio_code(spec)
    p <- studio_plot(code, d)
    expect_s3_class(p, "ggplot")
  }
  code <- studio_code(list(type = "bar", x = "my col", y = "hwy", group = "(none)", facet = "(none)",
                           title = "", subtitle = "", font = "Virgil", grid = "none"))
  expect_match(code, "`my col`", fixed = TRUE)
  expect_match(code, 'geom_bar(fill = "#a5d8ff")', fixed = TRUE)
})

test_that("default axes favour a categorical column with a few levels", {
  expect_equal(studio_defaults(as.data.frame(ggplot2::mpg))$x, "class")
  expect_equal(studio_defaults(as.data.frame(ggplot2::mpg))$y, "displ")
})

test_that("pasted spreadsheet data is read with the right separator", {
  expect_equal(ncol(studio_read_text("a\tb\n1\t2")), 2)
  expect_equal(ncol(studio_read_text("a;b\n1;2")), 2)
  expect_equal(ncol(studio_read_text("a,b\n1,2")), 2)
})

test_that("the studio server builds a scene and serves downloads", {
  shiny::testServer(studio_server, {
    session$setInputs(dataset = "Cars (mpg)", type = "bar", x = "class", y = "hwy", group = "(none)",
                      facet = "(none)", title = "Cars", subtitle = "", font = "Excalifont", grid = "y",
                      preset = "whiteboard", roughness = 1, fill_style = "hachure", paper = "plain")
    session$elapse(1000)
    s <- scene()
    expect_s3_class(s, "exc_scene")
    expect_true(all(vapply(s$elements, function(e) e$customData$scratchy$chart, "") == "chart"))
    expect_match(output$code, "geom_bar", fixed = TRUE)
    png <- output$dl_png
    expect_true(file.exists(png))
    expect_gt(file.size(png), 1000)
    md <- output$dl_obsidian
    expect_true(any(grepl("excalidraw-plugin: parsed", readLines(md))))
    svg <- output$dl_editable_svg
    f <- file.path(tempdir(), "studio-test.excalidraw.svg")
    file.copy(svg, f, overwrite = TRUE)
    expect_s3_class(read_excalidraw(f), "exc_scene")
    session$setInputs(preset = "chalkboard")
    session$elapse(1000)
    expect_equal(scene()$appState$viewBackgroundColor, "#2f3d33")
  })
})
