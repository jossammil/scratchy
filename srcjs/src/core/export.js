// PNG and SVG exports with Excalidraw's own exporter.
import { exportToBlob, exportToSvg } from "@excalidraw/excalidraw";
import { bytesToBase64 } from "./scene.js";

/**
 * scene: { elements, appState, files }.
 * opts: { type: "png" | "svg", scale (png, default 2), padding (10),
 *         background (true), embed (false: put the scene inside the image),
 *         dark (false), as: "base64" (default) | "blob" }.
 * Returns { type, data } (data: base64 PNG or SVG text), or a Blob with as = "blob".
 */
export async function exportScene({ elements, appState, files }, opts = {}) {
  const state = {
    ...appState,
    exportBackground: opts.background !== false,
    exportEmbedScene: !!opts.embed,
    exportWithDarkMode: !!opts.dark,
  };
  const base = { elements, appState: state, files: files || {}, exportPadding: opts.padding ?? 10 };
  if (opts.type === "png") {
    const scale = opts.scale || 2;
    const blob = await exportToBlob({ ...base, mimeType: "image/png", quality: 1,
      getDimensions: (w, h) => ({ width: w * scale, height: h * scale, scale }) });
    if (opts.as === "blob") return blob;
    return { type: "png", data: bytesToBase64(new Uint8Array(await blob.arrayBuffer())) };
  }
  const svg = (await exportToSvg(base)).outerHTML;
  if (opts.as === "blob") return new Blob([svg], { type: "image/svg+xml" });
  return { type: "svg", data: svg };
}
