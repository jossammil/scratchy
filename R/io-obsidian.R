# Obsidian Excalidraw plugin files (.excalidraw.md), following the layout of
# zsviczian/obsidian-excalidraw-plugin: front matter, a "## Text Elements"
# section (text followed by ^elementId), optional "## Embedded Files", and
# the scene JSON in a %%-hidden "## Drawing" block (json or compressed-json).

.obsidian_frontmatter <- paste(
  "---",
  "",
  "excalidraw-plugin: parsed",
  "tags: [excalidraw]",
  "",
  "---",
  paste0("==\u26a0  Switch to EXCALIDRAW VIEW in the MORE OPTIONS menu of this document. \u26a0== ",
         "You can decompress Drawing data with the command palette: 'Decompress current Excalidraw file'. ",
         "For more info check in plugin settings under 'Saving'"),
  "",
  "",
  sep = "\n"
)

write_obsidian <- function(scene, path, compress = TRUE) {
  texts <- Filter(function(e) e$type == "text" && !isTRUE(e$isDeleted), scene$elements)
  text_section <- vapply(texts, function(e) {
    paste0(e$originalText %||% e$text %||% "", " ^", e$id, "\n\n")
  }, "")

  files <- scene$files
  embedded <- character()
  if (length(files)) {
    dir_name <- paste0(sub("\\.excalidraw\\.md$", "", basename(path)), "-files")
    dir.create(file.path(dirname(path), dir_name), showWarnings = FALSE)
    for (id in names(files)) {
      f <- files[[id]]
      ext <- switch(f$mimeType %||% "", "image/png" = "png", "image/jpeg" = "jpg",
                    "image/svg+xml" = "svg", "image/gif" = "gif", "image/webp" = "webp", "png")
      rel <- file.path(dir_name, paste0(id, ".", ext))
      bytes <- jsonlite::base64_dec(sub("^data:[^,]*,", "", f$dataURL))
      writeBin(bytes, file.path(dirname(path), rel))
      embedded <- c(embedded, paste0(id, ": [[", rel, "]]\n\n"))
    }
  }

  json <- scene_to_json(scene, pretty = TRUE)
  drawing <- if (compress) {
    lz <- v8_context()$call("LZString.compressToBase64", json)
    chunks <- substring(lz, seq(1, nchar(lz), 256), pmin(seq(256, nchar(lz) + 255, 256), nchar(lz)))
    paste0("## Drawing\n```compressed-json\n", paste(chunks, collapse = "\n\n"), "\n```\n%%")
  } else {
    paste0("## Drawing\n```json\n", json, "\n```\n%%")
  }
  out <- paste0(
    .obsidian_frontmatter,
    "# Excalidraw Data\n\n## Text Elements\n",
    paste(text_section, collapse = ""),
    if (length(embedded)) paste0("## Embedded Files\n", paste(embedded, collapse = "")) else "",
    "%%\n",
    drawing,
    "\n"
  )
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(out)), con)
  invisible(path)
}

read_obsidian <- function(path) {
  md <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  json <- NULL
  m <- regmatches(md, regexec("\n##? Drawing\n[^`]*```compressed-json\n([\\s\\S]*?)```", md, perl = TRUE))[[1]]
  if (length(m) == 2) {
    packed <- gsub("[\r\n]", "", m[2])
    json <- v8_context()$call("LZString.decompressFromBase64", packed)
  } else {
    m <- regmatches(md, regexec("\n##? Drawing\n[^`]*```json\n([\\s\\S]*?)```", md, perl = TRUE))[[1]]
    if (length(m) == 2) json <- m[2]
  }
  if (is.null(json) || !nzchar(json)) {
    cli::cli_abort("{.file {path}} has no Excalidraw drawing section.")
  }
  scene <- scene_from_json(json)
  # Images live in the vault; load the ones we can find next to the file.
  emb <- regmatches(md, regexec("## Embedded Files\n([\\s\\S]*?)(\n%%|\n## )", md, perl = TRUE))[[1]]
  if (length(emb) == 3) {
    lines <- strsplit(emb[2], "\n", fixed = TRUE)[[1]]
    for (ln in lines[grepl("^[^:]+: \\[\\[", lines)]) {
      id <- sub(":.*$", "", ln)
      target <- sub("^[^:]+: \\[\\[([^]|#]+).*$", "\\1", ln)
      file <- find_vault_file(target, dirname(path))
      if (!is.null(file) && is.null(scene$files[[id]]$dataURL)) {
        scene$files[[id]] <- file_entry(file, id)
      }
    }
  }
  scene
}

find_vault_file <- function(target, start) {
  dir <- normalizePath(start)
  for (i in 1:6) {
    cand <- file.path(dir, target)
    if (file.exists(cand)) return(cand)
    if (dir.exists(file.path(dir, ".obsidian"))) break
    parent <- dirname(dir)
    if (parent == dir) break
    dir <- parent
  }
  NULL
}

file_entry <- function(file, id) {
  ext <- tolower(tools::file_ext(file))
  mime <- switch(ext, png = "image/png", jpg = , jpeg = "image/jpeg", gif = "image/gif",
                 svg = "image/svg+xml", webp = "image/webp", "application/octet-stream")
  bytes <- readBin(file, "raw", file.info(file)$size)
  list(mimeType = mime, id = id,
       dataURL = paste0("data:", mime, ";base64,", jsonlite::base64_enc(bytes)),
       created = timestamp_ms(), lastRetrieved = timestamp_ms())
}
