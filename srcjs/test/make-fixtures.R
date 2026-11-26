# Writes the files the JavaScript tests read, so they check against what the
# R package itself writes.   Rscript srcjs/test/make-fixtures.R  (from the package root)
devtools::load_all(quiet = TRUE)
s <- exc_scene(
  exc_rect(0, 0, 160, 80, label = "Idea", fill = "yellow", fill_style = "solid"),
  exc_arrow(c(170, 270), c(40, 40), label = "becomes"),
  exc_text("Ünïcode ✓ text", 0, 120)
)
write_excalidraw(s, "srcjs/test/fixtures/r-scene.excalidraw")
write_excalidraw(s, "srcjs/test/fixtures/r-scene.excalidraw.md")
