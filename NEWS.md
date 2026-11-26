# scratchy 0.1.0

First public version, on GitHub with a browser version of the editor.

* Renamed from excalidrawer to scratchy. Drawings tag what R generated in
  `customData$scratchy` (it was `customData$excalidrawer`).

* `excalidraw()` gains an scratchy sidebar (`extras = TRUE`, the button
  next to Library): the twelve sticker libraries, Open Peeps people, the style
  presets, Mermaid diagrams, and exports to PNG, SVG, editable SVG, a
  self-drawing animated SVG, `.excalidraw` and Obsidian `.excalidraw.md`.
* The editor's JavaScript is now one core, `Scratchy.mount()`, shared by
  the R widget, the browser version and denr's Sketch panel.
* Plots are read from svglite's output with a small built-in parser instead
  of xml2 (now only suggested): xml2's WebAssembly build crashes webR when it
  reads such SVG twice, which broke `as_excalidraw()` in denr. Conversions
  are unchanged.
* `exc_save()` to PDF falls back to R's `pdf()` device (text as outlines)
  where cairo can't load, as on macOS without XQuartz.
* GIFs from `exc_animate()` play the animation even on computers set to
  reduce motion (the recording emulates no preference).
* Cascadia Code is now Microsoft's own static Regular and Bold, unmodified,
  instead of instances made from the variable font (its name is reserved
  under the OFL). Text looks and measures the same.
* shiny and bslib moved to Suggests: only Sketch Studio and `exc_edit()` use
  them, so the package installs faster (also in webR).
* Sketch Studio offers the Penguins data only on R 4.5 and later, where
  `datasets::penguins` exists.

# scratchy 0.0.0.9000

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
