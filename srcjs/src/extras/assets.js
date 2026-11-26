// Sticker libraries and Open Peeps people for the editor.

/** The sticker libraries listed in <base>/index.json (written by the build from manifest.csv). */
export async function stickerIndex(base) {
  const res = await fetch(new URL("index.json", base));
  if (!res.ok) throw new Error("The sticker list could not be loaded.");
  return res.json();
}

/** One .excalidrawlib file as a Blob, which Excalidraw's updateLibrary() reads. */
export async function stickerLibrary(base, file) {
  const res = await fetch(new URL(file, base));
  if (!res.ok) throw new Error(`${file} could not be loaded.`);
  return new Blob([await res.text()], { type: "application/vnd.excalidrawlib+json" });
}

let dicebear = null;
const loadDicebear = () => (dicebear ||= Promise.all([import("@dicebear/core"), import("@dicebear/open-peeps")]));

/** Choices for each Open Peeps option (face, head, accessories ...), as exc_peep_options() gives. */
export async function peepOptions() {
  const [, openPeeps] = await loadDicebear();
  const props = openPeeps.schema.properties;
  return Object.fromEntries(Object.entries(props).map(([k, p]) => [k, p.items?.enum || p.default]));
}

/** An Open Peeps person as SVG text; options as in DiceBear (seed, face: [..], skinColor: [hex] ...). */
export async function peepSvg(options = {}) {
  const [{ createAvatar }, openPeeps] = await loadDicebear();
  return createAvatar(openPeeps, options).toString();
}

const randomId = () => Array.from(crypto.getRandomValues(new Uint8Array(10)), (b) => (b % 36).toString(36)).join("");

/** An SVG (text) as an image element plus its file, ready for controller.add(). */
export function svgImageScene(svg, { x = 0, y = 0, width = 160, height = 160 } = {}) {
  const fileId = randomId();
  const bytes = new TextEncoder().encode(svg);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return {
    elements: [{ type: "image", id: randomId(), x, y, width, height, fileId, status: "saved", scale: [1, 1] }],
    files: { [fileId]: { id: fileId, mimeType: "image/svg+xml", dataURL: `data:image/svg+xml;base64,${btoa(bin)}`, created: Date.now() } },
  };
}
