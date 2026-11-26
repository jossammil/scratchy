skip_if_not_installed("xml2")

anim_scene <- function() {
  withr::local_seed(42)
  exc_scene(
    exc_rect(0, 0, 160, 80, label = "Hello", fill = "yellow", fill_style = "hachure"),
    exc_arrow(c(170, 300), c(40, 40)),
    exc_text("Title", 0, 120, font_size = 28),
    exc_freedraw(300 + cos(seq(0, 6, 0.2)) * 30, 180 + sin(seq(0, 6, 0.2)) * 30)
  )
}

# Keyframes as a data frame: name, property, start and end (% of the cycle).
svg_keyframes <- function(doc) {
  css <- xml2::xml_text(xml2::xml_find_first(doc, "//*[local-name()='style']"))
  kf <- regmatches(css, gregexpr("@keyframes [^{]+\\{.*?\\}\\}", css, perl = TRUE))[[1]]
  kf <- kf[!grepl("-out\\{", kf)]
  data.frame(
    name = sub("@keyframes ([^{]+)\\{.*", "\\1", kf),
    prop = sub("^[^{]+\\{[^{]+\\{([a-z-]+):.*", "\\1", kf),
    start = as.numeric(sub("^[^{]+\\{(0%,)?([0-9.]+)%\\{.*", "\\2", kf)),
    end = as.numeric(sub(".*\\}([0-9.]+)%\\{[^{]*\\}\\}$", "\\1", kf)),
    hidden = as.numeric(sub("^[^{]+\\{[^{]+\\{[a-z-]+:([0-9.]+)\\}.*", "\\1", kf))
  )
}

anim_names <- function(nodes) sub("animation-name:", "", xml2::xml_attr(nodes, "style"))

# Length of a path written as "M x y l dx dy ...".
d_length <- function(d) {
  v <- as.numeric(regmatches(d, gregexpr("-?[0-9.]+", d))[[1]])
  steps <- matrix(v[-(1:2)], ncol = 2, byrow = TRUE)
  sum(sqrt(rowSums(steps^2)))
}

test_that("exc_animate writes an SVG whose strokes draw themselves in z-order", {
  s <- anim_scene()
  f <- withr::local_tempfile(fileext = ".svg")
  expect_identical(exc_animate(s, f, duration = 4), f)
  doc <- xml2::read_xml(f)
  root <- xml2::xml_root(doc)
  cv <- exc_grob(s)$canvas
  expect_equal(as.numeric(xml2::xml_attr(root, "width")), round(cv[["w"]]))
  expect_equal(as.numeric(xml2::xml_attr(root, "height")), round(cv[["h"]]))

  kf <- svg_keyframes(doc)
  styled <- xml2::xml_find_all(doc, "//*[@style]")
  expect_setequal(anim_names(styled), kf$name)
  expect_true(all(kf$start >= 0 & kf$end <= 100 & kf$start < kf$end))

  # Every traced path starts hidden in the dash gap and ends fully covered.
  dashed <- xml2::xml_find_all(doc, "//*[@stroke-dasharray]")
  expect_gt(length(dashed), 10)
  dash <- do.call(rbind, lapply(strsplit(xml2::xml_attr(dashed, "stroke-dasharray"), " "), as.numeric))
  lens <- vapply(xml2::xml_attr(dashed, "d"), d_length, 1)
  expect_true(all(dash[, 1] >= lens))
  hidden <- kf$hidden[match(anim_names(dashed), kf$name)]
  expect_true(all(hidden >= dash[, 1] + 0.5 & hidden + lens <= dash[, 1] + dash[, 2]))

  # ...and they are traced one after another, in z-order.
  timing <- kf[match(anim_names(dashed), kf$name), ]
  expect_false(is.unsorted(timing$start))
  expect_false(is.unsorted(timing$end))
})

