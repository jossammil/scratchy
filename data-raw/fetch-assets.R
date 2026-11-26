# Fetch the third-party assets bundled in inst/: fonts (with licences) and the
# small JavaScript libraries used by the native renderer.
#
# Run from the package root:  Rscript data-raw/fetch-assets.R
# Font conversion (WOFF2 -> TTF, variable -> static) needs Python + fontTools + brotli.

fonts_dir <- "inst/fonts"
lic_dir <- file.path(fonts_dir, "LICENSES")
js_dir <- "inst/js"
dir.create(lic_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(js_dir, recursive = TRUE, showWarnings = FALSE)

fetch <- function(url, dest) {
  message("fetching ", basename(dest))
  utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  invisible(dest)
}

gf <- "https://raw.githubusercontent.com/google/fonts/main/ofl"

# ---- fonts ------------------------------------------------------------------
fetch("https://excalidraw.nyc3.cdn.digitaloceanspaces.com/fonts/Excalifont-Regular.woff2",
      file.path(fonts_dir, "Excalifont-Regular.woff2"))
fetch("https://raw.githubusercontent.com/excalidraw/virgil/main/Virgil.woff2",
      file.path(fonts_dir, "Virgil.woff2"))
fetch("https://raw.githubusercontent.com/excalidraw/virgil/main/LICENSE.md",
      file.path(lic_dir, "Virgil-OFL.md"))
fetch("https://raw.githubusercontent.com/shannpersand/comic-shanns/master/v2/comic%20shanns%202.ttf",
      file.path(fonts_dir, "ComicShanns-Regular.ttf"))
fetch("https://raw.githubusercontent.com/shannpersand/comic-shanns/master/LICENSE",
      file.path(lic_dir, "ComicShanns-MIT.txt"))

google <- list(
  c("caveat", "Caveat%5Bwght%5D.ttf", "Caveat-VF.ttf"),
  c("patrickhand", "PatrickHand-Regular.ttf", "PatrickHand-Regular.ttf"),
  c("architectsdaughter", "ArchitectsDaughter-Regular.ttf", "ArchitectsDaughter-Regular.ttf"),
  c("gochihand", "GochiHand-Regular.ttf", "GochiHand-Regular.ttf"),
  c("nunito", "Nunito%5Bwght%5D.ttf", "Nunito-VF.ttf"),
  c("lilitaone", "LilitaOne-Regular.ttf", "LilitaOne-Regular.ttf")
)
for (g in google) {
  fetch(file.path(gf, g[1], g[2]), file.path(fonts_dir, g[3]))
  fetch(file.path(gf, g[1], "OFL.txt"), file.path(lic_dir, paste0(g[1], "-OFL.txt")))
}

# Cascadia Code: Microsoft's own static Regular and Bold from its release, used
# as they are. (Making them from the variable font would be a Modified Version
# under the OFL, which may not keep the Reserved Font Name "Cascadia Code".)
cascadia_zip <- tempfile(fileext = ".zip")
fetch("https://github.com/microsoft/cascadia-code/releases/download/v2407.24/CascadiaCode-2407.24.zip",
      cascadia_zip)
for (style in c("Regular", "Bold")) {
  utils::unzip(cascadia_zip, files = sprintf("ttf/static/CascadiaCode-%s.ttf", style),
               exdir = tempdir(), junkpaths = TRUE)
  file.copy(file.path(tempdir(), sprintf("CascadiaCode-%s.ttf", style)),
            file.path(fonts_dir, sprintf("CascadiaCode-%s.ttf", style)), overwrite = TRUE)
}
fetch("https://raw.githubusercontent.com/microsoft/cascadia-code/main/OFL.txt",
      file.path(lic_dir, "cascadiacode-OFL.txt"))

# Excalifont's licence text lives in its name table; write it out next to the others.
ofl_body <- readLines(file.path(lic_dir, "patrickhand-OFL.txt"), warn = FALSE)
start <- grep("^This Font Software is licensed", ofl_body)[1]
writeLines(c("Copyright (c) 2024 by Excalidraw.", "", ofl_body[start:length(ofl_body)]),
           file.path(lic_dir, "Excalifont-OFL.txt"))

status <- system2("python3", c("data-raw/fonts.py", fonts_dir))
if (status != 0) stop("font conversion failed")

# ---- JavaScript (versions pinned to what @excalidraw/excalidraw uses) ---------
jsd <- "https://cdn.jsdelivr.net/npm"
fetch(file.path(jsd, "roughjs@4.6.4/bundled/rough.js"), file.path(js_dir, "rough.js"))
fetch(file.path(jsd, "roughjs@4.6.4/LICENSE"), file.path(js_dir, "rough.LICENSE"))
fetch(file.path(jsd, "lz-string@1.5.0/libs/lz-string.min.js"), file.path(js_dir, "lz-string.min.js"))
fetch(file.path(jsd, "lz-string@1.5.0/LICENSE"), file.path(js_dir, "lz-string.LICENSE"))
fetch(file.path(jsd, "perfect-freehand@1.2.0/LICENSE"), file.path(js_dir, "perfect-freehand.LICENSE"))

# perfect-freehand ships CommonJS only; wrap it so V8 gets a `PerfectFreehand` global.
pf <- tempfile(fileext = ".js")
fetch(file.path(jsd, "perfect-freehand@1.2.0/dist/cjs/index.js"), pf)
writeLines(c(
  "// perfect-freehand 1.2.0 (MIT, Steve Ruiz), CommonJS build wrapped for V8",
  "var PerfectFreehand = (function () {",
  "var module = { exports: {} }; var exports = module.exports;",
  readLines(pf, warn = FALSE),
  "return module.exports;",
  "})();"
), file.path(js_dir, "perfect-freehand.js"))

message("done")

# ---- sticker libraries (libraries.excalidraw.com, MIT) -----------------------
stickers <- c(
  "r-icons" = "jumpingrivers/r.excalidrawlib",
  "stick-figures" = "youritjang/stick-figures.excalidrawlib",
  "storytelling" = "drwnio/storytelling.excalidrawlib",
  "bubbles" = "ocapraro/bubbles.excalidrawlib",
  "sticky-notes" = "ferminrp/post-it.excalidrawlib",
  "stars" = "lipis/stars.excalidrawlib",
  "hearts" = "dwelle/hearts.excalidrawlib",
  "emojis" = "anumithaapollo12/emojis.excalidrawlib",
  "data-viz" = "dbssticky/data-viz.excalidrawlib",
  "signs" = "kwirke/some-handdrawn-signs.excalidrawlib",
  "icons" = "ferminrp/awesome-icons.excalidrawlib",
  "data-science" = "farisology/data-science.excalidrawlib"
)
dir.create("inst/stickers", showWarnings = FALSE)
for (nm in names(stickers)) {
  fetch(file.path("https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries",
                  stickers[[nm]]), file.path("inst/stickers", paste0(nm, ".excalidrawlib")))
}
# inst/stickers/manifest.csv (titles, authors, sources) was written from the
# repository's libraries.json.

# The Open Peeps generator (inst/js/peeps.js) and the editor bundle
# (inst/htmlwidgets/lib/excalidraw-widget) are built with: cd srcjs && npm run build
