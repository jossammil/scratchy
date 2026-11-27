// The project explorer, master Markdown tabs, and the project, canvas,
// history, trash and export dialogs. Project rules live in manager.js.
import {
  ProjectManager,
  renameNode,
  setProjectTitle,
  setNodeFlag,
  moveNode,
  removeNode,
} from "./manager.js";
import { parseMaster } from "./markdown.js";
import { projectArchive } from "./archive.js";
import { deckSnapshot, exportPDF, exportPowerPoint } from "../presentations/export.js";
import { present } from "../presentations/presenter.js";
import { el, html } from "../dom.js";

const btn = (label, action, cls) => {
  const b = el("button", label, cls);
  b.type = "button";
  b.onclick = action;
  return b;
};
const fileData = (file) =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
// The explorer sidebar and the master Markdown editor.
const SIDEBAR = html`
  <div class="project-sidebar-head">
    <strong>Projects</strong>
    <button type="button" id="project-create">＋ Project</button>
  </div>
  <input
    type="search"
    id="project-search"
    aria-label="Search projects and canvases"
    placeholder="Find a canvas…"
  />
  <nav id="project-tree" aria-label="Projects and canvases"></nav>
  <div class="project-sidebar-foot">
    <button type="button" id="project-import">Import Markdown…</button>
    <button type="button" id="project-trash">Project trash</button>
  </div>
  <div
    class="project-resizer"
    role="separator"
    tabindex="0"
    aria-label="Resize project explorer"
    aria-orientation="vertical"
  ></div>
`;

const MASTER = html`
  <div class="master-toolbar">
    <strong id="master-title">Master Markdown</strong>
    <button type="button" id="master-apply">Apply to canvases</button>
    <button type="button" id="master-discard">Discard draft</button>
    <button type="button" id="master-save">Download .md</button>
    <button type="button" id="master-image">Add image…</button>
  </div>
  <p id="master-preview" role="status"></p>
  <div id="master-conflict" hidden>
    <p>The canvases changed after this draft began. Compare with the current source below.</p>
    <button type="button" id="master-keep">Keep current source</button>
    <button type="button" id="master-force">Apply this draft</button>
    <pre id="master-current"></pre>
  </div>
  <label class="sr-only" for="master-text">Master Markdown source</label>
  <textarea id="master-text" spellcheck="false"></textarea>
  <p class="master-help">
    Each heading is a canvas and slide. Keep the Scratchy ID comments to preserve your drawings when
    rearranging headings. Preview the changes, then apply.
  </p>
`;

