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
