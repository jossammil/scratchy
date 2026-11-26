sample_scene <- function() {
  withr::local_seed(42)
  exc_scene(
    exc_rect(0, 0, 160, 80, label = "Hello", fill = "yellow", fill_style = "solid", rounded = TRUE),
    exc_arrow(c(170, 300), c(40, 40), label = "next"),
    exc_ellipse(310, 0, 160, 90, label = "Chart", fill = "blue", fill_style = "hachure"),
    exc_diamond(500, 0, 120, 100, fill = "red", fill_style = "cross-hatch"),
    exc_text("Sketchy title", 0, 120, font_size = 28),
    exc_line(c(0, 80, 40), c(160, 160, 220), closed = TRUE, fill = "green"),
    exc_freedraw(300 + cos(seq(0, 6, 0.2)) * 30, 180 + sin(seq(0, 6, 0.2)) * 30),
    exc_arrow(c(500, 600, 650), c(200, 150, 220), curved = TRUE, start = "circle", end = "triangle",
              stroke_style = "dashed")
  )
}

test_that("rough geometry is deterministic for a seed", {
  el <- exc_rect(0, 0, 100, 50, fill = "blue", fill_style = "hachure", seed = 7)
  a <- rough_parts(unclass(el))
  b <- rough_parts(unclass(el))
  expect_identical(a, b)
  kinds <- vapply(a[[1]], function(p) p$kind, "")
  expect_true(all(c("stroke") %in% kinds))
  expect_equal(a[[1]][[1]]$color, "#a5d8ff")
})

test_that("arrow labels cut the arrow line", {
  s <- exc_scene(exc_arrow(c(0, 300), c(0, 0), label = "label"))
  els <- prepare_for_js(Filter(function(e) e$type == "arrow", s$elements), s$elements)
  box <- els[[1]]$`__labelBox`
  parts <- rough_parts(els)[[1]]
  body <- parts[[1]]$paths
  xs <- unlist(lapply(body, function(p) p[seq(1, length(p), 2)]))
  ys <- unlist(lapply(body, function(p) p[seq(2, length(p), 2)]))
  inside <- xs > box[1] + 0.01 & xs < box[3] - 0.01 & ys > box[2] + 0.01 & ys < box[4] - 0.01
  expect_false(any(inside))
  expect_gt(length(body), 1)
})

test_that("exc_grob draws on any device", {
  s <- sample_scene()
  g <- exc_grob(s)
  expect_s3_class(g, "exc_grob")
  f <- withr::local_tempfile(fileext = ".pdf")
  grDevices::pdf(f, width = 6, height = 3)
  grid::grid.draw(g)
  grDevices::dev.off()
  expect_gt(file.size(f), 1000)
})

test_that("exc_save writes png, svg and pdf at the scene's size", {
  skip_if_not_installed("ragg")
  skip_if_not_installed("svglite")
  s <- sample_scene()
  bb <- exc_bbox(s)
  png_file <- withr::local_tempfile(fileext = ".png")
  exc_save(s, png_file, scale = 2)
  dims <- dim(png::readPNG(png_file))
  expect_equal(dims[2], round((bb[["width"]] + 20) * 2), tolerance = 2)
  svg_file <- withr::local_tempfile(fileext = ".svg")
  exc_save(s, svg_file)
  svg <- paste(readLines(svg_file, warn = FALSE), collapse = "")
  expect_match(svg, "@font-face")
  expect_match(svg, "font/woff2;base64")
  pdf_file <- withr::local_tempfile(fileext = ".pdf")
  exc_save(s, pdf_file)
  expect_gt(file.size(pdf_file), 1000)
})

test_that("text can be drawn as outlines", {
  lay <- text_layout(exc_text("Hi there", 10, 20, font_size = 20)[[1]])
  o <- text_outlines(lay)
  expect_true(all(o$x >= 9 & o$x <= 10 + max(lay$widths) + 2))
  expect_true(all(o$y >= 20 - 2 & o$y <= 20 + 25 + 2))
})

test_that("presets restyle elements and remember the paper", {
  s <- exc_restyle(sample_scene(), "chalkboard")
  expect_equal(s$appState$viewBackgroundColor, "#2f3d33")
  expect_equal(s$meta$paper, "chalkboard")
  df <- as.data.frame(s)
  expect_true(all(df$strokeColor[df$type == "text"] == "#f1f3f5"))
  expect_true(all(df$roughness[df$type == "rectangle"] == 2))
  t <- Filter(function(e) e$type == "text", s$elements)[[1]]
  expect_equal(t$customData$excalidrawer$font, "Architects Daughter")
})

test_that("rendered scenes match snapshots", {
  skip_if_not_installed("vdiffr")
  s <- sample_scene()
  vdiffr::expect_doppelganger("sample scene", function() plot(s, text = "outline"))
  vdiffr::expect_doppelganger("blueprint preset", function() {
    plot(exc_restyle(s, "blueprint"), text = "outline")
  })
})

test_that("PDFs fall back to R's pdf() device when cairo can't open", {
  f <- withr::local_tempfile(fileext = ".pdf")
  # As on macOS without XQuartz: cairo_pdf() prints a message and opens nothing.
  open_pdf(f, 3, 2, cairo = function(...) message("failed to load cairo DLL"))
  expect_equal(names(grDevices::dev.cur()), "pdf")
  grid::grid.draw(exc_grob(exc_scene(exc_rect(0, 0, 100, 50, label = "PDF"))))
  grDevices::dev.off()
  expect_identical(readBin(f, "raw", 4), charToRaw("%PDF"))
})
