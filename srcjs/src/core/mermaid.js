// Mermaid text -> Excalidraw elements (and files, for diagram types Mermaid can
// only give as images). The converter and Mermaid load on first use.
import { convertToExcalidrawElements } from "@excalidraw/excalidraw";

export async function mermaidToScene(code, fontSize = 20) {
  const { parseMermaidToExcalidraw } = await import("@excalidraw/mermaid-to-excalidraw");
  const { elements, files } = await parseMermaidToExcalidraw(code, { themeVariables: { fontSize: `${fontSize}px` } });
  return { elements: convertToExcalidrawElements(elements, { regenerateIds: true }), files: files || {} };
}
