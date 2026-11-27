import { slideFrame, ensureFrame } from "./layout.js";

export async function deckSnapshot(workspace, projectId, subtree = null) {
  if ([...workspace.sessions.values()].some((s) => s.board.projectId === projectId && s.ctrl.api.getAppState().editingTextElement)) throw new Error("Finish editing canvas text before presenting or exporting.");
  await workspace.flushAll(); await workspace.projects.manager.idle();
  const p = await workspace.store.project(projectId);
  if (!p?.managed) throw new Error("Link the project to Markdown before presenting it.");
  if (p.draft !== null) throw new Error("Apply or discard the master Markdown draft before presenting or exporting.");
  const selected = new Set();
  for (const n of p.nodes) if (!subtree || n.id === subtree || selected.has(n.parentId)) selected.add(n.id);
  const slides = [];
  for (const n of p.nodes) if (selected.has(n.id) && n.include) {
    const data = await workspace.store.board(n.boardId); if (!data || data.board.deletedAt) continue;
    const scene = ensureFrame(structuredClone(data.scene), n.id, n.title), frame = slideFrame(scene, n.id);
    const missing = scene.elements.filter((e) => !e.isDeleted && e.customData?.scratchy?.markdown?.kind === "missing-image");
    if (missing.length) throw new Error(`Resolve the missing image on “${n.title}” before exporting.`);
    const outside = scene.elements.filter((e) => !e.isDeleted && e.id !== frame.id && (e.x < frame.x || e.y < frame.y || e.x + e.width > frame.x + frame.width || e.y + e.height > frame.y + frame.height));
    slides.push({ node: n, scene, frame, outside });
  }
  if (!slides.length) throw new Error("This selection has no included slides.");
  return { title: p.title, projectId, revision: p.revision, slides, overflow: slides.filter((s) => s.outside.length).map((s) => ({ title: s.node.title, elements: s.outside.map((e) => e.id) })) };
}
export async function renderSlide(S, slide, { scale = 2, elements = slide.scene.elements, background = true } = {}) {
  // exportingFrame fixes the bounds even when the slide contains little content.
  return S.exportScene({ ...slide.scene, elements: elements.some((e) => e.id === slide.frame.id) ? elements : [slide.frame, ...elements] }, { type: "png", as: "blob", frameId: slide.frame.id, padding: 0, scale, background });
}
const dataURL = (blob) => new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = () => reject(reader.error); reader.readAsDataURL(blob); });
export async function exportPowerPoint(S, deck, { portableFonts = false, progress = () => {} } = {}) {
  const { default: PptxGenJS } = await import("pptxgenjs");
  const pptx = new PptxGenJS(); const first = deck.slides[0].frame;
  pptx.defineLayout({ name: "SCRATCHY", width: first.width / 96, height: first.height / 96 }); pptx.layout = "SCRATCHY"; pptx.title = deck.title; pptx.author = "Scratchy";
  const fonts = { 1: "Virgil", 2: "Arial", 3: "Cascadia Code", 5: "Excalifont", 6: "Nunito", 7: "Lilita One", 8: "Comic Shanns", 9: "Liberation Sans" };
  for (let i = 0; i < deck.slides.length; i++) {
    const item = deck.slides[i], slide = pptx.addSlide(), f = item.frame;
    slide.background = { color: (item.scene.appState.viewBackgroundColor || "#ffffff").replace("#", "") };
    let run = [];
    const flush = async () => {
      if (!run.length) return;
      slide.addImage({ data: await dataURL(await renderSlide(S, item, { elements: run, background: false })), x: 0, y: 0, w: f.width / 96, h: f.height / 96 }); run = [];
    };
    for (const e of item.scene.elements.filter((e) => !e.isDeleted && e.id !== f.id)) {
      if (e.type !== "text") { run.push(e); continue; }
      await flush();
      if (e.x + e.width <= f.x || e.y + e.height <= f.y || e.x >= f.x + f.width || e.y >= f.y + f.height) continue;
      slide.addText(e.text || e.originalText || "", {
        x: (e.x - f.x) / 96, y: (e.y - f.y) / 96, w: e.width / 96, h: e.height / 96,
        fontFace: portableFonts ? "Arial" : fonts[e.fontFamily] || "Arial", fontSize: e.fontSize * .75,
        color: (e.strokeColor || "#1e1e1e").replace("#", ""), margin: 0, breakLine: false,
        align: e.textAlign || "left", valign: "top", rotate: (e.angle || 0) * 180 / Math.PI,
        lineSpacingMultiple: e.lineHeight || 1.25, transparency: 100 - (e.opacity ?? 100),
        objectName: e.id, ...(e.link && /^https?:\/\//i.test(e.link) ? { hyperlink: { url: e.link } } : {}),
      });
    }
    await flush(); progress(i + 1, deck.slides.length);
  }
  return pptx.write({ outputType: "blob", compression: true });
}
export async function exportPDF(S, deck, { progress = () => {} } = {}) {
  const { PDFDocument } = await import("pdf-lib"), doc = await PDFDocument.create(); doc.setTitle(deck.title); doc.setCreator("Scratchy");
  for (let i = 0; i < deck.slides.length; i++) {
    const item = deck.slides[i], png = await doc.embedPng(await (await renderSlide(S, item)).arrayBuffer());
    const page = doc.addPage([item.frame.width * .75, item.frame.height * .75]);
    page.drawImage(png, { x: 0, y: 0, width: page.getWidth(), height: page.getHeight() }); progress(i + 1, deck.slides.length);
  }
  return new Blob([await doc.save()], { type: "application/pdf" });
}
