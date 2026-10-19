test_that("constructors fill Excalidraw defaults", {
  r <- exc_rect(10, 20, 100, 50)[[1]]
  expect_equal(r$type, "rectangle")
  expect_equal(r$strokeColor, "#1e1e1e")
  expect_equal(r$backgroundColor, "transparent")
  expect_equal(r$roughness, 1)
  expect_equal(r$strokeWidth, 2)
  expect_null(r$roundness)
  expect_true("frameId" %in% names(r))
  expect_true("boundElements" %in% names(r))
  expect_match(r$id, "^[A-Za-z0-9_-]{20}$")
})

test_that("style names and hue names are normalised", {
  r <- exc_rect(0, 0, 10, 10, stroke = "blue", fill = "blue", roughness = "cartoonist",
                stroke_width = "extra_bold", fill_style = "cross_hatch")[[1]]
  expect_equal(r$strokeColor, "#1971c2")
  expect_equal(r$backgroundColor, "#a5d8ff")
  expect_equal(r$roughness, 2)
  expect_equal(r$strokeWidth, 4)
  expect_equal(r$fillStyle, "cross-hatch")
  expect_error(exc_rect(0, 0, 1, 1, wobble = 3), "Unknown style")
})

test_that("labels are bound to their container", {
  els <- exc_rect(0, 0, 200, 80, label = "hi")
  expect_length(els, 2)
  box <- els[[1]]
  txt <- els[[2]]
  expect_equal(txt$containerId, box$id)
  expect_equal(box$boundElements[[1]]$id, txt$id)
  expect_equal(txt$x + txt$width / 2, 100)
  expect_equal(txt$y + txt$height / 2, 40)
})

test_that("long labels wrap to fit", {
  els <- exc_rect(0, 0, 120, 120, label = "a fairly long label that must wrap")
  txt <- els[[2]]
  expect_match(txt$text, "\n")
  expect_lte(txt$width, 120 - 10)
  expect_equal(txt$originalText, "a fairly long label that must wrap")
})

test_that("text measures with the real font", {
  t20 <- exc_text("Hello", 0, 0, font_size = 20)[[1]]
  t40 <- exc_text("Hello", 0, 0, font_size = 40)[[1]]
  expect_equal(t40$width, 2 * t20$width, tolerance = 0.01)
  expect_equal(t20$height, 20 * 1.25)
  two <- exc_text("a\nb", 0, 0)[[1]]
  expect_equal(two$height, 2 * 20 * 1.25)
  centred <- exc_text("Hello", 100, 0, hjust = 0.5)[[1]]
  expect_equal(centred$x + centred$width / 2, 100)
  expect_equal(centred$textAlign, "center")
})

test_that("custom fonts are recorded for R and fall back in Excalidraw", {
  t <- exc_text("hi", 0, 0, font = "Caveat")[[1]]
  expect_equal(t$fontFamily, 5)
  expect_equal(t$customData$excalidrawer$font, "Caveat")
  expect_equal(exc_text("hi", 0, 0, font = "Virgil")[[1]]$fontFamily, 1)
  expect_error(exc_text("hi", 0, 0, font = "Nope"), "Unknown font")
})

test_that("lines store points relative to the first point", {
  l <- exc_line(c(10, 60, 30), c(10, 10, 40), closed = TRUE)[[1]]
  expect_equal(l$x, 10)
  expect_equal(l$y, 10)
  expect_equal(l$points[[1]], c(0, 0))
  expect_equal(l$points[[length(l$points)]], c(0, 0))
  expect_equal(l$width, 50)
  expect_equal(l$height, 30)
  expect_true(l$polygon)
  a <- exc_arrow(cbind(c(0, 100), c(0, 0)), start = "dot", end = "triangle")[[1]]
  expect_equal(a$startArrowhead, "dot")
  expect_equal(a$endArrowhead, "triangle")
  expect_error(exc_arrow(c(0, 1), c(0, 1), end = "spear"), "must be NULL or one of")
})

test_that("fractional indices are valid and ordered", {
  keys <- index_keys(70)
  expect_equal(keys[1:3], c("a0", "a1", "a2"))
  expect_equal(keys[62:63], c("az", "b00"))
  expect_true(keys_in_order(as.list(keys)))
  s <- exc_scene(exc_rect(0, 0, 1, 1), exc_text("x", 0, 0))
  expect_equal(vapply(s$elements, function(e) e$index, ""), c("a0", "a1"))
})

