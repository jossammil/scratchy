test_that("use_excalidraw_slides() sets up the extension and a deck", {
  dir <- withr::local_tempdir()
  out <- suppressMessages(use_excalidraw_slides(dir))
  expect_true(file.exists(out))
  ext <- file.path(dir, "_extensions", "excalidraw")
  expect_true(file.exists(file.path(ext, "_extension.yml")))
  expect_true(file.exists(file.path(ext, "sketchy", "plugin.yml")))
  expect_true(file.exists(file.path(ext, "sketchy", "rough.js")))
  expect_true(file.exists(file.path(ext, "fonts.css")))
  expect_match(paste(readLines(out), collapse = "\n"), "excalidraw-revealjs", fixed = TRUE)
  expect_message(use_excalidraw_slides(dir), "already exists")
})

test_that("the Quarto deck renders", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("quarto")), "quarto not installed")
  skip_if_not(requireNamespace("scratchy", quietly = TRUE) &&
                identical(find.package("scratchy"), normalizePath(system.file(package = "scratchy"))),
              "package not installed")
  dir <- withr::local_tempdir()
  qmd <- file.path(dir, "deck.qmd")
  suppressMessages(use_excalidraw_slides(dir, "deck.qmd"))
  writeLines(c("---", "title: Test", "format: excalidraw-revealjs", "---", "", "## Hi",
               "", "[word]{.rn-circle}"), qmd)
  res <- system2("quarto", c("render", shQuote(qmd), "--quiet"), stdout = TRUE, stderr = TRUE)
  expect_true(file.exists(file.path(dir, "deck.html")))
})

test_that("exc_pptx writes one slide per drawing and per frame", {
  skip_if_not_installed("officer")
  skip_if_not_installed("rvg")
  deck <- exc_scene(
    exc_frame(0, 0, 400, 300, "First", contents = exc_text("one", 20, 20)),
    exc_frame(500, 0, 400, 300, "Second", contents = exc_rect(520, 20, 100, 60, label = "two"))
  )
  f <- withr::local_tempfile(fileext = ".pptx")
  exc_pptx(list(exc_scene(exc_ellipse(0, 0, 100, 60)), deck), f, titles = c("An ellipse", NA, NA))
  doc <- officer::read_pptx(f)
  expect_equal(length(doc), 3)
  s <- officer::pptx_summary(doc)
  titles <- s$text[!is.na(s$text) & nzchar(s$text)]
  expect_true(all(c("An ellipse", "First", "Second") %in% titles))
  expect_false("NA" %in% titles)
  f2 <- withr::local_tempfile(fileext = ".pptx")
  exc_pptx(exc_scene(exc_rect(0, 0, 100, 50)), f2, vector = FALSE)
  s2 <- officer::pptx_summary(officer::read_pptx(f2))
  expect_true("image" %in% s2$content_type)
})

test_that("fonts install into a chosen folder", {
  dir <- withr::local_tempdir()
  paths <- suppressMessages(exc_install_fonts(dir))
  expect_true(all(file.exists(paths)))
  expect_true("Excalifont-Regular.ttf" %in% basename(paths))
})
