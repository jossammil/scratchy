// Obsidian Excalidraw plugin files (.excalidraw.md), the same layout R's
// write_excalidraw() uses: front matter, "## Text Elements", and the scene in
// a %%-hidden "## Drawing" block (compressed-json or json). Images stay inside
// the scene JSON, since a browser can only save one file.
import LZString from "lz-string";

const FRONT = [
  "---", "", "excalidraw-plugin: parsed", "tags: [excalidraw]", "", "---",
  "==⚠  Switch to EXCALIDRAW VIEW in the MORE OPTIONS menu of this document. ⚠== " +
    "You can decompress Drawing data with the command palette: 'Decompress current Excalidraw file'. " +
    "For more info check in plugin settings under 'Saving'",
  "", "", "",
].join("\n");

/** Scene JSON text -> .excalidraw.md text. */
export function toObsidian(json, { compress = true } = {}) {
  const scene = JSON.parse(json);
  const texts = (scene.elements || []).filter((e) => e.type === "text" && !e.isDeleted)
    .map((e) => `${e.originalText ?? e.text ?? ""} ^${e.id}\n\n`).join("");
  let drawing;
  if (compress) {
    const lz = LZString.compressToBase64(json);
    const chunks = lz.match(/.{1,256}/g) || [""];
    drawing = "## Drawing\n```compressed-json\n" + chunks.join("\n\n") + "\n```\n%%";
  } else {
    drawing = "## Drawing\n```json\n" + json + "\n```\n%%";
  }
  return FRONT + "# Excalidraw Data\n\n## Text Elements\n" + texts + "%%\n" + drawing + "\n";
}

/** .excalidraw.md text -> scene JSON text (throws if there is no drawing). */
export function fromObsidian(md) {
  let m = /\n##? Drawing\n[^`]*```compressed-json\n([\s\S]*?)```/.exec(md);
  if (m) {
    const json = LZString.decompressFromBase64(m[1].replace(/[\r\n]/g, ""));
    if (json) return json;
  }
  m = /\n##? Drawing\n[^`]*```json\n([\s\S]*?)```/.exec(md);
  if (m) return m[1];
  throw new Error("This file has no Excalidraw drawing section.");
}

export const isObsidian = (name) => /\.excalidraw\.md$/i.test(name || "");
