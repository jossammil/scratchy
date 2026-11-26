// Opening and saving drawings by file name, for the site and denr:
// .excalidraw (JSON), .excalidraw.md (Obsidian), and .svg / .png images with
// the scene embedded (.excalidraw.svg, .excalidraw.png), plus libraries.
import { loadSceneOrLibraryFromBlob, MIME_TYPES } from "@excalidraw/excalidraw";
import { fromObsidian, toObsidian, isObsidian } from "../extras/obsidian.js";

export const DRAWING_RE = /\.(excalidraw|excalidraw\.json|excalidraw\.md|excalidraw\.svg|excalidraw\.png|excalidrawlib)$/i;
export const isDrawingName = (name) => DRAWING_RE.test(name || "");

/** The name without its drawing extension: "plan.excalidraw.md" -> "plan". */
export const drawingStem = (name) => (name || "drawing").replace(/\.(excalidraw(\.(json|md|svg|png))?|excalidrawlib|svg|png|json|md)$/i, "") || "drawing";

/**
 * Reads a File/Blob (with a name) into { kind: "scene", scene: { elements, appState, files } }
 * or { kind: "library", blob }. Throws with a readable message when it holds no drawing.
 */
export async function readDrawingFile(file, name = file.name) {
  if (isObsidian(name)) return { kind: "scene", scene: JSON.parse(fromObsidian(await file.text())) };
  let r;
  try {
    r = await loadSceneOrLibraryFromBlob(file, null, null);
  } catch (e) {
    throw new Error(`${name || "This file"} has no Excalidraw drawing in it.`);
  }
  if (r.type === MIME_TYPES.excalidrawlib) return { kind: "library", blob: file };
  return { kind: "scene", scene: { elements: r.data.elements, appState: r.data.appState, files: r.data.files } };
}

/** The current drawing as a Blob in the format its name asks for. */
export async function drawingBlob(ctrl, name) {
  if (isObsidian(name)) return new Blob([toObsidian(ctrl.getScene())], { type: "text/markdown" });
  if (/\.svg$/i.test(name)) return ctrl.export({ type: "svg", as: "blob", embed: true });
  if (/\.png$/i.test(name)) return ctrl.export({ type: "png", as: "blob", embed: true });
  return new Blob([ctrl.getScene()], { type: "application/json" });
}
