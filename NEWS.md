# excalidrawer 0.1.0

First public version, on GitHub with a browser version of the editor.

* `excalidraw()` gains an excalidrawer sidebar (`extras = TRUE`, the button
  next to Library): the twelve sticker libraries, Open Peeps people, the style
  presets, Mermaid diagrams, and exports to PNG, SVG, editable SVG, a
  self-drawing animated SVG, `.excalidraw` and Obsidian `.excalidraw.md`.
* The editor's JavaScript is now one core, `Excalidrawer.mount()`, shared by
  the R widget, the browser version and denr's Sketch panel.
* shiny and bslib moved to Suggests: only Sketch Studio and `exc_edit()` use
  them, so the package installs faster (also in webR).
* Sketch Studio offers the Penguins data only on R 4.5 and later, where
  `datasets::penguins` exists.

# excalidrawer 0.0.0.9000

First version.

* Excalidraw scenes in R: shapes, text, lines, arrows, freehand strokes,
  images, frames and groups, stored as Excalidraw's own JSON.
* Read and write `.excalidraw`, `.excalidrawlib`, Obsidian `.excalidraw.md`,
  and SVG/PNG images with the scene embedded.
* Offline rendering with rough.js and Excalidraw's shape logic (in V8) to
  PNG, JPEG, SVG and PDF; paper backgrounds and style presets.
* `exc_animate()` saves a scene as an SVG that draws itself (strokes traced in
  z-order, fills fading in, text written letter by letter), or as a GIF
  recorded in headless Chrome.
* `as_excalidraw()` and `sketch()` for ggplot2 and base graphics;
  `theme_excalidraw()` and Excalidraw colour scales; annotations placed with
  data values.
* The Excalidraw editor as an htmlwidget, with Shiny bindings, a proxy and the
  `exc_edit()` gadget; Mermaid conversion and exact exports via headless Chrome.
* Stickers from Excalidraw libraries, Open Peeps people, data-driven
  templates, D2 diagrams and the xkcd font.
* Sketch Studio (`run_sketch_studio()`), a Shiny app for hand-drawn charts.
* Quarto `excalidraw-revealjs` slides and PowerPoint export.
