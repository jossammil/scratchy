// Workspace rules shared by the IndexedDB adapter, UI and archive reader.
export const HISTORY_LIMIT = 50;
export const SNAPSHOT_INTERVAL = 5 * 60 * 1000;
export const TRASH_RETENTION = 30 * 24 * 60 * 60 * 1000;
export const emptyScene = () => ({ type: "excalidraw", version: 2, elements: [], appState: { viewBackgroundColor: "#ffffff" }, files: {} });
export const uid = () => crypto.randomUUID();
export const normalize = (s) => String(s || "").normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
export function drawing(value) {
  const scene = typeof value === "string" ? JSON.parse(value) : structuredClone(value);
  if (!scene || !Array.isArray(scene.elements) || (scene.type && scene.type !== "excalidraw")) throw new Error("This is not an Excalidraw drawing.");
  if (scene.files && (typeof scene.files !== "object" || Array.isArray(scene.files))) throw new Error("Invalid drawing images.");
  return { ...scene, type: "excalidraw", appState: scene.appState || {}, files: scene.files || {} };
}
export const contentKey = (scene) => JSON.stringify(drawing(scene));
export const liveElements = (scene) => scene.elements.filter((e) => !e.isDeleted);
export const labels = (scene) => liveElements(scene).filter((e) => e.type === "text").map((e) => ({ id: e.id, text: e.originalText || e.text || "" }));
export const viewport = (state) => ({ scrollX: state.scrollX || 0, scrollY: state.scrollY || 0, zoom: state.zoom?.value || 1 });
export function searchBoards(boards, query) {
  const words = normalize(query).trim().split(/\s+/).filter(Boolean);
  return boards.filter((b) => !b.deletedAt).map((b) => {
    const title = normalize(b.title), text = normalize((b.labels || []).map((t) => t.text).join(" "));
    if (!words.every((word) => `${title} ${text}`.includes(word))) return null;
    const matches = (b.labels || []).filter((t) => words.some((word) => normalize(t.text).includes(word)));
    return { board: b, matches, score: words.length ? (title === normalize(query).trim() ? 0 : words.every((w) => title.includes(w)) ? 1 : 2) : 0 };
  }).filter(Boolean).sort((a, b) => a.score - b.score || Number(b.board.pinned) - Number(a.board.pinned) || b.board.updatedAt - a.board.updatedAt);
}
export function folderDescendants(folders, id) {
  const found = new Set([id]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const folder of folders) if (found.has(folder.parentId) && !found.has(folder.id)) { found.add(folder.id); changed = true; }
  }
  return found;
}
export function validFolderMove(folders, id, parentId) {
  return parentId === null || (folders.some((f) => f.id === parentId) && !folderDescendants(folders, id).has(parentId));
}
export async function digest(value) {
  const bytes = new TextEncoder().encode(typeof value === "string" ? value : JSON.stringify(value));
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), (b) => b.toString(16).padStart(2, "0")).join("");
}
// Images are content-addressed; each reference retains Excalidraw's file ID and metadata.
export async function packScene(value) {
  const { files, ...scene } = drawing(value), fileRefs = {}, assets = [];
  for (const [id, file] of Object.entries(files)) {
    if (typeof file.dataURL !== "string") throw new Error("A drawing image has no data.");
    const { dataURL, ...metadata } = file, key = await digest(dataURL);
    fileRefs[id] = { ...metadata, assetKey: key };
    assets.push({ key, dataURL });
  }
  return { scene, fileRefs, assets, labels: labels(scene), fingerprint: await digest({ scene, fileRefs }) };
}
export function unpackScene(record, assets) {
  const files = {};
  for (const [id, ref] of Object.entries(record.fileRefs || {})) {
    const { assetKey, ...metadata } = ref, asset = assets.get(assetKey);
    if (!asset) throw new Error("A saved drawing image is missing. Restore a workspace backup.");
    files[id] = { ...metadata, dataURL: asset.dataURL };
  }
  return { ...record.scene, files };
}