test_that("fills fade in after their outline and text is written letter by letter", {
  s <- anim_scene()
  f <- withr::local_tempfile(fileext = ".svg")
  exc_animate(s, f, duration = 4)
  doc <- xml2::read_xml(f)
  kf <- svg_keyframes(doc)
  timing <- function(nodes) kf[match(anim_names(nodes), kf$name), ]
  rect <- s$elements[[1]]
  hachure <- xml2::xml_find_all(doc, sprintf("//*[@stroke='%s']/*", rect$backgroundColor))
  outline <- xml2::xml_find_first(doc, sprintf("//*[@stroke='%s']", rect$strokeColor))
  expect_length(hachure, 1)
  expect_equal(timing(hachure)$prop, "stroke-opacity")
  expect_gte(min(timing(hachure)$start), max(timing(xml2::xml_children(outline))$end))

  glyphs <- xml2::xml_find_all(doc, "//*[contains(@class, '-t')]")
  expect_length(glyphs, 2)
  title <- timing(xml2::xml_children(glyphs[[2]]))
  expect_equal(nrow(title), nchar("Title"))
  expect_true(all(title$prop == "fill-opacity"))
  expect_false(is.unsorted(title$start, strictly = TRUE))

  # The freehand stroke is uncovered by a traced mask.
  mask <- xml2::xml_find_all(doc, "//*[local-name()='mask']")
  expect_length(mask, 1)
  expect_length(xml2::xml_find_all(doc, "//*[@mask]"), 1)

  faded <- withr::local_tempfile(fileext = ".svg")
  exc_animate(s, faded, duration = 4, text = "fade")
  doc <- xml2::read_xml(faded)
  expect_length(xml2::xml_find_all(doc, "//*[contains(@class, '-t')]"), 0)
  expect_true("opacity" %in% svg_keyframes(doc)$prop)
})

test_that("looping animations hold the drawing, then fade it out and restart", {
  f <- withr::local_tempfile(fileext = ".svg")
  exc_animate(anim_scene(), f, duration = 3, loop = TRUE, hold = 1)
  svg <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(svg, "animation:4s linear infinite both", fixed = TRUE)
  expect_match(svg, "prefers-reduced-motion", fixed = TRUE)
  expect_match(svg, "-out\\{0%,87.5%\\{opacity:1\\}100%\\{opacity:0\\}\\}")
  kf <- svg_keyframes(xml2::read_xml(f))
  expect_lte(max(kf$end), 75 + 0.01)

  once <- withr::local_tempfile(fileext = ".svg")
  exc_animate(anim_scene(), once, duration = 3)
  expect_match(paste(readLines(once, warn = FALSE), collapse = "\n"), "animation:3s linear 1 both",
               fixed = TRUE)
})

test_that("every outline subpath is animated on its own", {
  withr::local_seed(1)
  el <- exc_rect(0, 0, 100, 60, seed = 3)
  parts <- rough_parts(unclass(el))[[1]]
  outline <- Filter(function(p) p$role == "outline", parts)
  f <- withr::local_tempfile(fileext = ".svg")
  exc_animate(exc_scene(el), f)
  doc <- xml2::read_xml(f)
  n_paths <- sum(vapply(outline, function(p) length(p$paths), 1L))
  expect_length(xml2::xml_find_all(doc, "//*[@stroke-dasharray]"), n_paths)
})

test_that("frames clip their contents, images and paper are kept", {
  withr::local_seed(2)
  img <- withr::local_tempfile(fileext = ".png")
  png::writePNG(array(0.5, c(10, 20, 3)), img)
  s <- exc_scene(
    exc_frame(0, 0, 200, 120, "Frame", contents = exc_ellipse(150, 80, 120, 80, fill = "red")),
    exc_image(img, 220, 0, width = 40)
  )
  f <- withr::local_tempfile(fileext = ".svg")
  exc_animate(s, f, paper = "graph", background = FALSE)
  doc <- xml2::read_xml(f)
  clip <- xml2::xml_find_all(doc, "//*[local-name()='clipPath']")
  expect_length(clip, 1)
  clipped <- xml2::xml_find_all(doc, "//*[@clip-path]")
  expect_length(clipped, 1)
  expect_equal(xml2::xml_attr(clipped, "clip-path"), sprintf("url(#%s)", xml2::xml_attr(clip, "id")))
  image <- xml2::xml_find_all(doc, "//*[local-name()='image']")
  expect_length(image, 1)
  expect_match(xml2::xml_attr(image, "href"), "^data:image/png;base64,")
  expect_match(paste(readLines(f, warn = FALSE), collapse = ""), "stroke=\"#a5d8ff\"", fixed = TRUE)
  expect_length(xml2::xml_find_all(doc, "/*/*[local-name()='rect']"), 0)
})

