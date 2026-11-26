# Writes inst/quarto/_extensions/excalidraw/fonts.css with the slide fonts
# embedded as base64 WOFF2, so decks work offline and self-contained.
# Nunito and Cascadia Code are converted from the bundled TTFs with fontTools
# (see data-raw/fonts.py); pass the folder holding those WOFF2 files.
#   Rscript data-raw/quarto-fonts.R /path/to/woff2-folder
args <- commandArgs(trailingOnly = TRUE)
woff2_dir <- args[1]
face <- function(family, path, weight = "normal") {
  b64 <- gsub("\n", "", jsonlite::base64_enc(readBin(path, "raw", file.info(path)$size)))
  sprintf('@font-face {\n  font-family: "%s";\n  font-weight: %s;\n  font-display: block;\n  src: url(data:font/woff2;base64,%s) format("woff2");\n}\n',
          family, weight, b64)
}
css <- c(
  "/* Fonts for the excalidraw Quarto format (OFL-1.1; see the scratchy package). */\n",
  face("Excalifont", "inst/fonts/Excalifont-Regular.woff2"),
  face("Virgil", "inst/fonts/Virgil.woff2"),
  face("Nunito", file.path(woff2_dir, "Nunito-Regular.woff2")),
  face("Nunito", file.path(woff2_dir, "Nunito-Bold.woff2"), "bold"),
  face("Cascadia Code", file.path(woff2_dir, "CascadiaCode-Regular.woff2"))
)
writeLines(css, "inst/quarto/_extensions/excalidraw/fonts.css", sep = "")
message("wrote fonts.css (", round(sum(nchar(css)) / 1024), " KB)")
