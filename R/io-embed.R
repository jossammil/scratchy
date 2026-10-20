# Images that carry their Excalidraw scene (.excalidraw.svg / .excalidraw.png),
# as written by Excalidraw's "Embed scene" export. The scene JSON is deflated
# and stored as a Latin-1 "byte string" inside a small JSON envelope
# ({"version":"1","encoding":"bstring","compressed":true,"encoded":...}).
# PNG keeps the envelope in a tEXt chunk; SVG keeps it base64-encoded inside
# <metadata> comments. See Excalidraw's packages/excalidraw/data/encode.ts,
# data/image.ts and scene/export.ts.

.excalidraw_mime <- "application/vnd.excalidraw+json"

# How JSON.stringify writes each char code 0-255 of a byte string.
.json_byte_escapes <- local({
  esc <- lapply(0:255, function(i) {
    if (i == 0x22) return(charToRaw("\\\""))
    if (i == 0x5c) return(charToRaw("\\\\"))
    if (i == 0x08) return(charToRaw("\\b"))
    if (i == 0x0c) return(charToRaw("\\f"))
    if (i == 0x0a) return(charToRaw("\\n"))
    if (i == 0x0d) return(charToRaw("\\r"))
    if (i == 0x09) return(charToRaw("\\t"))
    if (i < 0x20) return(charToRaw(sprintf("\\u%04x", i)))
    as.raw(i)
  })
  esc
})

# The envelope as Latin-1 bytes (what Excalidraw's JSON.stringify(encode(...))
# produces, one byte per char).
encode_scene_payload <- function(scene) {
  json <- enc2utf8(scene_to_json(scene))
  deflated <- memCompress(charToRaw(json), type = "gzip")
  c(charToRaw('{"version":"1","encoding":"bstring","compressed":true,"encoded":"'),
    unlist(.json_byte_escapes[as.integer(deflated) + 1L]),
    charToRaw('"}'))
}

# Byte b -> the UTF-8 encoding of code point b. (R's own "latin1" conversion
# follows Windows-1252 for 0x80-0x9F, which would corrupt byte strings.)
.latin1_utf8 <- lapply(0:255, function(i) {
  if (i < 128) as.raw(i) else as.raw(c(0xc0 + i %/% 64, 0x80 + i %% 64))
})

latin1_to_utf8 <- function(bytes) {
  out <- rawToChar(unlist(.latin1_utf8[as.integer(bytes) + 1L]))
  Encoding(out) <- "UTF-8"
  out
}

# Envelope bytes (one byte per char, as stored in PNG tEXt chunks and v2 SVG
# payloads) -> scene JSON string.
decode_scene_payload <- function(bytes) decode_payload_text(latin1_to_utf8(bytes))

# Envelope (or legacy plain scene JSON) as text -> scene JSON string.
decode_payload_text <- function(txt) {
  res <- v8_context()$call("ExcPayload.decode", txt)
  if (isTRUE(res$plain)) return(res$json)
  raw <- as.raw(res$bytes)
  if (isTRUE(res$compressed)) raw <- memDecompress(raw, type = "gzip")
  out <- rawToChar(raw)
  Encoding(out) <- "UTF-8"
  out
}

# ---- SVG ------------------------------------------------------------------------

