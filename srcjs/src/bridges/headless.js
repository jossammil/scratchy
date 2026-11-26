// Helpers R drives through chromote (R/chrome.R): Mermaid conversion and
// exports made by Excalidraw itself.
import { parseScene } from "../core/mount.jsx";
import { exportScene } from "../core/export.js";
import { mermaidToScene } from "../core/mermaid.js";

window.scratchyHeadless = {
  async mermaid(code, fontSize) {
    const s = await mermaidToScene(code, fontSize);
    return JSON.stringify({ type: "excalidraw", version: 2, source: "scratchy",
                            elements: s.elements, appState: {}, files: s.files });
  },
  async export(sceneJson, opts) {
    return exportScene(parseScene(sceneJson), opts);
  },
};