export class ProjectUI {
  constructor(w) {
    this.w = w;
    this.manager = new ProjectManager(w);
    this.items = [];
    this.documents = [];
    this.sourceTabs = [];
    this.expanded = new Set();
    const editors = w.$("ws-editors"),
      empty = w.$("ws-empty");
    this.body = el("div", undefined, "ws-body");
    this.sidebar = el("aside", undefined, "project-sidebar");
    this.sidebar.setAttribute("aria-label", "Project explorer");
    this.main = el("main", undefined, "project-main");
    this.bar = el("div", undefined, "project-bar");
    this.main.append(this.bar, editors, empty);
    this.body.append(this.sidebar, this.main);
    w.$("ws-top")?.after(this.body);
    if (!this.body.isConnected) w.root.querySelector("header").after(this.body);
    const toggle = btn("☰", () => this.toggle());
    toggle.setAttribute("aria-label", "Toggle project explorer");
    w.root.querySelector("header").prepend(toggle);
    this.sidebar.innerHTML = SIDEBAR;
    this.sourceHost = el("section", undefined, "master-document");
    this.sourceHost.id = "project-master";
    this.sourceHost.hidden = true;
    this.sourceHost.setAttribute("role", "tabpanel");
    this.sourceHost.innerHTML = MASTER;
    this.main.append(this.sourceHost);
    this.$ = (id) => w.root.querySelector(`#${id}`);
    this.$("project-create").onclick = () => w.run(() => this.create());
    this.$("project-import").onclick = () => w.pick(".md", (file) => this.importMarkdown(file));
    this.$("project-trash").onclick = () => w.run(() => this.trash());
    this.$("project-search").oninput = () => this.renderTree();
    this.$("master-text").oninput = () => {
      if (!this.dirty) this.draftBase = this.current()?.revision;
      this.dirty = true;
      clearTimeout(this.timer);
      this.timer = setTimeout(() => w.run(() => this.saveDraft()), 300);
      this.preview();
      w.renderStatus();
    };
    this.$("master-apply").onclick = () => w.run(() => this.apply());
    this.$("master-force").onclick = () => w.run(() => this.apply(true));
    this.$("master-discard").onclick = this.$("master-keep").onclick = () =>
      w.run(() => this.discard());
    this.$("master-save").onclick = () => this.saveMaster();
    this.$("master-image").onclick = () => w.pick("image/*", (file) => this.addImage(file));
    window.addEventListener(
      "keydown",
      (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === "\\") {
          e.preventDefault();
          this.toggle();
        }
      },
      true,
    );
    const resize = this.sidebar.querySelector(".project-resizer");
    resize.onpointerdown = (e) => {
      resize.setPointerCapture(e.pointerId);
      resize.onpointermove = (event) =>
        this.width(event.clientX - w.root.getBoundingClientRect().left);
      resize.onpointerup = () => {
        resize.onpointermove = null;
        w.run(() => w.persistLayout());
      };
    };
    resize.onkeydown = (e) => {
      if (!["ArrowLeft", "ArrowRight"].includes(e.key)) return;
      e.preventDefault();
      this.width((this.sidebarWidth || 280) + (e.key === "ArrowRight" ? 20 : -20));
      w.run(() => w.persistLayout());
    };
  }
  update(projects, documents) {
    this.items = projects || [];
    this.documents = documents || [];
  }
  restore(state) {
    this.collapsed = state.sidebarCollapsed ?? matchMedia("(max-width: 760px)").matches;
    this.expanded = new Set(state.projectExpanded || this.items.map((p) => p.id));
    this.width(state.sidebarWidth || 280);
    this.sourceTabs = (state.tabs || [])
      .filter((t) => t.kind === "markdown" && this.items.some((p) => p.id === t.id && !p.deletedAt))
      .map((t) => t.id);
    this.selectedId = state.selectedProject || null;
    this.body.classList.toggle("sidebar-collapsed", this.collapsed);
  }
  layout() {
    return {
      sidebarCollapsed: Boolean(this.collapsed),
      sidebarWidth: this.sidebarWidth || 280,
      projectExpanded: [...this.expanded],
      selectedProject: this.selectedId || null,
      activeDocument: this.documentId || null,
      tabs: [
        ...this.w.openIds.map((id) => ({ kind: "canvas", id })),
        ...this.sourceTabs.map((id) => ({ kind: "markdown", id })),
      ],
    };
  }
  width(value) {
    this.sidebarWidth = Math.max(220, Math.min(480, value));
    this.body.style.setProperty("--project-width", `${this.sidebarWidth}px`);
  }
  toggle() {
    this.collapsed = !this.collapsed;
    this.body.classList.toggle("sidebar-collapsed", this.collapsed);
    this.w.run(() => this.w.persistLayout());
    requestAnimationFrame(() => this.w.active?.ctrl.refresh());
  }
  current() {
    return (
      this.items.find(
        (p) =>
          p.id ===
          (this.documentId || this.selectedId || this.w.boards.get(this.w.activeId)?.projectId),
      ) || this.items.find((p) => p.id === "my-sketches")
    );
  }
  node() {
    const p = this.current();
    return p?.nodes.find((n) => n.boardId === this.w.activeId);
  }
  async create(source, title) {
    if (!title) title = prompt("Project name", "New project")?.trim();
    if (!title) return;
    await this.w.flushAll();
    const result = await this.manager.create(title, source);
    this.selectedId = result.project.id;
    this.expanded.add(result.project.id);
    if (result.boards[0]) await this.w.switchTo(result.boards[0].id);
    else await this.showMaster(result.project.id);
  }
  async importMarkdown(file) {
    const source = await file.text(),
      parsed = parseMaster(source, { assignIds: true });
    const title =
      parsed.title === "Untitled project" ? file.name.replace(/\.md$/i, "") : parsed.title;
    return this.create(setProjectTitle(parsed.source, title), title);
  }
  async activateCanvas(id) {
    await this.saveDraft();
    this.documentId = null;
    this.sourceHost.hidden = true;
    this.selectedId = this.w.boards.get(id)?.projectId;
    const p = this.items.find((p) => p.id === this.selectedId);
    if (p) {
      this.expanded.add(p.id);
      let node = p.nodes.find((n) => n.boardId === id);
      while (node?.parentId) {
        this.expanded.add(node.parentId);
        node = p.nodes.find((n) => n.id === node.parentId);
      }
    }
  }
  async showMaster(id) {
    await this.saveDraft();
    await this.w.flushAll();
    const p = await this.w.store.project(id);
    if (!p?.managed) throw new Error("Link My sketches to Markdown to edit its master source.");
    this.documentId = id;
    this.selectedId = id;
    if (!this.sourceTabs.includes(id)) this.sourceTabs.push(id);
    for (const s of this.w.sessions.values()) s.host.hidden = true;
    this.sourceHost.hidden = false;
    this.$("master-text").value = p.draft ?? p.source;
    this.dirty = p.draft !== null;
    this.draftBase = p.draftBase ?? p.revision;
    this.preview();
    this.w.render();
    await this.w.persistLayout();
    this.$("master-text").focus();
  }
  async closeMaster(id) {
    const active = this.documentId === id;
    if (active) {
      await this.saveDraft();
      this.documentId = null;
      this.sourceHost.hidden = true;
    }
    this.sourceTabs = this.sourceTabs.filter((x) => x !== id);
    if (active && this.w.activeId) await this.w.activate(this.w.activeId);
    await this.w.persistLayout();
    this.w.render();
  }
  async saveDraft() {
    clearTimeout(this.timer);
    this.timer = null;
    if (this.documentId && this.dirty) {
      const source = this.$("master-text").value;
      await this.w.store.draft(this.documentId, source, this.draftBase);
    }
  }
  preview() {
    const p = this.current();
    if (!p) return;
    this.$("master-title").textContent = `${p.title} / project.md`;
    const input = this.$("master-text").value,
      info = this.$("master-preview");
    try {
      const parsed = parseMaster(input),
        added = parsed.nodes.filter((n) => !p.nodes.some((x) => x.id === n.id)).length,
        removed = p.nodes.filter((n) => !parsed.nodes.some((x) => x.id === n.id)).length;
      info.textContent = `${this.dirty ? "Draft saved in this browser · " : ""}${parsed.nodes.length} canvases · ${added} new · ${removed} removed${parsed.warnings.length ? ` · ${parsed.warnings.join(" ")}` : ""}`;
      info.classList.remove("ws-error");
      this.$("master-apply").disabled = false;
    } catch (e) {
      info.textContent = `Draft retained. ${e.message}`;
      info.classList.add("ws-error");
      this.$("master-apply").disabled = true;
    }
    this.$("master-discard").disabled = !this.dirty;
    const conflict = this.dirty && this.draftBase !== p.revision;
    this.$("master-conflict").hidden = !conflict;
    if (conflict)
      this.$("master-current").textContent =
        this.documents.find((d) => d.id === p.id)?.source || "";
  }
  async apply(force = false) {
    const input = this.$("master-text");
    input.readOnly = true;
    try {
      await this.saveDraft();
      const id = this.documentId,
        result = await this.manager.apply(id, input.value, {
          force,
          resources: this.pendingResources,
        });
      this.pendingResources = null;
      this.documentId = result.project.id;
      this.selectedId = result.project.id;
      if (!this.sourceTabs.includes(result.project.id)) this.sourceTabs.push(result.project.id);
      input.value = result.source;
      this.draftBase = result.project.revision;
      this.dirty = false;
      this.w.notice = "Master Markdown applied. Existing drawings and positions were preserved.";
      this.w.render();
      await this.w.persistLayout();
    } finally {
      input.readOnly = false;
    }
  }
  async discard() {
    clearTimeout(this.timer);
    this.timer = null;
    const input = this.$("master-text");
    input.readOnly = true;
    try {
      const id = this.documentId;
      await this.w.store.draft(id, null, null);
      const p = await this.w.store.project(id);
      input.value = p.source;
      this.pendingResources = null;
      this.draftBase = p.revision;
      this.dirty = false;
      this.w.render();
    } finally {
      input.readOnly = false;
    }
  }
  saveMaster() {
    if (this.documentId)
      this.w.download(
        "project.md",
        new Blob([this.$("master-text").value], { type: "text/markdown" }),
      );
  }
  async addImage(file) {
    if (!this.documentId) return;
    if (!/^image\/(png|jpeg|webp|gif|svg\+xml)$/.test(file.type))
      throw new Error("Choose a PNG, JPEG, WebP, GIF or SVG image.");
    const p = await this.w.store.project(this.documentId),
      path = `assets/${Date.now()}-${file.name.replace(/[^\w.-]/g, "-")}`;
    this.pendingResources = {
      ...(this.pendingResources || p.resourceFiles),
      [path]: { id: path, mimeType: file.type, dataURL: await fileData(file), created: Date.now() },
    };
    this.$("master-text").value += `\n![${file.name.replace(/[\[\]]/g, "")}](${path})\n`;
    this.$("master-text").dispatchEvent(new Event("input"));
    // The source and image commit together, so a reload cannot leave a broken reference.
    await this.apply();
  }
  render() {
    this.renderTree();
    this.renderBar();
    for (const id of this.sourceTabs) {
      const p = this.items.find((p) => p.id === id && !p.deletedAt);
      if (!p) continue;
      const tab = el("div", undefined, "ws-tab"),
        open = btn(`${p.title}${p.importedFromId ? " (restored)" : ""} · .md`, () =>
          this.w.run(() => this.showMaster(id)),
        );
      open.setAttribute("role", "tab");
      open.setAttribute("aria-selected", String(this.documentId === id));
      open.setAttribute("aria-controls", "project-master");
      open.dataset.projectId = id;
      tab.append(
        open,
        btn("×", () => this.w.run(() => this.closeMaster(id))),
      );
      this.w.$("ws-tabs").append(tab);
    }
    if (this.documentId) {
      this.w.$("ws-empty").hidden = true;
      this.preview();
    }
  }
  /** The window title and save status while a master Markdown tab is shown. */
  status() {
    if (!this.documentId) return null;
    return {
      title: `${this.current()?.title} · Markdown · scratchy`,
      text: this.dirty
        ? "Markdown draft saved in this browser · Apply to update canvases"
        : "Master Markdown saved in this browser",
    };
  }
  renderTree() {
    const tree = this.$("project-tree"),
      query = this.$("project-search").value.trim().toLowerCase();
    const signature = JSON.stringify([
      this.items,
      [...this.w.boards.values()].map((b) => [b.id, b.title, b.deletedAt, b.folderId]),
      this.w.folders,
      [...this.expanded],
      this.selectedId,
      this.w.activeId,
      this.documentId,
      query,
    ]);
    if (signature === this.treeSignature) return;
    this.treeSignature = signature;
    tree.replaceChildren();
    const projects = this.items
      .filter((p) => !p.deletedAt)
      .sort((a, b) => a.createdAt - b.createdAt);
    for (const p of projects) {
      const boards = [...this.w.boards.values()].filter(
        (b) => b.projectId === p.id && !b.deletedAt,
      );
      const matches = (title) => title.toLowerCase().includes(query);
      if (query && !matches(p.title) && !boards.some((b) => matches(b.title))) continue;
      this.projectRow(tree, p, boards);
      if (!this.expanded.has(p.id) && !query) continue;
      if (p.managed) this.outlineRows(tree, p, query);
      else this.folderRows(tree, boards, query, null, 1);
    }
  }
  /** One explorer row: an expand chevron, the label and an optional actions button. */
  treeRow(tree, { label, depth, selected, open, key, children, menu }) {
    const wrap = el("div", undefined, `project-tree-row${selected ? " selected" : ""}`);
    wrap.style.setProperty("--depth", depth);
    const expanded = this.expanded.has(key);
    const chevron = btn(children ? (expanded ? "▾" : "▸") : "·", () => {
      if (this.expanded.has(key)) this.expanded.delete(key);
      else this.expanded.add(key);
      this.renderTree();
      this.w.run(() => this.w.persistLayout());
    });
    chevron.setAttribute("aria-label", `${expanded ? "Collapse" : "Expand"} ${label}`);
    if (children) chevron.setAttribute("aria-expanded", String(expanded));
    else chevron.disabled = true;
    const main = btn(label, () => this.w.run(open), "project-tree-label");
    main.title = label;
    wrap.append(chevron, main);
    if (menu) {
      const more = btn("⋯", () => this.w.run(menu));
      more.setAttribute("aria-label", `Actions for ${label}`);
      wrap.append(more);
    }
    tree.append(wrap);
    return wrap;
  }
  /** Accepts a dragged section, nesting it under parentId (the project root when null). */
  dropTarget(row, p, parentId = null) {
    row.ondragover = (e) => e.preventDefault();
    row.ondrop = (e) => {
      e.preventDefault();
      e.stopPropagation();
      const data = e.dataTransfer.getData("application/x-scratchy-node");
      if (!data) return;
      const [projectId, nodeId] = JSON.parse(data);
      if (projectId === p.id) {
        this.w.run(() => this.manager.edit(p.id, (s) => moveNode(s, nodeId, parentId)));
      }
    };
  }
  projectRow(tree, p, boards) {
    const row = this.treeRow(tree, {
      label: p.importedFromId ? `${p.title} (restored)` : p.title,
      depth: 0,
      selected: this.selectedId === p.id && !this.node(),
      open: async () => {
        this.selectedId = p.id;
        this.expanded.add(p.id);
        const first = p.nodes[0]?.boardId || boards[0]?.id;
        if (first) await this.w.switchTo(first);
        else this.w.render();
      },
      key: p.id,
      children: true,
      menu: () => this.projectMenu(p.id),
    });
    row.dataset.projectId = p.id;
    this.dropTarget(row, p);
  }
  /** The canvases of a Markdown project, nested by heading level. */
  outlineRows(tree, p, query) {
    const byId = new Map(p.nodes.map((n) => [n.id, n]));
    const visible = (n) => {
      for (let parent = n.parentId; parent; parent = byId.get(parent)?.parentId) {
        if (!this.expanded.has(parent) && !query) return false;
      }
      return true;
    };
    const depth = (n) => (n.parentId ? 1 + depth(byId.get(n.parentId)) : 1);
    const matches = (title) => title.toLowerCase().includes(query);
    for (const n of p.nodes) {
      if (!visible(n) || (query && !matches(n.title) && !matches(p.title))) continue;
      const row = this.treeRow(tree, {
        label: `${n.include ? "" : "○ "}${n.title}`,
        depth: depth(n),
        selected: !this.documentId && this.w.activeId === n.boardId,
        open: () => this.w.switchTo(n.boardId),
        key: n.id,
        children: p.nodes.some((x) => x.parentId === n.id),
        menu: () => this.nodeMenu(p.id, n.id),
      });
      row.dataset.nodeId = n.id;
      row.draggable = true;
      row.ondragstart = (e) =>
        e.dataTransfer.setData("application/x-scratchy-node", JSON.stringify([p.id, n.id]));
      this.dropTarget(row, p, n.id);
    }
  }
  /** Ordinary drawings (My sketches), in their legacy folders. */
  folderRows(tree, boards, query, parent, depth) {
    for (const f of this.w.folders.filter((f) => f.parentId === parent)) {
      this.treeRow(tree, {
        label: f.title,
        depth,
        selected: false,
        open: () => {
          if (this.expanded.has(f.id)) this.expanded.delete(f.id);
          else this.expanded.add(f.id);
          this.renderTree();
        },
        key: f.id,
        children: true,
      });
      if (this.expanded.has(f.id) || query) this.folderRows(tree, boards, query, f.id, depth + 1);
    }
    const here = boards.filter(
      (b) => b.folderId === parent && (!query || b.title.toLowerCase().includes(query)),
    );
    for (const b of here) {
      this.treeRow(tree, {
        label: b.title,
        depth,
        selected: !this.documentId && b.id === this.w.activeId,
        open: () => this.w.switchTo(b.id),
        key: b.id,
        children: false,
        menu: () => this.w.showCollection(),
      });
    }
  }
  renderBar() {
    const p = this.current(),
      n = this.node();
    this.bar.replaceChildren();
    if (!p) return;
    this.bar.append(
      el("span", `${p.title}${n && !this.documentId ? ` / ${n.title}` : ""}`, "project-breadcrumb"),
    );
    if (!p.managed) {
      this.bar.append(
        btn("Link to Markdown…", () =>
          this.w.run(async () => {
            await this.w.flushAll();
            await this.manager.adoptLegacy(p.id);
            await this.showMaster(p.id);
          }),
        ),
      );
      return;
    }
    this.bar.append(
      btn("＋ Canvas", () =>
        this.w.run(async () => {
          const b = await this.manager.addCanvas(p.id);
          await this.w.switchTo(b.board.id);
        }),
      ),
      btn("Source", () => this.w.run(() => this.showMaster(p.id))),
      btn("Present", () => this.w.run(() => this.export(p.id, "present"))),
      btn("Export…", () => this.w.run(() => this.exportMenu(p.id))),
    );
  }
  async dialog(title, build) {
    const d = el("dialog", undefined, "project-dialog"),
      head = el("div", undefined, "ws-dialog-head");
    head.append(
      el("h2", title),
      btn("Close", () => d.close()),
    );
    d.append(head);
    const body = el("div", undefined, "project-dialog-body");
    d.append(body);
    this.w.root.append(d);
    await build(body, d);
    d.showModal();
    d.addEventListener("close", () => d.remove(), { once: true });
    return d;
  }
  async projectMenu(id) {
    const p = this.items.find((p) => p.id === id);
    return this.dialog(p.title, (body, d) => {
      if (!p.managed) {
        body.append(
          el(
            "p",
            "Your original drawings retain their appearance. Link them to a master Markdown document to use the outline and slides.",
          ),
          btn("Link to Markdown", () =>
            this.w.run(async () => {
              d.close();
              await this.w.flushAll();
              await this.manager.adoptLegacy(id);
              await this.showMaster(id);
            }),
          ),
        );
        return;
      }
      const action = (label, fn) =>
        body.append(
          btn(label, () =>
            this.w.run(async () => {
              d.close();
              await this.w.flushAll();
              await this.saveDraft();
              await fn();
            }),
          ),
        );
      action("Rename project", async () => {
        const title = prompt("Project name", p.title)?.trim();
        if (title) await this.manager.edit(id, (s) => setProjectTitle(s, title));
      });
      action("Duplicate project", () => this.manager.duplicateProject(id));
      action("Master Markdown", () => this.showMaster(id));
      action("Project history", () => this.history(id));
      action("Export project…", () => this.exportMenu(id));
      action("Move project to trash", async () => {
        await this.manager.trashProject(id);
        this.sourceTabs = this.sourceTabs.filter((x) => x !== id);
        if (this.documentId === id) {
          this.documentId = null;
          this.sourceHost.hidden = true;
        }
        this.selectedId = null;
        await this.w.persistLayout();
        this.w.render();
      });
    });
  }
  async nodeMenu(id, nodeId) {
    const p = this.items.find((p) => p.id === id),
      n = p.nodes.find((n) => n.id === nodeId);
    return this.dialog(n.title, (body, d) => {
      const action = (label, fn) =>
        body.append(
          btn(label, () =>
            this.w.run(async () => {
              d.close();
              await this.w.flushAll();
              await fn();
            }),
          ),
        );
      action("Rename canvas", async () => {
        const title = prompt("Canvas name", n.title)?.trim();
        if (title) await this.manager.edit(id, (s) => renameNode(s, nodeId, title));
      });
      action("Add child canvas", async () => {
        this.expanded.add(nodeId);
        const data = await this.manager.addCanvas(id, "New canvas", nodeId);
        await this.w.switchTo(data.board.id);
      });
      action("Duplicate section", () => this.manager.duplicateCanvas(id, nodeId));
      action("Move section…", () => this.move(id, nodeId));
      action(n.include ? "Exclude from slides" : "Include in slides", () =>
        this.manager.edit(id, (s) => setNodeFlag(s, nodeId, "excluded", n.include)),
      );
      action(n.hidden ? "Show canvas title" : "Hide canvas title", () =>
        this.manager.edit(id, (s) => setNodeFlag(s, nodeId, "hidden", !n.hidden)),
      );
      action("Reflow Markdown text", () => this.manager.edit(id, (s) => s, { reflow: true }));
      action("Present this section", () => this.export(id, "present", nodeId));
      action("Trash this section", () => this.manager.edit(id, (s) => removeNode(s, nodeId)));
    });
  }
  async move(id, nodeId) {
    const p = this.items.find((p) => p.id === id);
    return this.dialog("Move section", (body, d) => {
      const parent = el("select"),
        before = el("select");
      parent.setAttribute("aria-label", "New parent section");
      before.setAttribute("aria-label", "Place before section");
      for (const select of [parent, before]) {
        const o = el("option", select === parent ? "Project root" : "At end");
        o.value = "";
        select.append(o);
        for (const n of p.nodes.filter((n) => n.id !== nodeId)) {
          const o = el("option", `${"—".repeat(n.level - 1)} ${n.title}`);
          o.value = n.id;
          select.append(o);
        }
      }
      body.append(
        el("label", "Parent"),
        parent,
        el("label", "Place before a sibling (optional)"),
        before,
        btn("Move", () =>
          this.w.run(async () => {
            const sibling = p.nodes.find((n) => n.id === before.value);
            if (sibling && sibling.parentId !== (parent.value || null))
              throw new Error("Choose a sibling within the selected parent.");
            await this.manager.edit(id, (s) =>
              moveNode(s, nodeId, parent.value || null, before.value || null),
            );
            d.close();
          }),
        ),
      );
    });
  }
  async history(id) {
    const versions = await this.w.store.projectHistory(id);
    return this.dialog("Project history", (body, d) => {
      body.append(
        el(
          "p",
          "Restoring recovers the master, outline, canvases and images together. Up to 50 project versions are retained.",
        ),
      );
      if (!versions.length) body.append(el("p", "No earlier project versions yet."));
      for (const v of versions) {
        const details = el("details"),
          summary = el(
            "summary",
            `${new Date(v.createdAt).toLocaleString()} · ${v.project.nodes.length} canvases`,
          );
        details.append(
          summary,
          el("pre", v.document?.source || "Original drawings"),
          btn("Restore project version", () =>
            this.w.run(async () => {
              await this.w.flushAll();
              await this.manager.restoreVersion(id, v.id);
              this.dirty = false;
              d.close();
              if (this.documentId === id) await this.showMaster(id);
            }),
          ),
        );
        body.append(details);
      }
    });
  }
  async trash() {
    return this.dialog("Project trash · kept for 30 days", (body, d) => {
      const projects = this.items.filter((p) => p.deletedAt);
      if (!projects.length) body.append(el("p", "No projects in trash."));
      for (const p of projects)
        body.append(
          btn(`Restore ${p.title}`, () =>
            this.w.run(async () => {
              await this.manager.trashProject(p.id, true);
              d.close();
              this.selectedId = p.id;
              this.w.render();
            }),
          ),
        );
    });
  }
  async boardAction(action, board) {
    const p = this.items.find((p) => p.id === board.projectId);
    if (!p?.managed || action === "pin") return false;
    const n = p.nodes.find((n) => n.boardId === board.id);
    if (!n) {
      if (action === "restore") {
        await this.history(p.id);
        return true;
      }
      throw new Error("Restore a removed section through project history.");
    }
    await this.w.flushAll();
    if (action === "rename") {
      const title = prompt("Canvas name", n.title)?.trim();
      if (title) await this.manager.edit(p.id, (s) => renameNode(s, n.id, title));
    }
    if (action === "duplicate") await this.manager.duplicateCanvas(p.id, n.id);
    if (action === "move") await this.move(p.id, n.id);
    if (action === "trash") await this.manager.edit(p.id, (s) => removeNode(s, n.id));
    if (action === "history" || action === "restore") await this.history(p.id);
    return true;
  }
  async exportMenu(id) {
    return this.dialog("Export project", (body, d) => {
      const label = el("label"),
        portable = el("input");
      portable.type = "checkbox";
      label.append(portable, document.createTextNode(" Use Arial for editable PowerPoint text"));
      body.append(
        label,
        el(
          "p",
          "PowerPoint keeps text editable and embeds drawings as images. PDF preserves the rendered canvas. ZIP contains project.md, canvases and images.",
        ),
      );
      for (const [kind, name] of [
        ["pptx", "PowerPoint (.pptx)"],
        ["pdf", "PDF slides"],
        ["zip", "Portable project ZIP"],
      ])
        body.append(
          btn(name, () =>
            this.w.run(async () => {
              d.close();
              await this.export(id, kind, null, portable.checked);
            }),
          ),
        );
    });
  }
  async export(id, kind, subtree = null, portable = false) {
    await this.saveDraft();
    if (kind === "zip") {
      const p = this.items.find((p) => p.id === id);
      return this.w.download(
        `${p.title.replace(/[^\w.-]/g, "-")}.zip`,
        await projectArchive(this.w, id),
      );
    }
    const deck = await deckSnapshot(this.w, id, subtree);
    if (deck.overflow.length) {
      const proceed = await new Promise((resolve) =>
        this.dialog("Content outside slide frames", (body, d) => {
          body.append(
            el(
              "p",
              `These canvases have content outside their slide frame: ${deck.overflow.map((x) => x.title).join(", ")}. That content is clipped in the presentation.`,
            ),
            btn("Continue with slide frames", () => {
              resolve(true);
              d.close();
            }),
          );
          d.addEventListener("close", () => resolve(false), { once: true });
        }),
      );
      if (!proceed) return;
    }
    if (kind === "present") return present(this.w, deck);
    this.w.notice = `Preparing ${kind.toUpperCase()}…`;
    this.w.renderStatus();
    const blob =
      kind === "pptx"
        ? await exportPowerPoint(this.w.S, deck, { portableFonts: portable })
        : await exportPDF(this.w.S, deck);
    this.w.download(`${deck.title.replace(/[^\w.-]/g, "-")}.${kind}`, blob);
    this.w.notice = `${kind.toUpperCase()} exported · ${deck.slides.length} slides`;
    this.w.renderStatus();
    return blob;
  }
}
