// Entry point of the editor bundle (inst/htmlwidgets/lib/excalidraw-widget/
// excalidraw-widget.js). Loaded as a <script type="module"> by the R
// htmlwidget, or with import() by the site and denr; either way it defines
// globalThis.Scratchy.
import "@excalidraw/excalidraw/index.css";
import { mount, parseScene } from "./core/mount.jsx";
import { exportScene } from "./core/export.js";
import { mermaidToScene } from "./core/mermaid.js";
import { readDrawingFile, drawingBlob, isDrawingName, drawingStem } from "./core/files.js";
import { animateSvg } from "./extras/animate.js";
import { toObsidian, fromObsidian, isObsidian } from "./extras/obsidian.js";
import { presets, restyleElements } from "./extras/restyle.js";
import { stickerIndex, stickerLibrary, peepSvg, peepOptions, svgImageScene } from "./extras/assets.js";
import { defaultDownload } from "./extras/sidebar.jsx";
import "./bridges/htmlwidget.js";
import "./bridges/headless.js";

// Fonts are served next to this bundle so the editor works offline. This has
// to be in the entry file: import.meta.url is the bundle's own address here.
window.EXCALIDRAW_ASSET_PATH = new URL("./", import.meta.url).href;

export const version = __SCRATCHY_VERSION__;
export const extras = {
  animateSvg, toObsidian, fromObsidian, isObsidian, presets, restyleElements,
  stickerIndex, stickerLibrary, peepSvg, peepOptions, svgImageScene, download: defaultDownload,
};
export const files = { readDrawingFile, drawingBlob, isDrawingName, drawingStem };
export { mount, parseScene, exportScene, mermaidToScene };

const Scratchy = { version, mount, parseScene, exportScene, mermaidToScene, extras, files };
globalThis.Scratchy = Scratchy;
export default Scratchy;
