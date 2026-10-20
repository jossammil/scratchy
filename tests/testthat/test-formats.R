fmt_scene <- function() {
  withr::local_seed(11)
  exc_scene(
    exc_rect(0, 0, 160, 80, label = "Hello", fill = "yellow"),
    exc_arrow(c(170, 300), c(40, 40), label = "next"),
    exc_text("café — über \U0001f3a8", 0, 120)
  )
}

test_that("Obsidian files round-trip, compressed or not", {
  s <- fmt_scene()
  for (compress in c(TRUE, FALSE)) {
    f <- withr::local_tempfile(fileext = ".excalidraw.md")
    write_excalidraw(s, f, compress = compress)
    md <- readLines(f, encoding = "UTF-8")
    expect_true("excalidraw-plugin: parsed" %in% md)
    expect_true("# Excalidraw Data" %in% md)
    expect_true("## Text Elements" %in% md)
    expect_true(any(md == if (compress) "```compressed-json" else "```json"))
    label <- Filter(function(e) e$type == "text", s$elements)[[1]]
    expect_true(paste0("Hello ^", label$id) %in% md)
    expect_identical(scene_to_json(read_excalidraw(f)), scene_to_json(s))
  }
})

test_that("compressed Obsidian drawings are split into 256-character lines", {
  s <- fmt_scene()
  f <- withr::local_tempfile(fileext = ".excalidraw.md")
  write_excalidraw(s, f)
  md <- readLines(f)
  start <- which(md == "```compressed-json") + 1
  end <- which(md == "```")[which(md == "```") > start][1] - 1
  chunk_lines <- md[start:end]
  chunk_lines <- chunk_lines[nzchar(chunk_lines)]
  expect_true(all(nchar(chunk_lines) <= 256))
  expect_true(all(nchar(head(chunk_lines, -1)) == 256))
})

test_that("Obsidian images are saved next to the drawing and read back", {
  png_file <- withr::local_tempfile(fileext = ".png")
  grDevices::png(png_file, width = 20, height = 10)
  grid::grid.rect(gp = grid::gpar(fill = "blue"))
  grDevices::dev.off()
  s <- exc_scene(exc_image(png_file, 0, 0))
  dir <- withr::local_tempdir()
  f <- file.path(dir, "pic.excalidraw.md")
  write_excalidraw(s, f)
  id <- names(s$files)[1]
  expect_true(file.exists(file.path(dir, "pic-files", paste0(id, ".png"))))
  md <- readLines(f)
  expect_true(paste0(id, ": [[pic-files/", id, ".png]]") %in% md)
  back <- read_excalidraw(f)
  expect_match(back$files[[id]]$dataURL, "^data:image/png;base64,")
})

test_that("embedded-scene SVG and PNG files round-trip", {
  skip_if_not_installed("ragg")
  s <- fmt_scene()
  for (ext in c(".excalidraw.svg", ".excalidraw.png")) {
    f <- withr::local_tempfile(fileext = ext)
    write_excalidraw(s, f)
    expect_identical(scene_to_json(read_excalidraw(f)), scene_to_json(s))
  }
  svg_file <- withr::local_tempfile(fileext = ".svg")
  write_excalidraw(s, svg_file)
  svg <- paste(readLines(svg_file), collapse = "")
  expect_match(svg, "<!-- payload-type:application/vnd.excalidraw+json -->", fixed = TRUE)
  expect_match(svg, "<!-- payload-version:2 -->", fixed = TRUE)
})

test_that("plain PNG/SVG saves don't embed the scene unless asked", {
  skip_if_not_installed("ragg")
  s <- fmt_scene()
  f <- withr::local_tempfile(fileext = ".png")
  exc_save(s, f)
  expect_error(read_excalidraw(f), "no embedded Excalidraw scene")
  exc_save(s, f, embed_scene = TRUE)
  expect_s3_class(read_excalidraw(f), "exc_scene")
})

test_that("byte strings survive every byte value (0x80-0x9F included)", {
  withr::local_seed(5)
  # random text compresses poorly, so the deflated bytes cover the full range
  noise <- paste(sample(c(letters, LETTERS, 0:9), 3000, replace = TRUE), collapse = "")
  s <- exc_scene(exc_text(noise, 0, 0))
  payload <- encode_scene_payload(s)
  deflated <- memCompress(charToRaw(enc2utf8(scene_to_json(s))), type = "gzip")
  expect_true(any(as.integer(deflated) >= 0x80 & as.integer(deflated) <= 0x9f))
  expect_false(any(payload == as.raw(0)))
  expect_identical(decode_scene_payload(payload), scene_to_json(s))
})

test_that("legacy plain-JSON payloads are accepted", {
  s <- exc_scene(exc_text("caf\u00e9", 0, 0))
  json <- scene_to_json(s)
  # old PNG payloads: Latin-1 text, one byte per character
  expect_identical(decode_scene_payload(as.raw(utf8ToInt(json))), json)
  # old (version 1) SVG payloads: base64 of UTF-8 text, any characters
  s2 <- fmt_scene()
  f <- withr::local_tempfile(fileext = ".svg")
  b64 <- gsub("\n", "", jsonlite::base64_enc(charToRaw(enc2utf8(scene_to_json(s2)))))
  writeLines(paste0("<svg xmlns='http://www.w3.org/2000/svg'><metadata>",
                    "<!-- payload-type:application/vnd.excalidraw+json --><!-- payload-version:1 -->",
                    "<!-- payload-start -->", b64, "<!-- payload-end --></metadata></svg>"), f)
  expect_identical(scene_to_json(read_excalidraw(f)), scene_to_json(s2))
})

test_that("PNG chunks carry valid CRCs", {
  skip_if_not_installed("ragg")
  f <- withr::local_tempfile(fileext = ".excalidraw.png")
  write_excalidraw(fmt_scene(), f)
  png <- readBin(f, "raw", file.info(f)$size)
  for (ch in png_chunks(png)) {
    stored <- read_be32(png[(ch$start + 8 + length(ch$data)):(ch$start + 11 + length(ch$data))])
    expect_equal(stored, png_crc32(c(charToRaw(ch$type), ch$data)))
  }
  img <- png::readPNG(f)
  expect_gt(dim(img)[1], 10)
})

test_that("emoji and CJK text render without errors", {
  skip_if_not_installed("ragg")
  s <- exc_scene(exc_text("中文 \U0001f3a8 café", 0, 0, font_size = 28))
  f <- withr::local_tempfile(fileext = ".png")
  expect_no_error(exc_save(s, f, text = "outline"))
  expect_no_error(exc_save(s, f, text = "font"))
})
