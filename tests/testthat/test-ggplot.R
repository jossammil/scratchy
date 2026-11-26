skip_if_not_installed("ggplot2")
library(ggplot2)

bars <- ggplot(mpg, aes(class)) + geom_bar(fill = "#a5d8ff")

test_that("ggplots convert to Excalidraw elements", {
  s <- as_excalidraw(bars, width = 800, height = 500)
  df <- as.data.frame(s)
  expect_equal(sum(df$type == "rectangle" & df$role == "data"), 7)
  expect_true(all(df$fontFamily[df$type == "text"] == 5))
  expect_true(any(df$text == "suv", na.rm = TRUE))
  bar <- df[df$type == "rectangle" & df$role == "data", ][1, ]
  expect_equal(bar$fillStyle, "hachure")
  expect_equal(bar$backgroundColor, "#a5d8ff")
  expect_equal(bar$strokeColor, "#1971c2")
  expect_equal(unname(s$meta$size), c(800, 500))
  # every element belongs to one chart group
  groups <- unique(vapply(s$elements, function(e) tail(unlist(e$groupIds), 1), ""))
  expect_length(groups, 1)
})

test_that("conversion is reproducible for a seed", {
  a <- as_excalidraw(bars, seed = 3)
  b <- as_excalidraw(bars, seed = 3)
  seeds <- function(s) vapply(s$elements, function(e) e$seed, 1)
  expect_identical(seeds(a), seeds(b))
  expect_false(identical(seeds(a), seeds(as_excalidraw(bars, seed = 4))))
})

test_that("data coordinates map onto the panel", {
  s <- as_excalidraw(bars, width = 800, height = 500)
  df <- as.data.frame(s)
  suv <- df[df$type == "rectangle" & df$role == "data", ]
  suv <- suv[which.max(suv$x), ]
  p <- exc_data_to_px(s, "suv", 62)
  expect_equal(p$x, suv$x + suv$width / 2, tolerance = 0.5)
  expect_equal(p$y, suv$y, tolerance = 0.5)
  zero <- exc_data_to_px(s, "suv", 0)
  expect_equal(zero$y, suv$y + suv$height, tolerance = 0.5)
  px <- exc_data_to_px(s, I(10), I(20))
  expect_equal(c(px$x, px$y), c(10, 20))
})

test_that("flipped coordinates map correctly", {
  s <- as_excalidraw(bars + coord_flip())
  df <- as.data.frame(s)
  bars_df <- df[df$type == "rectangle" & df$role == "data", ]
  suv <- bars_df[which.min(bars_df$y), ]
  p <- exc_data_to_px(s, "suv", 62)
  expect_equal(p$y, suv$y + suv$height / 2, tolerance = 0.5)
  expect_equal(p$x, suv$x + suv$width, tolerance = 0.5)
})

test_that("facets get one coordinate map per panel", {
  s <- as_excalidraw(ggplot(mpg, aes(displ, hwy)) + geom_point() + facet_wrap(~year))
  expect_length(s$meta$coord, 2)
  p1 <- exc_data_to_px(s, 4, 30, panel = 1)
  p2 <- exc_data_to_px(s, 4, 30, panel = 2)
  expect_gt(p2$x, p1$x)
  expect_equal(p2$y, p1$y)
})

test_that("panel clipping removes out-of-range geometry", {
  p <- ggplot(economics, aes(date, unemploy)) + geom_line() +
    coord_cartesian(xlim = as.Date(c("2000-01-01", "2005-01-01")))
  s <- as_excalidraw(p)
  rect <- s$meta$coord[[1]]$rect
  lines <- Filter(function(e) e$type == "line" && identical(e$customData$excalidrawer$role, "data"), s$elements)
  xs <- unlist(lapply(lines, function(e) e$x + vapply(e$points, `[`, 1, 1)))
  expect_true(all(xs >= rect[["x0"]] - 0.5 & xs <= rect[["x1"]] + 0.5))
})

test_that("base graphics convert", {
  s <- as_excalidraw(~ barplot(c(a = 3, b = 5), col = "#ffec99"))
  df <- as.data.frame(s)
  expect_equal(sum(df$type == "rectangle"), 2)
  expect_null(s$meta$coord)
  expect_error(exc_data_to_px(s, "a", 1), "no data coordinates")
})

test_that("annotations add tagged elements", {
  s <- as_excalidraw(bars) |>
    exc_note("SUVs win!", x = "midsize", y = 50, to = c("suv", 50)) |>
    exc_callout("tiny", x = "2seater", y = 5) |>
    exc_mark(x = "suv", y = c(0, 62), type = "box") |>
    exc_mark(x = "compact", y = 47, type = "highlight") |>
    exc_title("Cars", subtitle = "by class")
  df <- as.data.frame(s)
  ann <- df[df$role %in% "annotation", ]
  expect_true(all(c("rectangle", "arrow", "text", "line") %in% ann$type))
  expect_true(any(ann$text == "SUVs win!", na.rm = TRUE))
  # highlight goes underneath everything else
  expect_equal(df$role[1], "annotation")
  expect_equal(df$opacity[1], 55)
  title <- ann[ann$text %in% "Cars", ]
  expect_lt(title$y, min(df$y[df$role != "annotation"], na.rm = TRUE))
  expect_true(keys_in_order(lapply(s$elements, function(e) e$index)))
})

test_that("sketch() draws at the device size and works with ggsave", {
  skip_if_not_installed("ragg")
  f <- withr::local_tempfile(fileext = ".png")
  ggsave(f, sketch(bars), width = 6, height = 4, dpi = 96, device = ragg::agg_png)
  dims <- dim(png::readPNG(f))
  expect_equal(dims[1:2], c(384, 576))
  s <- as_excalidraw(sketch(bars, width = 600, height = 400))
  expect_equal(unname(s$meta$size), c(600, 400))
})

test_that("presets flow through conversion", {
  s <- as_excalidraw(bars, preset = "blueprint")
  expect_equal(s$appState$viewBackgroundColor, "#1d4f86")
  txt <- Filter(function(e) e$type == "text", s$elements)
  expect_true(all(vapply(txt, function(e) e$fontFamily, 1) == 1))
})

test_that("the SVG reader agrees with xml2 on svglite's output", {
  skip_if_not_installed("xml2")
  p <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg, colour = factor(cyl))) + ggplot2::geom_point() +
    ggplot2::labs(title = "Fuel & weight <test> été")
  cap <- capture_svg(function() print(p), 600, 400)
  mine <- svg_parse(cap$svg)
  doc <- xml2::read_xml(cap$svg)
  xml2::xml_ns_strip(doc)
  count <- function(n) 1L + sum(vapply(n$children, count, 1L))
  expect_equal(count(mine), length(xml2::xml_find_all(doc, "//*")))
  expect_equal(sx_attr(mine, "viewBox"), xml2::xml_attr(doc, "viewBox"))
  texts <- vapply(sx_find_all(mine, "text"), sx_text, "")
  expect_equal(texts, xml2::xml_text(xml2::xml_find_all(doc, "//text")))
  expect_true("Fuel & weight <test> été" %in% texts)
  expect_length(sx_find_all(mine, "clipPath"), length(xml2::xml_find_all(doc, "//clipPath")))
  expect_true(is.na(sx_attr(mine, "no-such-attribute")))
})
