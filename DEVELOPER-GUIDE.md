# scratchy developer guide

How scratchy is put together, how to build and test it, and what other
projects (the website, denr) rely on. For using the package, see README.md.

## 1. The big picture

scratchy is three things built from one repository:

```
                 ┌──────────────── R package (R/, inst/) ────────────────┐
 ggplot2, base   │ as_excalidraw() → exc_scene (Excalidraw JSON in R)    │
 graphics, R  ──▶│ native renderer: rough.js in V8 + grid → PNG/SVG/PDF   │
 code            │ excalidraw() htmlwidget ──┐                            │
                 └───────────────────────────┼────────────────────────────┘
                                             ▼
                 srcjs/  ──esbuild──▶  inst/htmlwidgets/lib/excalidraw-widget/
                 Scratchy.mount(el, opts) → controller   (one editor core)
                          │                         │
                          ▼                         ▼
          site-dist/ (GitHub Pages, no R)     denr's Sketch panel (webR)
```

- **The R package** keeps scenes as Excalidraw's own JSON, converts plots by
  capturing them with svglite, and renders without a browser using rough.js
  inside V8 (also under webR: V8 there runs on the browser's own engine).
- **The editor bundle** is the real `@excalidraw/excalidraw` plus
  scratchy's sidebar (stickers, people, presets, Mermaid, exports). It is
  built once and committed, so installing the R package needs no Node.
- **The website** (`site/`, built into `site-dist/`) and **denr** load that
  same bundle and call `Scratchy.mount()`.

## 2. Repository map

```
R/                      the package (see section 3)
inst/
  htmlwidgets/          the htmlwidget binding and, under lib/, the BUILT editor bundle
  js/                   rough.js, perfect-freehand, lz-string, exc-shapes.js (native renderer, V8)
                        and peeps.js (BUILT: DiceBear for V8)
  fonts/, stickers/     bundled fonts and sticker libraries (stickers/index.json is BUILT)
  quarto/, templates/   the Quarto slide format and template examples
srcjs/                  the browser code (not in the R build)
  src/index.js          bundle entry: exports, globalThis.Scratchy
  src/core/             mount.jsx, scene.js, export.js, mermaid.js, files.js
  src/extras/           sidebar.jsx, restyle.js (+ presets.json, BUILT from R), animate.js,
                        obsidian.js, assets.js (stickers, Open Peeps)
  src/bridges/          htmlwidget.js (Shiny proxy), headless.js (chromote helpers)
  src/peeps.js          DiceBear bundle for R's V8
  test/                 node:test unit tests; fixtures/ written by R (make-fixtures.R)
  test-e2e/e2e.mjs      Playwright tests of the website
  tools/build-site.mjs  builds site-dist/
site/                   the website's own files (page template, app.js, sw.template.js, icons)
data-raw/               scripts that fetch assets and write generated data (extras-json.R)
tests/testthat/         R tests
.github/workflows/      R-CMD-check, js (unit, bundle check, e2e), pages
```

Never edit by hand: `inst/htmlwidgets/lib/**`, `inst/js/peeps.js`,
`inst/stickers/index.json`, `srcjs/src/extras/presets.json`, `site-dist/**`.

## 3. The R side

| Area | Files |
|---|---|
| Scene model, JSON and file formats | `scene.R`, `elements.R`, `style.R`, `io-json.R`, `io-obsidian.R`, `io-embed.R` |
| Native renderer | `v8.R` (one V8 context), `render.R`, `render-text.R`, `save.R`, `animate.R` |
| Plots to scenes | `gg-convert.R` (svglite capture → elements), `gg-theme.R`, `sketch.R`, `annotate.R` |
| Editor, Shiny, gadget | `widget.R` |
| Headless Chrome (Mermaid, exact exports, GIFs, slides) | `chrome.R` |
| Extras | `stickers.R`, `templates.R`, `d2.R`, `slides.R`, `pptx.R`, `app.R` (Sketch Studio) |

Fonts are registered with systemfonts in `.onLoad`; all text is measured with
textshaping, so a scene's text boxes match the editor's.

## 4. The bridge: htmlwidgets

`excalidraw()` sends `x = { scene, mode, theme, grid, zen, debounce, extras }`.
`inst/htmlwidgets/excalidraw.js` waits for the ES-module bundle and calls
`scratchyLib.render(el, x)`, which is `mount()` plus the Shiny proxy
(`bridges/htmlwidget.js`). With `extras = TRUE`, R also attaches
`inst/stickers` as the dependency `scratchy-stickers-<version>`, which the
bundle finds next to its own folder.

Shiny messages arrive as `{ id, method, args }` on `scratchy-proxy`
(`update`, `add`, `replaceChart`, `scrollTo`, `set`, `reset`, `export`,
`mermaid`); results come back as `input$<id>_scene`, `_selection`, `_export`
and `_mermaid`.

## 5. The browser side

`mount(el, opts)` renders the editor into `el` and returns a controller:

| Member | What it does |
|---|---|
| `ready` | promise, resolves when the editor can be changed |
| `api` | Excalidraw's own imperative API |
| `getScene()` / `getSceneData()` | the drawing as `.excalidraw` JSON text / `{ elements, appState, files }` |
| `setScene(scene, { keepAppState })` | replace the drawing |
| `add(scene, { placement: "right" })` | add elements (and files) |
| `replaceChart(scene, chartId)` | swap a generated chart, keeping hand drawings |
| `set({ theme, viewMode, zen, grid, background })` | view settings |
| `export({ type: "png" \| "svg", scale, embed, as: "blob" })` | an image |
| `mermaid(code)` | convert and add Mermaid |
| `refresh()` | after the element moved or was resized while hidden |
| `onChange(fn)` → unsubscribe; `destroy()` | |

Options: `scene`, `mode`, `theme`, `zen`, `grid`, `libraryItems`, `langCode`,
`name`, `debounce`, `onChange(json, data)`, `onSelection(ids)`,
`canvasActions` (`loadScene: false` hides Open), `menu` (plain
`{ label, onSelect, shortcut }` items for the main menu) and `extras` (`true`
or `{ stickers: URL, download(name, blob, info), fileName() }`).

`globalThis.Scratchy` (and the module's exports) also carry
`parseScene`, `exportScene`, `mermaidToScene`, `extras` (animateSvg,
to/fromObsidian, presets, restyleElements, sticker and Open Peeps helpers)
and `files` (`readDrawingFile`, `drawingBlob`, `isDrawingName`,
`drawingStem`).

The website (`site/app.js`) keeps drawings in IndexedDB (`scratchy`
database), opens and saves files with the File System Access API when the
browser has it (downloads otherwise), and registers `sw.js`, which caches
the core at install and the rest in the background.

The standalone site now delegates collection management to
`srcjs/src/workspace/`, built separately into `site-dist/workspace/`. It keeps
one editor instance per visited open tab, mounts restored tabs lazily, and
never adds the workspace UI to the R widget or denr. Its IndexedDB v2 adapter
preserves the legacy `kv` keys and migrates their drawing transactionally.
History shares image assets; full ZIPs include ordinary drawings and a
versioned recovery manifest. See `dev/multi-board/` for the earlier plan,
implementation details, recovery defaults and roadmap.

Additive mount options: `initialViewport: { scrollX, scrollY, zoom }` skips the
initial fit; `onStateChange({ elements, appState, files })` observes upstream
changes before the legacy element-version filter; `onLibraryChange(items)`
persists libraries in hosts that opt in. `controller.set({ name })` rerenders
the export name without resetting the editor. The existing `onChange` and
R/Shiny contracts are unchanged. `window.scratchy.ctrl` and `.doc` are getters
for the active session, and `.workspace` is the standalone host.

## 6. Libraries and the licence rule

Bundled code must be MIT-compatible, listed in `inst/COPYRIGHTS` (and in
`Authors@R` as `ctb`/`cph` when it is substantial), and credited in the
README. esbuild writes the bundle's licences to
`excalidraw-widget.js.LEGAL.txt`. Current: Excalidraw 0.18.1, React 19,
Mermaid (through @excalidraw/mermaid-to-excalidraw), rough.js,
perfect-freehand, lz-string, DiceBear with Open Peeps (CC0 art), the fonts
in `inst/fonts/LICENSES`, and the excalidraw-libraries stickers.

## 7. Tools and the build cycle

Node 22 or later, R 4.1 or later. Memorise this:

```bash
cd srcjs
npm install
npm test            # unit tests (WITH_R=1 also checks R reads what JS writes)
npm run build       # inst/htmlwidgets/lib/excalidraw-widget, inst/js/peeps.js, inst/stickers/index.json
npm run site        # site-dist/
npm run e2e         # Chromium; BROWSER=webkit for WebKit
npm run e2e:workspace # multi-board migration, Undo, recovery, search and scale
```

```r
devtools::document(); devtools::test()   # NOT_CRAN=true also runs the Chrome tests
```

The build stops if `srcjs/package.json` and `DESCRIPTION` give different
versions. It is deterministic: CI rebuilds and fails if the result differs
from what is committed, so always commit the rebuilt files.

## 8. How to update things

- **Bump the version:** `DESCRIPTION` and `srcjs/package.json`, then
  `npm run build` (the version goes into the bundle and `VERSION.json`), and
  `NEWS.md`.
- **Update Excalidraw:** change the pin in `srcjs/package.json`, `npm
  install`, `npm run build`, check `excalidraw_dependency()`'s version in
  `R/widget.R`, run every test (Mermaid and exports go through it too).
- **Change a preset or font:** edit `R/presets.R` / `R/constants.R`, then
  `Rscript data-raw/extras-json.R` and `npm run build`.
- **Add a sticker library:** put the `.excalidrawlib` in `inst/stickers`, add a
  row to `manifest.csv`, `npm run build`.
- **Change the website:** edit `site/`, `npm run site`, preview `site-dist/`
  (`.claude/launch.json` has a "site" entry), `npm run e2e`.

## 9. Tests

- `tests/testthat/`: the R package; snapshot tests draw text as outlines so
  they match across systems; Chrome, Quarto, d2 and officer tests skip when
  those are missing.
- `srcjs/test/`: scene helpers, presets and restyle against the R package,
  Obsidian files read from R's output (`fixtures/`, written by
  `srcjs/test/make-fixtures.R`).
- `srcjs/test-e2e/e2e.mjs`: the website in Chromium and WebKit: drawing,
  reload, stickers, people, presets, Mermaid, exports, animated SVG, Obsidian
  files, offline use, page errors.

## 10. Continuous integration and publishing

- `R-CMD-check.yaml`: macOS, Windows, Linux (release, oldrel), plus an
  `install_github` smoke test.
- `js.yaml`: unit tests, the committed-bundle check, e2e in Chromium and
  WebKit.
- `pages.yaml`: `site-dist/` with the pkgdown site in `site-dist/r/`, to
  https://jossammil.github.io/scratchy/.
- R-universe (`jossammil.r-universe.dev`) builds binaries, including the
  WebAssembly build that denr installs.

## 11. Working with denr

denr (`~/makeit/pocket-r`, the R workspace in the browser) vendors the
editor bundle the way it vendors Plank: its `scripts/sync-scratchy.mjs`
copies `inst/htmlwidgets/lib/excalidraw-widget/`, `inst/stickers/`,
`inst/COPYRIGHTS` and `LICENSE` and records this repository's commit. Its
Sketch panel loads the bundle with `import()` and calls
`Scratchy.mount()`; in R, `Draw()` and the Plots panel's Sketch button
use the scratchy package itself, installed from R-universe.

**The contract** (change it only together with denr):

- `inst/htmlwidgets/lib/excalidraw-widget/excalidraw-widget.js` is an ES
  module that sets `globalThis.Scratchy` and finds its fonts and chunks
  next to itself.
- `VERSION.json` there: `{ scratchy, excalidraw }`.
- `inst/stickers/index.json` and the `.excalidrawlib` files beside it.
- The controller members and options in section 5, `Scratchy.files` and
  `Scratchy.extras.download`.

When any of these change, run denr's `npm run sync-scratchy`, its unit
tests and its `sketch-*` e2e checks.

## 12. Debugging

| Symptom | Likely cause | Fix |
|---|---|---|
| Editor area blank | the element has no height | give it a height; `mount()` only makes a static element `position: relative` |
| Website shows an old build | the service worker's cache | the cache name carries a content hash: reload twice, or unregister it in DevTools |
| `js` CI fails at "bundle matches" | rebuilt files not committed | `npm run build` and commit `inst/` |
| Stickers tab empty in R | `extras = FALSE`, or the stickers dependency did not load | check `excalidraw()`'s dependencies |
| Text boxes too wide/narrow in R | font not registered | `exc_fonts()`; systemfonts must see `inst/fonts` |

Handles: `el.scratchy` (the controller) on any mounted element;
`window.scratchy` (`{ ctrl, doc, version }`) on the website.

## 13. Glossary

- **scene**: Excalidraw's JSON (`elements`, `appState`, `files`); `exc_scene` in R.
- **controller**: what `mount()` returns.
- **extras**: the scratchy sidebar.
- **chart id**: `customData.scratchy.chart`, marking elements generated from one plot.
- **denr**: the browser R workspace that embeds the editor as its Sketch panel.

## 14. Standalone projects and slides

The persistent project explorer and master Markdown live under
`srcjs/src/workspace/projects/`; frame layout, browser presentation and PPTX/PDF
exports live under `srcjs/src/workspace/presentations/`. See
[the project workflow and storage contract](dev/multi-board/projects-and-slides.md).
IndexedDB version 3 retains legacy stores and adds project/document/history stores.
Source edits use explicit Apply; canvas text sync waits for native text editing to
finish. Keep project CAS checks, stable node/block IDs and native element
versionNonce values when changing synchronization. Closed tabs release editors;
source refreshes preserve live editor Undo and deleted-element tombstones.

`npm run e2e:projects` verifies synchronization, Undo, draft conflicts, editable
PPTX text, PDF pages, image resources and ZIP recovery in a real browser. Repeat
with `BROWSER=webkit`. Exporters are dynamic chunks; the site builder includes
static dependencies in the startup cache and exporters in background caching.
The shared `Scratchy.exportScene(scene, { frameId })` option fixes the export
bounds to a native frame; all previous defaults remain.
