test_that("bundled sticker libraries are listed and placeable", {
  st <- exc_stickers()
  expect_true(all(c("emojis", "stick-figures", "r-icons", "bubbles") %in% st$library))
  expect_true("stick-figures:Girl" %in% st$sticker)
  s <- exc_scene() |>
    exc_sticker("stick-figures:Girl", 10, 20, width = 80) |>
    exc_sticker("emojis:3", 100, 20, width = 40, stroke = "red")
  els <- s$elements
  expect_gt(length(els), 2)
  expect_true(all(vapply(els, function(e) e$customData$excalidrawer$role, "") == "annotation"))
  girl <- Filter(function(e) length(e$groupIds) && e$x < 95, els)
  bb <- exc_bbox(new_elements(girl), stroke = FALSE)
  expect_equal(unname(bb[c("xmin", "ymin")]), c(10, 20), tolerance = 0.5)
  expect_equal(bb[["width"]], 80, tolerance = 0.5)
  emoji <- Filter(function(e) e$x >= 95, els)
  expect_true(all(vapply(emoji, function(e) e$strokeColor, "") == "#e03131"))
  expect_error(exc_sticker(exc_scene(), "nope:1"), "Unknown sticker library|cannot open|Can't find")
})

test_that("sticker sheets lay out every item with its number", {
  sheet <- exc_sticker_sheet("hearts", columns = 3)
  labels <- Filter(function(e) e$type == "text", sheet$elements)
  expect_equal(length(labels), nrow(exc_stickers("hearts")))
})

test_that("Open Peeps are deterministic SVG images", {
  a <- exc_peep(NULL, 0, 0, seed = "Ada", face = "smile")
  b <- exc_peep(NULL, 0, 0, seed = "Ada", face = "smile")
  c <- exc_peep(NULL, 0, 0, seed = "Grace")
  file_a <- attr(a, "files")[[1]]
  expect_equal(file_a$mimeType, "image/svg+xml")
  expect_identical(file_a$dataURL, attr(b, "files")[[1]]$dataURL)
  expect_false(identical(file_a$dataURL, attr(c, "files")[[1]]$dataURL))
  expect_true("smile" %in% exc_peep_options()$face)
  s <- exc_peep(exc_scene(), 10, 10, size = 100, seed = 1)
  expect_length(s$files, 1)
})

test_that("templates fill text, charts and images", {
  skip_if_not_installed("ggplot2")
  card <- exc_template_fill(
    exc_template_example(),
    data = data.frame(metric = "Coffees", value = 1234.5, change = "+3"),
    charts = list(trend = function(row) ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) +
                    ggplot2::geom_point())
  )
  texts <- vapply(Filter(function(e) e$type == "text", card$elements), function(e) e$text, "")
  expect_true("Coffees" %in% texts)
  expect_true("1,234.5" %in% texts)
  expect_false(any(grepl("{{", texts, fixed = TRUE)))
  chart <- Filter(function(e) identical(e$customData$excalidrawer$chart, "trend"), card$elements)
  expect_gt(length(chart), 10)
  slot <- Filter(function(e) e$type == "rectangle" && identical(e$strokeStyle, "dashed"), card$elements)[[1]]
  bb <- exc_bbox(new_elements(chart), stroke = FALSE)
  expect_gte(bb[["xmin"]], slot$x - 1)
  expect_lte(bb[["xmax"]], slot$x + slot$width + 1)
  expect_true(keys_in_order(lapply(card$elements, function(e) e$index)))
})

test_that("image slots and batch rendering work", {
  skip_if_not_installed("ragg")
  png_file <- withr::local_tempfile(fileext = ".png")
  grDevices::png(png_file, width = 40, height = 20)
  grid::grid.rect(gp = grid::gpar(fill = "orange"))
  grDevices::dev.off()
  tpl <- exc_scene(exc_text("Hi {{name}}", 0, 0), exc_rect(0, 40, 200, 100, label = "{{image:pic}}"))
  filled <- exc_template_fill(tpl, list(name = "Ada", pic = png_file))
  img <- Filter(function(e) e$type == "image", filled$elements)
  expect_length(img, 1)
  expect_equal(img[[1]]$width / img[[1]]$height, 2, tolerance = 0.01)
  dir <- withr::local_tempdir()
  paths <- exc_template_render(tpl, data.frame(name = c("Ada", "Grace"), pic = png_file),
                               dir = dir, file = "hi-{name}.png", images = list(pic = png_file))
  expect_equal(basename(paths), c("hi-Ada.png", "hi-Grace.png"))
  expect_true(all(file.exists(paths)))
  paths2 <- exc_template_render(tpl, data.frame(name = "Ada", pic = png_file), dir = dir,
                                file = "hi.excalidraw")
  expect_s3_class(read_excalidraw(paths2), "exc_scene")
})

test_that("D2 diagrams render when d2 is installed", {
  skip_if(!nzchar(Sys.which("d2")), "d2 not installed")
  s <- exc_d2("a -> b")
  expect_equal(s$elements[[1]]$type, "image")
})