test_that("scenes round-trip through .excalidraw files losslessly", {
  set.seed(1)
  s <- exc_scene(
    exc_rect(0, 0, 160, 80, label = "Hello", fill = "yellow", rounded = TRUE),
    exc_arrow(c(170, 300), c(40, 40), label = "next", curved = TRUE),
    exc_freedraw(c(0, 5, 10), c(0, 5, 0), pressures = c(0.5, 0.6, 0.7)),
    exc_line(c(0, 5), c(0, 5))
  )
  f <- withr::local_tempfile(fileext = ".excalidraw")
  write_excalidraw(s, f)
  s2 <- read_excalidraw(f)
  expect_identical(scene_to_json(s), scene_to_json(s2))
  json <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  expect_equal(json$type, "excalidraw")
  expect_equal(json$elements[[5]]$pressures, list(0.5, 0.6, 0.7))
  expect_equal(json$elements[[1]]$groupIds, list())
})

test_that("unknown fields from newer Excalidraw versions survive", {
  json <- '{"type":"excalidraw","version":2,"elements":[{"id":"a","type":"rectangle","x":1,"y":2,"width":3,"height":4,"index":"a0","futureField":{"nested":[1,2]}}],"appState":{"viewBackgroundColor":"#fff","someNewSetting":true},"files":{}}'
  s <- scene_from_json(json)
  out <- jsonlite::fromJSON(scene_to_json(s), simplifyVector = FALSE)
  expect_equal(out$elements[[1]]$futureField$nested, list(1, 2))
  expect_true(out$appState$someNewSetting)
})

test_that("exc_modify changes matching elements and refits text", {
  s <- exc_scene(exc_text("small", 0, 0, font_size = 16), exc_rect(0, 30, 50, 50))
  s2 <- exc_modify(s, type == "text", font_size = 32)
  t <- s2$elements[[1]]
  expect_equal(t$fontSize, 32)
  expect_equal(t$height, 32 * 1.25)
  expect_equal(t$version, 2)
  expect_equal(s2$elements[[2]]$fontSize, NULL)
  s3 <- exc_modify(s, type == "rectangle", fill = "red", fill_style = "solid")
  expect_equal(s3$elements[[2]]$backgroundColor, "#ffc9c9")
})

test_that("bbox, translate and groups behave", {
  s <- exc_scene(exc_rect(10, 10, 100, 50, stroke_width = 2))
  bb <- exc_bbox(s)
  expect_equal(unname(bb[c("xmin", "ymin", "width", "height")]), c(9, 9, 102, 52))
  moved <- exc_translate(s, dx = 5, dy = -5)
  expect_equal(moved$elements[[1]]$x, 15)
  g <- exc_group(exc_rect(0, 0, 1, 1), exc_text("a", 0, 0))
  expect_equal(g[[1]]$groupIds, g[[2]]$groupIds)
  expect_length(g[[1]]$groupIds, 1)
})

test_that("frames own their contents", {
  f <- exc_frame(0, 0, 400, 300, "Slide 1", contents = exc_text("Hi", 20, 20))
  expect_equal(f[[2]]$type, "frame")
  expect_equal(f[[1]]$frameId, f[[2]]$id)
  expect_equal(f[[2]]$name, "Slide 1")
})

test_that("images are embedded with their data", {
  png_file <- withr::local_tempfile(fileext = ".png")
  grDevices::png(png_file, width = 40, height = 20)
  grid::grid.rect(gp = grid::gpar(fill = "red"))
  grDevices::dev.off()
  im <- exc_image(png_file, 0, 0)
  expect_equal(im[[1]]$width, 40)
  expect_equal(im[[1]]$height, 20)
  files <- attr(im, "files")
  expect_match(files[[1]]$dataURL, "^data:image/png;base64,")
  s <- exc_scene(im)
  expect_length(s$files, 1)
})

test_that("libraries round-trip and items get fresh ids", {
  lib_file <- withr::local_tempfile(fileext = ".excalidrawlib")
  write_excalidraw_lib(list(box = exc_rect(0, 0, 10, 10, label = "x"),
                            dot = exc_ellipse(0, 0, 5, 5)), lib_file)
  lib <- read_excalidraw_lib(lib_file)
  expect_length(lib, 2)
  expect_equal(lib[[1]]$name, "box")
  item <- exc_library_item(lib, "box", x = 100, y = 50, width = 20)
  bb <- exc_bbox(item, stroke = FALSE)
  expect_equal(unname(bb[c("xmin", "ymin", "width")]), c(100, 50, 20))
  expect_false(item[[1]]$id == lib[[1]]$elements[[1]]$id)
  expect_equal(item[[2]]$containerId, item[[1]]$id)
})
