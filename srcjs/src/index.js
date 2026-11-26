// Entry point of the editor bundle (inst/htmlwidgets/lib/excalidraw-widget/
// excalidraw-widget.js). Loaded as a <script type="module"> by the R
// htmlwidget, or with import() by the site and denr; either way it defines
// globalThis.Excalidrawer.
import "@excalidraw/excalidraw/index.css";
import { mount, parseScene } from "./core/mount.jsx";
import { exportScene } from "./core/export.js";
import { mermaidToScene } from "./core/mermaid.js";
import "./bridges/htmlwidget.js";
import "./bridges/headless.js";

// Fonts are served next to this bundle so the editor works offline. This has
// to be in the entry file: import.meta.url is the bundle's own address here.
window.EXCALIDRAW_ASSET_PATH = new URL("./", import.meta.url).href;

export const version = __EXCALIDRAWER_VERSION__;
export { mount, parseScene, exportScene, mermaidToScene };

const Excalidrawer = { version, mount, parseScene, exportScene, mermaidToScene };
globalThis.Excalidrawer = Excalidrawer;
export default Excalidrawer;
