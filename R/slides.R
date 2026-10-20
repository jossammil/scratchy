#' Hand-drawn Quarto slides
#'
#' Sets up a Quarto presentation that uses the `excalidraw-revealjs` format:
#' Excalifont headings, Excalidraw colours, sketchy code blocks and
#' callouts, and figures sized for slides. In the slides you can use:
#' * `[text]{.rn-underline}`, `.rn-circle`, `.rn-box`, `.rn-highlight`,
#'   `.rn-strike`, `.rn-cross` and `.rn-bracket` for hand-drawn marks
#'   (add `.fragment` to reveal them on click);
#' * `[text]{.sticky-note}` (also `.blue`, `.pink`, `.green`);
#' * `::: {.sketch-box}` for a box with a rough border (`data-fill` adds a
#'   hachure fill);
#' * `excalidraw: paper:` in the YAML (`dots`, `graph`, `lines`, `kraft`,
#'   `blueprint`, `chalkboard`);
#' * [sketch()] and `plot()` of scenes in R chunks.
#'
#' @param path Folder for the presentation. Created if needed.
#' @param file Name of the slides file.
#' @param overwrite Replace existing files.
#' @return The path of the slides file, invisibly.
#' @export
#' @examples
#' \dontrun{
#' use_excalidraw_slides("talk")
#' # then: quarto render talk/slides.qmd
#' }
use_excalidraw_slides <- function(path = "slides", file = "slides.qmd", overwrite = FALSE) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  src <- pkg_file("quarto", "_extensions", "excalidraw")
  dst <- file.path(path, "_extensions", "excalidraw")
  if (dir.exists(dst) && !overwrite) {
    cli::cli_inform("{.file {dst}} already exists; keeping it.")
  } else {
    dir.create(dst, recursive = TRUE, showWarnings = FALSE)
    file.copy(list.files(src, full.names = TRUE), dst, overwrite = TRUE, recursive = TRUE)
  }
  out <- file.path(path, file)
  if (file.exists(out) && !overwrite) {
    cli::cli_inform("{.file {out}} already exists; keeping it.")
  } else {
    file.copy(pkg_file("quarto", "template.qmd"), out, overwrite = TRUE)
    cli::cli_inform(c(v = "Created {.file {out}}.", i = "Render it with {.code quarto render {out}}."))
  }
  invisible(out)
}

#' Print rendered slides to PDF
#'
#' Prints a rendered reveal.js presentation (HTML) to PDF with headless
#' Chrome, one slide per page. Needs the chromote package.
#'
#' @param html The rendered slides (`.html`).
#' @param output PDF path.
#' @param wait Seconds to let the slides (and their hand-drawn marks)
#'   finish drawing before printing.
#' @return `output`, invisibly.
#' @export
exc_slides_pdf <- function(html, output = sub("\\.html?$", ".pdf", html), wait = 3) {
  rlang::check_installed("chromote")
  b <- chromote::ChromoteSession$new()
  on.exit(b$close(), add = TRUE)
  b$Page$navigate(paste0("file://", normalizePath(html), "?print-pdf"))
  Sys.sleep(wait)
  pdf <- b$Page$printToPDF(printBackground = TRUE, preferCSSPageSize = TRUE)
  writeBin(jsonlite::base64_dec(pdf$data), output)
  invisible(output)
}