embed_scene_svg <- function(svg_file, scene) {
  svg <- paste(readLines(svg_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  b64 <- gsub("\n", "", jsonlite::base64_enc(encode_scene_payload(scene)))
  meta <- paste0(
    "<!-- svg-source:excalidraw --><metadata>",
    "<!-- payload-type:", .excalidraw_mime, " -->",
    "<!-- payload-version:2 --><!-- payload-start -->", b64, "<!-- payload-end -->",
    "</metadata>"
  )
  open_tag <- regexpr("<svg[^>]*>", svg)
  if (open_tag < 0) cli::cli_abort("Couldn't find the <svg> element to embed the scene in.")
  end <- open_tag + attr(open_tag, "match.length") - 1
  svg <- paste0(substr(svg, 1, end), meta, substr(svg, end + 1, nchar(svg)), "\n")
  con <- file(svg_file, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(svg)), con)
  invisible(svg_file)
}

read_scene_svg <- function(path) {
  svg <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (!grepl(paste0("payload-type:", .excalidraw_mime), svg, fixed = TRUE)) {
    cli::cli_abort(c("{.file {path}} has no embedded Excalidraw scene.",
                     i = "Export from Excalidraw with \"Embed scene\" turned on, or save with {.fn write_excalidraw}."))
  }
  m <- regmatches(svg, regexec("<!-- payload-start -->\\s*(.+?)\\s*<!-- payload-end -->", svg))[[1]]
  version <- regmatches(svg, regexec("<!-- payload-version:(\\d+) -->", svg))[[1]]
  bytes <- jsonlite::base64_dec(m[2])
  if (length(version) < 2 || version[2] == "1") {
    # version 1 base64-encoded UTF-8 text rather than a byte string
    txt <- rawToChar(bytes)
    Encoding(txt) <- "UTF-8"
    return(scene_from_json(decode_payload_text(txt)))
  }
  scene_from_json(decode_scene_payload(bytes))
}

# ---- PNG ------------------------------------------------------------------------

be32 <- function(x) {
  as.raw(c(x %/% 2^24 %% 256, x %/% 2^16 %% 256, x %/% 2^8 %% 256, x %% 256))
}

read_be32 <- function(b) sum(as.integer(b) * 256^(3:0))

png_crc32 <- function(bytes) v8_context()$call("ExcPayload.crc32", as.integer(bytes))

png_chunks <- function(png) {
  if (!identical(png[1:8], as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)))) {
    cli::cli_abort("Not a PNG file.")
  }
  pos <- 9
  out <- list()
  while (pos + 7 <= length(png)) {
    len <- read_be32(png[pos:(pos + 3)])
    type <- rawToChar(png[(pos + 4):(pos + 7)])
    data <- if (len > 0) png[(pos + 8):(pos + 7 + len)] else raw()
    out[[length(out) + 1]] <- list(type = type, start = pos, data = data)
    pos <- pos + 12 + len
    if (type == "IEND") break
  }
  out
}

embed_scene_png <- function(png_file, scene) {
  png <- readBin(png_file, "raw", file.info(png_file)$size)
  chunks <- png_chunks(png)
  # Excalidraw reads the first tEXt chunk, so ours goes right after IHDR and
  # any other tEXt chunks are dropped.
  data <- c(charToRaw(.excalidraw_mime), as.raw(0), encode_scene_payload(scene))
  type <- charToRaw("tEXt")
  chunk <- c(be32(length(data)), type, data, be32(png_crc32(c(type, data))))
  kept <- Filter(function(ch) ch$type != "tEXt", chunks)
  pieces <- lapply(kept, function(ch) png[ch$start:(ch$start + 11 + length(ch$data))])
  out <- c(png[1:8], pieces[[1]], chunk, unlist(pieces[-1]))
  writeBin(out, png_file)
  invisible(png_file)
}

read_scene_png <- function(path) {
  png <- readBin(path, "raw", file.info(path)$size)
  for (ch in png_chunks(png)) {
    if (ch$type != "tEXt") next
    nul <- match(as.raw(0), ch$data)
    if (is.na(nul)) next
    if (rawToChar(ch$data[seq_len(nul - 1)]) != .excalidraw_mime) next
    return(scene_from_json(decode_scene_payload(ch$data[(nul + 1):length(ch$data)])))
  }
  cli::cli_abort(c("{.file {path}} has no embedded Excalidraw scene.",
                   i = "Export from Excalidraw with \"Embed scene\" turned on, or save with {.fn write_excalidraw}."))
}