test_that("animation helpers keep keyframes apart and paths short", {
  expect_equal(anim_keyframes("k", 0.5, 0.5, "fill-opacity"),
               "@keyframes k{0%,50%{fill-opacity:0}50.01%{fill-opacity:1}}")
  expect_equal(anim_keyframes("k", 0, 0.25, "stroke-dashoffset", 12.5),
               "@keyframes k{0%{stroke-dashoffset:12.5}25%{stroke-dashoffset:0}}")
  expect_equal(anim_keyframes("k", 1, 1, "opacity"), "@keyframes k{0%,99.99%{opacity:0}100%{opacity:1}}")
  line <- c(rbind(seq(0, 100, length.out = 50), 2))
  expect_equal(tidy_xy(line), c(0, 2, 100, 2))
  a <- seq(0, 2 * pi, length.out = 200)
  circle <- tidy_xy(c(rbind(50 * cos(a), 50 * sin(a))))
  expect_lt(length(circle) / 2, 100)
  expect_equal(polyline_length(circle), 2 * pi * 50, tolerance = 0.01)
  expect_equal(svg_path_d(list(c(1, 2, 3.5, 2, 3.5, 0.25))), "M1 2l2.5 0 0-1.75")
  expect_equal(fmt_num(c(1.5, 2, -0.001, 1234.567)), c("1.5", "2", "0", "1234.57"))
})

test_that("exc_animate checks its inputs", {
  s <- anim_scene()
  expect_error(exc_animate(s, tempfile(fileext = ".mp4")), "svg or gif")
  expect_error(exc_animate(s, tempfile(fileext = ".svg"), duration = 0), "duration")
  expect_error(exc_animate(s, tempfile(fileext = ".svg"), hold = -1), "hold")
  expect_error(exc_animate(s, tempfile(fileext = ".gif"), fps = 60), "at most 50")
  expect_error(exc_animate(list(), tempfile(fileext = ".svg")), "exc_scene")
})

test_that("GIFs are recorded frame by frame in headless Chrome", {
  skip_on_cran()
  skip_if_not_installed("chromote")
  skip_if(is.null(tryCatch(chromote::find_chrome(), error = function(e) NULL)), "no Chrome")
  skip_if_not(requireNamespace("gifski", quietly = TRUE) || requireNamespace("magick", quietly = TRUE),
              "neither gifski nor magick is installed")
  s <- anim_scene()

  # The animation really progresses: blank first frame, finished last frame.
  g <- exc_grob(s, text = "outline")
  anim <- animation_svg(g, s, duration = 2, loop = FALSE, hold = 0, text = "write", scale = 1)
  svg <- withr::local_tempfile(fileext = ".svg")
  write_utf8(anim$svg, svg)
  dir <- withr::local_tempdir()
  frames <- capture_frames(svg, c(0, 1, 2), anim$width, anim$height, 1, FALSE, dir, rep(NA, 3))
  ink <- vapply(frames, function(f) sum(png::readPNG(f)[, , 1] < 0.5), 1)
  expect_equal(ink[[1]], 0)
  expect_gt(ink[[2]], 0)
  expect_gt(ink[[3]], ink[[2]])
  static <- withr::local_tempfile(fileext = ".png")
  exc_save(s, static, text = "outline")
  last <- png::readPNG(frames[3])[, , 1:3]
  expect_equal(dim(last), dim(png::readPNG(static)[, , 1:3]))
  expect_lt(mean(abs(last - png::readPNG(static)[, , 1:3])), 0.01)

  gif <- withr::local_tempfile(fileext = ".gif")
  exc_animate(s, gif, duration = 1, fps = 10, scale = 0.5)
  expect_identical(readBin(gif, "raw", 6), charToRaw("GIF89a"))
  skip_if_not_installed("magick")
  img <- magick::image_read(gif)
  expect_gt(length(img), 5)
  expect_equal(magick::image_info(img)$width[1], round(anim$width * 0.5))

  local_mocked_bindings(gif_encoder = function() "magick")
  looped <- withr::local_tempfile(fileext = ".gif")
  exc_animate(s, looped, duration = 1, loop = TRUE, hold = 0.5, fps = 10, scale = 0.5)
  expect_equal(length(magick::image_read(looped)), 15)
})
