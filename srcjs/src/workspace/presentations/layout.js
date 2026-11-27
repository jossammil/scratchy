import { emptyScene, uid } from "../model.js";
export const SLIDE = { width: 1280, height: 720 };
export const binding = (e) => e.customData?.scratchy?.markdown;
const tagged = (e, metadata) => ({ ...e, customData: { ...e.customData, scratchy: { ...e.customData?.scratchy, markdown: metadata } } });
const element = (type, id, props) => ({ id, type, x: 0, y: 0, width: 0, height: 0, angle: 0, strokeColor: "#1e1e1e", backgroundColor: "transparent", fillStyle: "solid", strokeWidth: 1, strokeStyle: "solid", roughness: 1, opacity: 100, groupIds: [], frameId: null, roundness: null, seed: 1, version: 1, versionNonce: 1, isDeleted: false, boundElements: null, updated: Date.now(), link: null, locked: false, ...props });
const dimensions = (text, size, width) => Math.max(size * 1.3, text.split("\n").reduce((n, line) => n + Math.max(1, Math.ceil(line.length * size * 0.55 / width)), 0) * size * 1.3);
export function projectScene(projectId, node, previous = emptyScene(), { reflow = false, resources = {} } = {}) {
  const old = previous.elements || [], frameId = `slide_${node.id}`, frame = old.find((e) => e.id === frameId) || element("frame", frameId, { ...SLIDE, name: node.title, locked: true });
  const live = old.filter((e) => !e.isDeleted), generated = new Map(live.filter((e) => binding(e)?.nodeId === node.id).map((e) => [binding(e).blockId, e]));
  const required = new Set(node.blocks.map((b) => b.id)); if (!node.hidden) required.add("title");
  const elements = live.filter((e) => e.id !== frameId && (!binding(e) || binding(e).nodeId !== node.id || (binding(e).role === "annotation" && required.has(binding(e).blockId))));
  const files = { ...(previous.files || {}) }; let y = 130;
  const text = (id, value, kind, top, size = 28) => {
    const prior = generated.get(id), annotation = binding(prior || {})?.role === "annotation";
    const base = prior || element("text", `md_${node.id}_${id}`, { x: 64, y: top, width: 1152, fontSize: size, fontFamily: kind === "code" ? 3 : 5, textAlign: "left", verticalAlign: "top", containerId: null, autoResize: false, lineHeight: 1.3, frameId });
    const next = tagged({ ...base, text: value, originalText: value, height: base.originalText === value && !reflow ? base.height : dimensions(value, base.fontSize || size, base.width || 1152), version: base.version + 1, versionNonce: Math.floor(Math.random() * 2147483647), updated: Date.now() }, { projectId, nodeId: node.id, blockId: id, kind, role: annotation ? "annotation" : "generated" });
    if (reflow && !annotation) Object.assign(next, { x: 64, y: top, width: 1152, frameId });
    const index = elements.findIndex((e) => e.id === next.id);
    if (index >= 0) elements[index] = next; else elements.push(next);
    return next;
  };
  if (!node.hidden) text("title", node.title, "title", 48, 48);
  for (const block of node.blocks) {
    if (block.kind === "image") {
      const resource = resources[block.url], prior = generated.get(block.id);
      if (resource) {
        const fileId = resource.id || `asset_${block.id}`; files[fileId] = { ...resource, id: fileId };
        const image = tagged((prior?.type === "image" ? prior : null) || element("image", `md_${node.id}_${block.id}`, { x: 64, y, width: 640, height: 300, fileId, scale: [1, 1], status: "saved", frameId }), { projectId, nodeId: node.id, blockId: block.id, kind: "image", role: "generated" });
        image.fileId = fileId; elements.push(image); y += image.height + 24;
      } else { text(block.id, `[Missing image: ${block.url}]`, "missing-image", y); y += 70; }
    } else { const e = text(block.id, block.text, block.kind, y); if (block.links?.length === 1 && /^https?:\/\//i.test(block.links[0])) e.link = block.links[0]; if (binding(e).role !== "annotation") y = Math.max(y, e.y + e.height + 24); }
  }
  const order = new Map(old.map((e, i) => [e.id, i]));
  elements.sort((a, b) => (order.get(a.id) ?? Infinity) - (order.get(b.id) ?? Infinity));
  return { ...previous, type: "excalidraw", elements: [{ ...frame, name: node.title }, ...elements], files };
}
export function adoptText(scene, projectId, nodeId, pairs) {
  return { ...scene, elements: scene.elements.map((e) => pairs.has(e.id) ? tagged(e, { projectId, nodeId, blockId: pairs.get(e.id), kind: "paragraph", role: "annotation" }) : e) };
}
export function tagAnnotation(e, projectId, nodeId, blockId = `text_${e.id}`) { return tagged(e, { projectId, nodeId, blockId, kind: "paragraph", role: "annotation" }); }
export function slideFrame(scene, nodeId) { return scene.elements.find((e) => e.type === "frame" && e.id === `slide_${nodeId}` && !e.isDeleted); }
export function ensureFrame(scene, nodeId, title) {
  if (slideFrame(scene, nodeId)) return scene;
  return { ...scene, elements: [element("frame", `slide_${nodeId}`, { ...SLIDE, name: title, locked: true }), ...scene.elements.map((e) => ({ ...e, frameId: e.frameId || `slide_${nodeId}` }))] };
}
export function cloneScene(scene, projectId, nodeId) {
  const ids = new Map(scene.elements.map((e) => [e.id, uid()]));
  return { ...structuredClone(scene), elements: scene.elements.map((e) => {
    const next = { ...structuredClone(e), id: e.type === "frame" ? `slide_${nodeId}` : ids.get(e.id), frameId: e.frameId ? `slide_${nodeId}` : null, groupIds: [] };
    if (next.containerId) next.containerId = ids.get(next.containerId) || null;
    if (next.boundElements) next.boundElements = next.boundElements.map((b) => ({ ...b, id: ids.get(b.id) })).filter((b) => b.id);
    for (const key of ["startBinding", "endBinding"]) if (next[key]) next[key] = { ...next[key], elementId: ids.get(next[key].elementId) };
    if (binding(next)) return tagged(next, { ...binding(next), projectId, nodeId }); return next;
  }) };
}
