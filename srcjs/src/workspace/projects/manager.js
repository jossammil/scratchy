import { uid, emptyScene, contentKey } from "../model.js";
import { parseMaster, newMaster, renameNode, setProjectTitle, setNodeFlag, setBlockText, appendText, removeBlock, addNode, removeNode, moveNode, duplicateNode, marker } from "./markdown.js";
import { projectScene, binding, tagAnnotation, adoptText, ensureFrame, cloneScene } from "../presentations/layout.js";

const tick = () => new Promise(requestAnimationFrame);
export class ProjectManager {
  constructor(workspace) { this.w = workspace; this.queues = new Map(); }
  enqueue(id, fn) { const task = (this.queues.get(id) || Promise.resolve()).catch(() => {}).then(fn); this.queues.set(id, task); return task; }
  async idle() { await Promise.allSettled([...this.queues.values()]); }
  async scenes(project) { return Promise.all(project.nodes.map(async (n) => { const data = await this.w.store.board(n.boardId); return { node: n, board: data?.board || { id: n.boardId, title: n.title }, scene: data?.scene || emptyScene() }; })); }
  async create(title, source = newMaster(title), resources = {}) {
    const id = uid(), project = { id, title, managed: true, nodes: [], revision: -1, deletedAt: null, resourceFiles: resources };
    return this.enqueue(id, () => this.commit(project, source));
  }
  async apply(id, source, { force = false, reflow = false, overrides = new Map(), resources } = {}) {
    return this.enqueue(id, async () => {
      const project = await this.w.store.project(id); if (!project) throw new Error("Project not found.");
      if (project.draft !== null && project.draftBase !== project.revision && !force) { const error = new Error("The canvases changed after this draft began. Review the current source, then choose which version to keep."); error.code = "DRAFT_CONFLICT"; throw error; }
      return this.commit(resources ? { ...project, resourceFiles: resources } : project, source, { reflow, overrides });
    });
  }
  async commit(project, source, { reflow = false, overrides = new Map(), preserveDraft = false, incoming = null } = {}) {
    const parsed = parseMaster(source, { assignIds: true }), existing = await this.scenes(project), previous = new Map(existing.map((x) => [x.node.id, x]));
    const nodes = [], scenes = [];
    for (const n of parsed.nodes) {
      const old = overrides.get(n.id) || previous.get(n.id), boardId = old?.board.id || uid();
      const node = { id: n.id, title: n.title, level: n.level, parentId: n.parentId, boardId, hidden: n.hidden, include: n.include };
      const base = incoming?.board.id === boardId ? incoming.scene : old?.scene || emptyScene();
      const scene = projectScene(project.id, n, base, { reflow, resources: project.resourceFiles });
      nodes.push(node); scenes.push({ board: { ...old?.board, id: boardId, title: n.title, fileName: `${n.title}.excalidraw`, projectId: project.id, nodeId: n.id, folderId: old?.board.folderId || null }, scene });
    }
    const next = { ...project, title: parsed.title, managed: true, nodes };
    let result;
    try { result = await this.w.store.commitProject(next, project.revision, parsed.source, scenes, { preserveDraft }); }
    catch (error) {
      if (error.code !== "PROJECT_CONFLICT") throw error;
      return this.fork(next, parsed.source, scenes);
    }
    await this.reconcile(result, scenes); return { ...result, source: parsed.source, warnings: parsed.warnings };
  }
  async fork(project, source, scenes) {
    const id = uid(), title = `${project.title} (recovered)`, byId = new Map();
    const copies = scenes.map(({ board, scene }) => { const copy = { ...board, id: uid(), projectId: id, title: board.title, fileName: `${board.title}.excalidraw` }; byId.set(board.id, copy.id); const cloned = structuredClone(scene); for (const e of cloned.elements) if (binding(e)) binding(e).projectId = id; return { board: copy, scene: cloned }; });
    const next = { ...project, id, title, deletedAt: null, revision: -1, nodes: project.nodes.map((n) => ({ ...n, boardId: byId.get(n.boardId) })) };
    source = setProjectTitle(source, title);
    const result = await this.w.store.commitProject(next, -1, source, copies);
    this.w.notice = "Another window changed this project. Your edits were kept in a recovered project.";
    await this.w.refresh(); return { ...result, source, conflict: true, boardMap: byId, scenes: copies };
  }
  async reconcile(result, scenes) {
    const saved = new Map(result.boards.map((b) => [b.id, b]));
    for (const s of [...this.w.sessions.values()]) {
      if (s.board.projectId !== result.project.id) continue;
      const b = saved.get(s.board.id);
      if (!b || b.deletedAt) { this.w.detach(s); continue; }
      const scene = scenes.find((x) => x.board.id === b.id)?.scene;
      if (scene && contentKey(scene) !== contentKey(s.ctrl.getScene())) {
        s.suppress = true;
        try {
          const restored = this.w.S.parseScene(scene);
          if (Object.keys(restored.files || {}).length) s.ctrl.api.addFiles(Object.values(restored.files));
          const tombstones = s.ctrl.api.getSceneElementsIncludingDeleted().filter((e) => e.isDeleted && !restored.elements.some((n) => n.id === e.id));
          s.ctrl.api.updateScene({ elements: [...restored.elements, ...tombstones], appState: { viewBackgroundColor: restored.appState.viewBackgroundColor }, captureUpdate: "NEVER" });
          await tick();
        } finally { s.suppress = false; }
      }
      s.board = b; s.projectRevision = result.project.revision; s.projectSnapshot = { ...result.project, source: this.w.projects.documents.find((d) => d.id === result.project.id)?.source }; s.savedKey = contentKey(s.ctrl.getScene());
      this.w.boards.set(b.id, b); await s.ctrl.set({ name: b.title });
    }
    await this.w.refresh();
    for (const s of this.w.sessions.values()) if (s.board.projectId === result.project.id) s.projectSnapshot = await this.w.store.project(result.project.id);
  }
  async saveCanvas(session, json, view) {
    return this.enqueue(session.board.projectId, async () => {
      const latest = await this.w.store.project(session.board.projectId);
      const removed = !latest || latest.deletedAt || !latest.nodes.some((n) => n.boardId === session.board.id);
      const project = removed && session.projectSnapshot?.source ? session.projectSnapshot : latest;
      if (!project?.managed) return this.w.store.save(session.board.id, session.board.revision, json, view);
      const node = project.nodes.find((n) => n.boardId === session.board.id);
      if (!node) throw new Error("This canvas is no longer in the project. Download it to retain your current work.");
      let source = project.source, scene = JSON.parse(json), parsed = parseMaster(source), heading = parsed.nodes.find((n) => n.id === node.id);
      const texts = scene.elements.filter((e) => e.type === "text" && !e.isDeleted), seen = new Set();
      for (const e of texts) {
        const meta = binding(e), value = e.originalText ?? e.text ?? "";
        if (meta?.nodeId === node.id) {
          seen.add(meta.blockId);
          if (meta.kind === "title") { if (heading.hidden) source = setNodeFlag(source, node.id, "hidden", false); if (value.trim() && value !== heading.title) source = renameNode(source, node.id, value); }
          else {
            const b = parseMaster(source).nodes.find((n) => n.id === node.id)?.blocks.find((b) => b.id === meta.blockId);
            if (!b || (!["image", "unsupported"].includes(b.kind) && b.text !== value)) source = setBlockText(source, node.id, meta.blockId, value);
          }
        } else if (value.trim()) {
          const tagged = tagAnnotation(e, project.id, node.id); Object.assign(e, tagged); seen.add(binding(tagged).blockId);
          source = appendText(source, node.id, value, binding(tagged).blockId);
        }
      }
      if (!heading.hidden && !seen.has("title")) source = setNodeFlag(source, node.id, "hidden");
      for (const b of heading.blocks) if (!["image", "unsupported"].includes(b.kind) && !seen.has(b.id)) source = removeBlock(source, node.id, b.id);
      const current = await this.w.store.board(session.board.id), unchanged = contentKey(json) === (session.savedKey || session.base);
      const stale = removed || (session.projectRevision !== undefined && session.projectRevision !== project.revision) || current.board.revision !== session.board.revision;
      if (stale && unchanged && source === project.source) {
        if (removed) return { board: current?.board || session.board, deleted: true };
        const all = await this.scenes(project); await this.reconcile({ project, boards: all.map((x) => x.board) }, all);
        return { board: current.board, projectRevision: project.revision };
      }
      if (stale) {
        const all = await this.scenes(project), incoming = all.map((x) => ({ board: x.board, scene: x.board.id === session.board.id ? scene : x.scene }));
        const result = await this.fork(project, source, incoming);
        const board = result.boards.find((b) => b.id === result.boardMap.get(session.board.id));
        return { board, scene: result.scenes.find((x) => x.board.id === board.id).scene, conflict: true, projectRevision: result.project.revision };
      }
      if (source === project.source && unchanged) {
        const board = await this.w.store.patch(session.board.id, { viewport: view });
        return { board, projectRevision: project.revision };
      }
      const result = await this.commit(project, source, { preserveDraft: true, incoming: { board: session.board, scene } });
      const board = result.boards.find((b) => b.id === (result.boardMap?.get(session.board.id) || session.board.id));
      return { board, scene: result.scenes?.find((x) => x.board.id === board.id)?.scene, conflict: Boolean(result.conflict), projectRevision: result.project.revision };
    });
  }
  async edit(id, transform, options = {}) {
    return this.enqueue(id, async () => {
      const p = await this.w.store.project(id); if (!p?.managed) throw new Error("Link this project to Markdown first.");
      if (p.draft !== null) throw new Error("Apply or discard the master Markdown draft before changing the outline.");
      return this.commit(p, transform(p.source), options);
    });
  }
  async addCanvas(id, title = "New canvas", parentId = null, scene = null) {
    const nodeId = uid(), overrides = new Map();
    if (scene) overrides.set(nodeId, { board: { id: uid(), title }, scene });
    const result = await this.edit(id, (source) => addNode(source, title, parentId, nodeId), { overrides });
    const n = result.project.nodes.find((n) => n.id === nodeId); return this.w.store.board(n.boardId);
  }
  async adoptLegacy(id) {
    const p = await this.w.store.project(id), boards = [...this.w.boards.values()].filter((b) => b.projectId === id && !b.deletedAt);
    let source = `---\ntitle: ${JSON.stringify(p.title)}\n---\n`, overrides = new Map(), folders = [...this.w.folders];
    const folderNodes = new Map();
    const addFolder = (folderId) => {
      if (!folderId) return null;
      if (folderNodes.has(folderId)) return folderNodes.get(folderId);
      const f = folders.find((f) => f.id === folderId); if (!f) return null;
      const parent = addFolder(f.parentId), nodeId = uid(); source = addNode(parseMaster(source, { assignIds: true }).source, f.title, parent, nodeId); folderNodes.set(folderId, nodeId); return nodeId;
    };
    for (const b of boards) {
      const parent = addFolder(b.folderId), nodeId = uid(); source = addNode(parseMaster(source, { assignIds: true }).source, b.title, parent, nodeId); source = setNodeFlag(source, nodeId, "hidden");
      const data = await this.w.store.board(b.id), pairs = new Map();
      for (const e of data.scene.elements) if (e.type === "text" && !e.isDeleted) { const blockId = `text_${e.id}`; pairs.set(e.id, blockId); source = appendText(source, nodeId, e.originalText || e.text || "", blockId); }
      overrides.set(nodeId, { board: b, scene: adoptText(data.scene, id, nodeId, pairs) });
    }
    return this.enqueue(id, () => this.commit({ ...p, managed: true }, source, { overrides }));
  }
  async trashProject(id, restore = false) {
    return this.enqueue(id, async () => {
      const p = await this.w.store.project(id); if (!p) throw new Error("Project not found.");
      if (!p.managed) throw new Error("My sketches is retained as the home for ordinary drawings. Move or trash its drawings individually.");
      const scenes = (await this.scenes(p)).map(({ board, scene }) => ({ board, scene }));
      const result = await this.w.store.commitProject({ ...p, deletedAt: restore ? null : Date.now() }, p.revision, p.source, scenes, { preserveDraft: true });
      if (!restore) for (const s of [...this.w.sessions.values()]) if (s.board.projectId === id) this.w.detach(s);
      await this.w.refresh(); return result;
    });
  }
  async restoreVersion(id, versionId) {
    return this.enqueue(id, async () => {
      const p = await this.w.store.project(id), v = await this.w.store.projectVersion(versionId);
      for (const item of v.scenes) { const current = await this.w.store.board(item.board.id); if (current) item.board.revision = current.board.revision; }
      const result = await this.w.store.commitProject({ ...v.project, id, resourceFiles: v.resourceFiles, deletedAt: null }, p.revision, v.document?.source || "", v.scenes);
      await this.reconcile(result, v.scenes); return result;
    });
  }
  async duplicateProject(id) {
    const p = await this.w.store.project(id); if (!p?.managed) throw new Error("Link the project to Markdown before duplicating it.");
    const scenes = await this.scenes(p), newId = uid(), title = `${p.title} copy`, source = setProjectTitle(p.source, title);
    const copies = scenes.map(({ board, scene }) => ({ board: { ...board, id: uid(), projectId: newId }, scene: structuredClone(scene) }));
    const map = new Map(scenes.map((s, i) => [s.board.id, copies[i].board.id]));
    const result = await this.w.store.commitProject({ ...p, id: newId, title, revision: -1, nodes: p.nodes.map((n) => ({ ...n, boardId: map.get(n.boardId) })) }, -1, source, copies);
    await this.w.refresh(); return result;
  }
  async duplicateCanvas(id, nodeId) {
    const p = await this.w.store.project(id), before = parseMaster(p.source), source = duplicateNode(p.source, nodeId), after = parseMaster(source);
    const fresh = after.nodes.filter((n) => !before.nodes.some((x) => x.id === n.id));
    const range = before.nodes.filter((n) => n.id === nodeId || (() => { let parent = n.parentId; while (parent) { if (parent === nodeId) return true; parent = before.nodes.find((x) => x.id === parent)?.parentId; } return false; })());
    const overrides = new Map();
    for (let i = 0; i < fresh.length; i++) {
      const original = p.nodes.find((n) => n.id === range[i].id), data = await this.w.store.board(original.boardId), copy = cloneScene(data.scene, id, fresh[i].id);
      const oldBlocks = range[i].blocks, newBlocks = fresh[i].blocks, ids = new Map(oldBlocks.map((b, j) => [b.id, newBlocks[j]?.id]));
      for (const e of copy.elements) { const m = binding(e); if (m && m.blockId !== "title" && ids.has(m.blockId)) m.blockId = ids.get(m.blockId); }
      overrides.set(fresh[i].id, { board: { ...data.board, id: uid(), title: fresh[i].title }, scene: copy });
    }
    return this.apply(id, source, { overrides });
  }
}
export { renameNode, setProjectTitle, setNodeFlag, moveNode, removeNode };
