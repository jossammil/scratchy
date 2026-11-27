// The standalone site's multi-board workspace: open tabs with their own
// editor sessions, the All boards collection, history, trash and backups.
import { openWorkspace } from "./storage.js";
import { createBackup, readBackup } from "./backup.js";
import {
  emptyScene,
  contentKey,
  viewport,
  searchBoards,
  folderDescendants,
  TRASH_RETENTION,
} from "./model.js";
import "./workspace.css";
import { ProjectUI } from "./projects/ui.js";
import { el, html } from "./dom.js";

const button = (text, action, label = text) => {
  const b = el("button", text);
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.addEventListener("click", action);
  return b;
};
const frame = () => new Promise(requestAnimationFrame);
const PICKERS = [
  {
    description: "Excalidraw drawings",
    accept: {
      "application/vnd.excalidraw+json": [".excalidraw"],
      "text/markdown": [".md"],
      "image/svg+xml": [".svg"],
      "image/png": [".png"],
      "application/vnd.excalidrawlib+json": [".excalidrawlib"],
    },
  },
];

// The workspace chrome: tabs, editors, status bar and its dialogs.
const SHELL = html`
  <header class="ws-top">
    <button type="button" id="ws-all">All boards</button>
    <div id="ws-tabs" role="tablist" aria-label="Open drawings"></div>
    <button type="button" id="ws-new" aria-label="New drawing">＋</button>
    <select id="ws-actions" aria-label="Board actions">
      <option value="">Board…</option>
      <option value="rename">Rename</option>
      <option value="duplicate">Duplicate</option>
      <option value="move">Move to folder</option>
      <option value="pin">Pin / unpin</option>
      <option value="history">Version history</option>
      <option value="trash">Move to trash</option>
    </select>
  </header>
  <div id="ws-editors"></div>
  <div id="ws-empty" hidden>
    <h1>Your drawings, together.</h1>
    <p>Open a saved board or start a new drawing.</p>
  </div>
  <footer class="ws-status">
    <span id="ws-save-status" role="status" aria-live="polite"></span>
    <span id="ws-backup-status"></span>
    <button type="button" id="ws-retry" hidden>Retry save</button>
    <button type="button" id="ws-recover" hidden>Download current drawing</button>
  </footer>
  <dialog id="ws-collection" aria-labelledby="ws-collection-title">
    <div class="ws-dialog-head">
      <h1 id="ws-collection-title">All boards</h1>
      <button type="button" data-close>Close</button>
    </div>
    <div class="ws-collection-tools">
      <input
        id="ws-search"
        type="search"
        placeholder="Search titles and drawing text"
        aria-label="Search boards"
      />
      <button type="button" id="ws-open">Open file…</button>
      <button type="button" id="ws-new-full">New drawing</button>
      <button type="button" id="ws-backup">Back up ZIP</button>
      <button type="button" id="ws-import">Restore ZIP…</button>
      <button type="button" id="ws-trash-view">Trash</button>
    </div>
    <div class="ws-collection-body">
      <nav id="ws-folders" aria-label="Folders"></nav>
      <div>
        <p id="ws-count" role="status"></p>
        <div id="ws-results" class="ws-grid"></div>
      </div>
    </div>
  </dialog>
  <dialog id="ws-history" aria-labelledby="ws-history-title">
    <div class="ws-dialog-head">
      <h1 id="ws-history-title">Version history</h1>
      <button type="button" data-close>Close</button>
    </div>
    <p>
      Up to 50 versions per board. Snapshots are made every five minutes of changed work and before
      clearing, restoring or trashing.
    </p>
    <button type="button" id="ws-checkpoint">Save version now</button>
    <div id="ws-versions"></div>
    <div id="ws-preview" hidden></div>
    <button type="button" id="ws-restore-version" hidden>Restore this version</button>
  </dialog>
  <dialog id="ws-move" aria-labelledby="ws-move-title">
    <form method="dialog">
      <h2 id="ws-move-title">Move to folder</h2>
      <select id="ws-move-folder" aria-label="Destination folder"></select>
      <div class="ws-dialog-buttons">
        <button value="cancel">Cancel</button>
        <button value="move">Move</button>
      </div>
    </form>
  </dialog>
`;

export async function mountWorkspace(root, { Scratchy, databaseName = "scratchy" }) {
  const workspace = new Workspace(root, Scratchy);
  await workspace.start(databaseName);
  return workspace;
}

class Workspace {
  constructor(root, Scratchy) {
    this.root = root;
    this.S = Scratchy;
    this.F = Scratchy.files;
    this.sessions = new Map();
    this.openIds = [];
    this.boards = new Map();
    this.folders = [];
    this.activeId = null;
    this.navigation = Promise.resolve();
    this.filter = "*";
    this.trashView = false;
    this.urls = [];
    this.preview = null;
    this.librarySignature = "";
    this.libraryItems = [];
    root.classList.add("workspace");
    root.innerHTML = SHELL;
    this.$ = (id) => root.querySelector(`#${id}`);
    this.message = el("div", undefined, "ws-notice");
    this.messageText = el("span");
    this.dismissMessage = button("Dismiss", () => {
      this.notice = null;
      if (![...this.sessions.values()].some((s) => s.error)) this.errorMessage = null;
      this.renderStatus();
    });
    this.message.append(this.messageText, this.dismissMessage);
    this.message.setAttribute("role", "status");
    this.$("ws-save-status").after(this.message);
    this.dialogMessages = ["ws-collection", "ws-history"].map((id) => {
      const message = el("p", undefined, "ws-dialog-message");
      message.setAttribute("role", "status");
      this.$(id).querySelector(".ws-dialog-head").after(message);
      return message;
    });
    this.$("ws-all").onclick = () => this.showCollection();
    this.$("ws-new").onclick = this.$("ws-new-full").onclick = () =>
      this.run(() => this.createBoard());
    this.$("ws-open").onclick = () => this.run(() => this.openFile());
    this.$("ws-backup").onclick = () => this.run(() => this.backup());
    this.$("ws-import").onclick = () => this.pick(".zip", (file) => this.restoreBackup(file));
    this.$("ws-search").oninput = () => this.renderCollection();
    this.$("ws-search").onkeydown = (e) => {
      if (e.key === "Enter") {
        const b = this.$("ws-results").querySelector("button[data-open]");
        if (b) b.click();
      }
      if (e.key === "ArrowDown") {
        e.preventDefault();
        this.$("ws-results").querySelector("button[data-open]")?.focus();
      }
    };
    this.$("ws-trash-view").onclick = () => {
      this.trashView = !this.trashView;
      this.renderCollection();
    };
    this.$("ws-actions").onchange = (e) => {
      const action = e.target.value;
      e.target.value = "";
      if (action) this.run(() => this.boardAction(action, this.activeId));
    };
    this.$("ws-retry").onclick = () => this.run(() => this.flushAll());
    this.$("ws-recover").onclick = () => {
      const s = this.active;
      if (s)
        this.download(
          `${this.F.drawingStem(s.name)}.excalidraw`,
          new Blob([s.ctrl.getScene()], { type: "application/json" }),
        );
    };
    for (const b of root.querySelectorAll("[data-close]"))
      b.onclick = () => b.closest("dialog").close();
    this.$("ws-history").addEventListener("close", () => {
      this.preview?.destroy();
      this.preview = null;
      this.$("ws-preview").replaceChildren();
      this.installFileHandler();
    });
    this.$("ws-checkpoint").onclick = () =>
      this.run(async () => {
        await this.flush(this.sessions.get(this.historyBoard));
        await this.store.checkpoint(this.historyBoard);
        await this.renderHistory();
      });
    this.$("ws-restore-version").onclick = () =>
      this.run(() => this.restoreVersion(this.historyBoard, this.previewVersion));
    this.bindFilesAndKeys();
    this.projects = new ProjectUI(this);
  }
  get active() {
    return this.projects?.documentId ? undefined : this.sessions.get(this.activeId);
  }
  run(fn) {
    return Promise.resolve()
      .then(fn)
      .catch((error) => {
        if (error.name !== "AbortError") this.error(error);
        return null;
      });
  }
  error(error) {
    this.errorMessage = error.message || String(error);
    this.renderStatus();
  }
  async start(databaseName) {
    this.store = await openWorkspace({
      name: databaseName,
      blocked: (message) => this.error(new Error(message)),
    });
    this.errorMessage = null;
    await this.refresh();
    this.theme =
      this.state.theme || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    this.root.dataset.theme = this.theme;
    this.libraryItems = this.state.libraryItems || [];
    this.librarySignature = JSON.stringify(this.libraryItems);
    this.openIds = this.state.openIds.filter(
      (id) => this.boards.has(id) && !this.boards.get(id).deletedAt,
    );
    this.activeId = this.openIds.includes(this.state.activeId)
      ? this.state.activeId
      : this.openIds[0] || null;
    this.projects.restore(this.state);
    this.store.subscribe(() => {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = setTimeout(() => this.run(() => this.refresh()), 50);
    });
    if (this.activeId) await this.activate(this.activeId);
    else this.render();
    if (this.state.activeDocument && this.projects.sourceTabs.includes(this.state.activeDocument))
      await this.projects.showMaster(this.state.activeDocument);
    await this.persistLayout();
    this.installFileHandler();
    return this;
  }
  async refresh() {
    const { boards, folders, state, projects, documents } = await this.store.list();
    this.boards = new Map(boards.map((b) => [b.id, b]));
    this.folders = folders;
    this.state = state;
    this.projects.update(projects, documents);
    const signature = JSON.stringify(state.libraryItems || []);
    if (this.librarySignature && signature !== this.librarySignature)
      await this.syncLibrary(state.libraryItems || [], false);
    this.render();
  }
  async persistLayout() {
    await this.store.layout({
      openIds: this.openIds,
      activeId: this.activeId,
      theme: this.theme,
      ...this.projects.layout(),
    });
  }
  switchTo(id, matches = []) {
    const task = this.navigation
      .catch(() => {})
      .then(async () => {
        if (this.active && this.activeId !== id) await this.flush(this.active);
        await this.activate(id);
        if (matches.length) {
          const elements = this.active.ctrl.api
            .getSceneElements()
            .filter((e) => matches.some((m) => m.id === e.id));
          if (elements.length)
            this.active.ctrl.api.scrollToContent(elements, { fitToContent: false, animate: true });
        }
        await this.persistLayout();
      });
    this.navigation = task;
    return task;
  }
  async activate(id) {
    await this.projects.activateCanvas(id);
    let s = this.sessions.get(id);
    if (!s) {
      const data = await this.store.board(id);
      if (!data || data.board.deletedAt)
        throw new Error("This board is in Trash or is no longer available.");
      const host = el("section", undefined, "ws-editor");
      host.dataset.boardId = id;
      host.setAttribute("aria-label", data.board.title);
      host.id = `ws-board-${id}`;
      host.setAttribute("role", "tabpanel");
      host.setAttribute("aria-labelledby", `ws-tab-${id}`);
      this.$("ws-editors").append(host);
      s = {
        board: data.board,
        name: data.board.fileName,
        handle: null,
        host,
        queue: Promise.resolve(),
        pending: 0,
        initializing: true,
        savedKey: null,
      };
      s.projectRevision = this.projects.items.find((p) => p.id === data.board.projectId)?.revision;
      s.projectSnapshot = await this.store.project(data.board.projectId);
      this.sessions.set(id, s);
      s.ctrl = this.S.mount(host, {
        scene: data.scene,
        initialViewport: data.board.viewport,
        theme: this.theme,
        name: this.F.drawingStem(s.name),
        libraryItems: this.libraryItems,
        canvasActions: { loadScene: false },
        extras: {
          stickers: new URL("./stickers/", location.href).href,
          download: (...args) => this.download(...args),
          fileName: () => this.F.drawingStem(s.name),
        },
        menu: [
          { label: "New drawing", onSelect: () => this.run(() => this.createBoard()) },
          { label: "All boards", shortcut: "Ctrl+P", onSelect: () => this.showCollection() },
          { label: "Open…", shortcut: "Ctrl+O", onSelect: () => this.run(() => this.openFile()) },
          { label: "Save", shortcut: "Ctrl+S", onSelect: () => this.run(() => this.saveFile(s)) },
          {
            label: "Save as…",
            shortcut: "Ctrl+Shift+S",
            onSelect: () => this.run(() => this.saveFile(s, true)),
          },
          {
            label: "Version history",
            onSelect: () => this.run(() => this.showHistory(s.board.id)),
          },
          { label: "About scratchy", onSelect: () => document.getElementById("about").showModal() },
        ],
        onStateChange: ({ appState }) => {
          if (s.initializing || s.suppress) return;
          clearTimeout(s.timer);
          s.timer = setTimeout(() => this.run(() => this.flush(s)), 300);
          if (this.active === s && appState.theme && appState.theme !== this.theme) {
            this.theme = appState.theme;
            this.root.dataset.theme = this.theme;
            this.run(() => this.persistLayout());
            for (const other of this.sessions.values())
              if (other !== s) this.run(() => other.ctrl.set({ theme: this.theme }));
          }
          // Excalidraw reports every pointer move; update the status once a frame.
          if (!this.statusFrame) {
            this.statusFrame = requestAnimationFrame(() => {
              this.statusFrame = null;
              this.renderStatus();
            });
          }
        },
        onLibraryChange: (items) => this.run(() => this.syncLibrary(items)),
      });
      await s.ctrl.ready;
      s.base = contentKey(s.ctrl.getScene());
      s.initializing = false;
    }
    if (!this.openIds.includes(id)) this.openIds.push(id);
    this.activeId = id;
    for (const other of this.sessions.values()) other.host.hidden = other !== s;
    this.render();
    await frame();
    s.ctrl.refresh();
    if (!this.root.querySelector("dialog[open]"))
      s.host.querySelector(".excalidraw")?.focus({ preventScroll: true });
    await this.flush(s);
  }
  async flush(s = this.active) {
    if (!s?.ctrl || s.initializing) return;
    clearTimeout(s.timer);
    s.timer = null;
    const json = s.ctrl.getScene(),
      key = contentKey(json),
      view = viewport(s.ctrl.api.getAppState()),
      viewKey = JSON.stringify(view);
    s.dirty = s.base !== key;
    if (key === s.savedKey && viewKey === s.savedView && !s.error && !s.pendingSourceSync) {
      this.renderStatus();
      return;
    }
    s.pending++;
    const task = s.queue
      .catch(() => {})
      .then(async () => {
        const managed = this.projects.items.find((p) => p.id === s.board.projectId)?.managed;
        const editing = Boolean(s.ctrl.api.getAppState().editingTextElement);
        s.pendingSourceSync = managed && editing;
        const result =
          managed && !editing
            ? await this.projects.manager.saveCanvas(s, json, view)
            : await this.store.save(s.board.id, s.board.revision, json, view, {
                rejectConflict: managed,
              });
        if (result.scene) {
          s.suppress = true;
          try {
            const scene = this.S.parseScene(result.scene);
            s.ctrl.api.addFiles(Object.values(scene.files || {}));
            s.ctrl.api.updateScene({ elements: scene.elements, captureUpdate: "NEVER" });
            await frame();
          } finally {
            s.suppress = false;
          }
        }
        if (result.deleted) {
          this.detach(s);
          this.error(new Error("This board was moved to Trash in another window."));
          return;
        }
        if (result.conflict) {
          const previous = s.board.id;
          this.sessions.delete(previous);
          this.sessions.set(result.board.id, s);
          this.openIds = this.openIds.map((id) => (id === previous ? result.board.id : id));
          if (this.activeId === previous) this.activeId = result.board.id;
          s.host.dataset.boardId = result.board.id;
          s.handle = null;
          s.base = null;
          s.name = result.board.fileName;
          s.host.id = `ws-board-${result.board.id}`;
          s.host.setAttribute("aria-labelledby", `ws-tab-${result.board.id}`);
          this.projects.selectedId = result.board.projectId;
          this.notice = managed
            ? "Another window changed this project. Your edits were saved as a recovered project."
            : "Another window changed this board. Your edits were saved as a recovered copy.";
          await this.persistLayout();
        }
        s.board = result.board;
        if (result.conflict && managed)
          s.projectSnapshot = await this.store.project(result.board.projectId);
        s.projectRevision = result.projectRevision ?? s.projectRevision;
        s.savedKey = contentKey(s.ctrl.getScene());
        s.savedView = viewKey;
        s.error = null;
        this.boards.set(s.board.id, s.board);
        if (this.errorMessage && ![...this.sessions.values()].some((x) => x.error))
          this.errorMessage = null;
        clearTimeout(s.thumbnailTimer);
        if (s.thumbnailKey !== key)
          s.thumbnailTimer = setTimeout(() => this.run(() => this.makeThumbnail(s, key)), 1500);
      });
    s.queue = task;
    this.renderStatus();
    try {
      await task;
    } catch (error) {
      s.error = error;
      this.error(error);
      throw error;
    } finally {
      s.pending--;
      this.render();
    }
  }
  async flushAll() {
    await Promise.all([...this.sessions.values()].map((s) => this.flush(s)));
  }
  async makeThumbnail(s, key) {
    if (
      !this.sessions.has(s.board.id) ||
      s.savedKey !== key ||
      contentKey(s.ctrl.getScene()) !== key
    )
      return;
    const es = s.ctrl.api.getSceneElements().filter((e) => !e.isDeleted);
    const width = es.length
      ? Math.max(...es.map((e) => e.x + e.width)) - Math.min(...es.map((e) => e.x))
      : 200;
    const height = es.length
      ? Math.max(...es.map((e) => e.y + e.height)) - Math.min(...es.map((e) => e.y))
      : 120;
    try {
      const blob = await s.ctrl.export({
        type: "png",
        as: "blob",
        scale: Math.min(1, 240 / Math.max(width, 1), 150 / Math.max(height, 1)),
      });
      if (s.savedKey === key) {
        s.thumbnailKey = key;
        await this.store.thumbnail(s.board.id, s.board.revision, blob);
      }
    } catch {
      /* A failed thumbnail never prevents a drawing from being saved. */
    }
  }
  async syncLibrary(items, persist = true) {
    const signature = JSON.stringify(items);
    if (signature === this.librarySignature) return;
    this.librarySignature = signature;
    this.libraryItems = structuredClone(items);
    if (persist) await this.store.library(this.libraryItems);
    for (const s of this.sessions.values())
      await s.ctrl.api?.updateLibrary({ libraryItems: this.libraryItems, merge: false });
  }
  async createBoard(scene = emptyScene(), meta = {}) {
    if (this.active) await this.flush(this.active);
    const project = this.projects.current();
    if (project?.managed && !meta.projectId) {
      const data = await this.projects.manager.addCanvas(
        project.id,
        meta.title || "New canvas",
        null,
        scene,
      );
      await this.switchTo(data.board.id);
      this.$("ws-collection").close();
      return data.board;
    }
    const board = await this.store.create(scene, meta);
    this.boards.set(board.id, board);
    await this.switchTo(board.id);
    this.$("ws-collection").close();
    return board;
  }
  detach(s) {
    if (this.sessions.get(s.board.id) !== s) return;
    clearTimeout(s.timer);
    clearTimeout(s.thumbnailTimer);
    s.ctrl.destroy();
    s.host.remove();
    this.sessions.delete(s.board.id);
    this.openIds = this.openIds.filter((id) => id !== s.board.id);
    if (this.activeId === s.board.id) this.activeId = null;
    this.installFileHandler();
  }
  async closeBoard(id) {
    const s = this.sessions.get(id);
    if (s) {
      await this.flush(s);
      this.detach(s);
    } else this.openIds = this.openIds.filter((x) => x !== id);
    if (!this.activeId && this.openIds.length && !this.projects.documentId)
      await this.activate(this.openIds.at(-1));
    await this.persistLayout();
    this.render();
  }
  async boardAction(action, id) {
    const board = this.boards.get(id);
    if (!board) return;
    if (await this.projects.boardAction(action, board)) return;
    const s = this.sessions.get(id);
    if (action === "history") return this.showHistory(id);
    if (action === "rename") {
      const title = prompt("Board name", board.title)?.trim();
      if (!title || title === board.title) return;
      const fileName = `${title}.excalidraw`;
      const updated = await this.store.patch(id, { title, fileName });
      if (s) {
        s.board = { ...s.board, title, fileName };
        if (!s.handle) s.name = fileName;
        await s.ctrl.set({ name: title });
        s.host.setAttribute("aria-label", title);
      }
      this.boards.set(id, updated);
    } else if (action === "duplicate") {
      if (s) await this.flush(s);
      const data = await this.store.board(id);
      await this.createBoard(data.scene, {
        title: `${board.title} copy`,
        folderId: board.folderId,
      });
    } else if (action === "pin") await this.store.patch(id, { pinned: !board.pinned });
    else if (action === "move") await this.chooseFolder(id, false);
    else if (action === "trash") {
      if (s) await this.flush(s);
      await this.store.trash(id);
      await this.closeBoard(id);
    } else if (action === "restore") {
      await this.store.restore(id);
      await this.refresh();
      await this.switchTo(id);
      this.$("ws-collection").close();
    }
    await this.refresh();
  }
  folderPath(id) {
    const names = [],
      seen = new Set();
    while (id && !seen.has(id)) {
      seen.add(id);
      const f = this.folders.find((f) => f.id === id);
      if (!f) break;
      names.unshift(f.title);
      id = f.parentId;
    }
    return names.join(" / ");
  }
  async chooseFolder(id, folder) {
    const select = this.$("ws-move-folder");
    select.replaceChildren();
    const option = (value, text) => {
      const o = el("option", text);
      o.value = value || "";
      select.append(o);
    };
    option(null, "Root");
    const excluded = folder ? folderDescendants(this.folders, id) : new Set();
    for (const f of [...this.folders].sort((a, b) =>
      this.folderPath(a.id).localeCompare(this.folderPath(b.id)),
    ))
      if (!excluded.has(f.id)) option(f.id, this.folderPath(f.id));
    const d = this.$("ws-move");
    select.value =
      (folder ? this.folders.find((f) => f.id === id)?.parentId : this.boards.get(id)?.folderId) ||
      "";
    d.returnValue = "";
    d.showModal();
    await new Promise((resolve) => d.addEventListener("close", resolve, { once: true }));
    if (d.returnValue !== "move") return;
    if (folder) await this.store.moveFolder(id, select.value || null);
    else await this.store.patch(id, { folderId: select.value || null });
    await this.refresh();
  }
  showCollection() {
    this.renderCollection();
    const d = this.$("ws-collection");
    if (!d.open) d.showModal();
    this.$("ws-search").focus();
    this.$("ws-search").select();
  }
  render() {
    const tabs = this.$("ws-tabs");
    tabs.replaceChildren();
    for (const id of this.openIds) {
      const board = this.boards.get(id);
      if (!board || board.deletedAt) continue;
      const item = el("div", undefined, "ws-tab");
      const open = button(board.title, () => this.run(() => this.switchTo(id)));
      open.setAttribute("role", "tab");
      open.setAttribute("aria-selected", String(!this.projects.documentId && this.activeId === id));
      open.dataset.boardId = id;
      open.id = `ws-tab-${id}`;
      open.setAttribute("aria-controls", `ws-board-${id}`);
      open.onkeydown = (event) => {
        if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
        event.preventDefault();
        const n = this.openIds.indexOf(id),
          next =
            event.key === "Home"
              ? this.openIds[0]
              : event.key === "End"
                ? this.openIds.at(-1)
                : this.openIds[
                    (n + (event.key === "ArrowLeft" ? -1 : 1) + this.openIds.length) %
                      this.openIds.length
                  ];
        this.run(async () => {
          await this.switchTo(next);
          this.$("ws-tabs").querySelector(`[data-board-id="${next}"]`)?.focus();
        });
      };
      item.append(
        open,
        button("×", () => this.run(() => this.closeBoard(id)), `Close ${board.title}`),
      );
      tabs.append(item);
    }
    this.$("ws-empty").hidden = Boolean(this.active);
    this.$("ws-actions").disabled = !this.active;
    this.renderStatus();
    this.projects.render();
    if (this.$("ws-collection").open) this.renderCollection();
  }
  renderStatus() {
    const s = this.active;
    // s.dirty is kept by flush() and saveFile(): serializing the scene here
    // would run on every pointer move.
    const dirty = Boolean(s?.dirty);
    document.title = s
      ? `${dirty ? "• " : ""}${this.boards.get(s.board.id)?.title || s.board.title} · scratchy`
      : "All boards · scratchy";
    const failures = [...this.sessions.values()].some((session) => session.error);
    const status = !s
      ? "Choose a board or start a drawing."
      : s.error
        ? `Could not save: ${s.error.message}`
        : s.pending || s.timer
          ? "Saving in this browser…"
          : `Saved in this browser${dirty ? " · Changes not saved to a file" : !s.handle ? " · No external file linked" : ""}`;
    this.$("ws-save-status").textContent = status;
    this.$("ws-save-status").classList.toggle("ws-error", Boolean(s?.error));
    this.$("ws-retry").hidden = !failures;
    this.$("ws-recover").hidden = !failures || !s;
    const message = this.errorMessage || this.notice || "";
    this.message.hidden = !message;
    this.messageText.textContent = message;
    this.dismissMessage.hidden = failures;
    this.message.classList.toggle("ws-error", Boolean(this.errorMessage));
    for (const dialog of this.dialogMessages) {
      dialog.hidden = !message;
      dialog.textContent = message;
      dialog.classList.toggle("ws-error", Boolean(this.errorMessage));
    }
    const state = this.state;
    this.$("ws-backup-status").textContent = !state?.lastBackupAt
      ? "Not backed up yet"
      : `Last ZIP export ${new Date(state.lastBackupAt).toLocaleString()}${state.changeSeq !== state.lastBackupSeq ? " · Changes since backup" : ""}`;
  }
  renderCollection() {
    for (const url of this.urls) URL.revokeObjectURL(url);
    this.urls = [];
    this.$("ws-collection-title").textContent = this.trashView
      ? "Trash · kept for 30 days"
      : "All boards";
    this.$("ws-trash-view").textContent = this.trashView ? "All boards" : "Trash";
    this.renderFolderList();
    const query = this.$("ws-search").value;
    let candidates = [...this.boards.values()].filter(
      (b) => Boolean(b.deletedAt) === this.trashView,
    );
    if (this.filter !== "*") {
      const ids = this.filter ? folderDescendants(this.folders, this.filter) : new Set([null]);
      candidates = candidates.filter((b) => ids.has(b.folderId));
    }
    const results = searchBoards(
      candidates.map((b) => (this.trashView ? { ...b, deletedAt: null } : b)),
      query,
    );
    this.$("ws-count").textContent =
      `${results.length} ${results.length === 1 ? "board" : "boards"}${query ? " found" : ""}`;
    const grid = this.$("ws-results");
    grid.replaceChildren();
    for (const { board, matches } of results) grid.append(this.boardCard(board, matches));
  }
  /** The collection's folder filter, with folder actions for the selected one. */
  renderFolderList() {
    const folders = this.$("ws-folders");
    folders.replaceChildren();
    const folderButton = (id, title) => {
      const b = button(title, () => {
        this.filter = id;
        this.renderCollection();
      });
      b.className = this.filter === id ? "ws-selected" : "";
      b.ondragover = (e) => e.preventDefault();
      b.ondrop = (e) => {
        e.preventDefault();
        const boardId = e.dataTransfer.getData("application/x-scratchy-board"),
          folderId = e.dataTransfer.getData("application/x-scratchy-folder");
        if (boardId)
          this.run(() => this.store.patch(boardId, { folderId: id === "*" ? null : id }));
        if (folderId) this.run(() => this.store.moveFolder(folderId, id === "*" ? null : id));
      };
      folders.append(b);
      return b;
    };
    folderButton("*", "All folders");
    folderButton(null, "Root");
    for (const f of [...this.folders].sort((a, b) =>
      this.folderPath(a.id).localeCompare(this.folderPath(b.id)),
    )) {
      const b = folderButton(f.id, this.folderPath(f.id));
      b.draggable = true;
      b.ondragstart = (e) => e.dataTransfer.setData("application/x-scratchy-folder", f.id);
    }
    folders.append(
      button("New folder", () =>
        this.run(async () => {
          const title = prompt("Folder name")?.trim();
          if (title) await this.store.folder(title, this.filter === "*" ? null : this.filter);
        }),
      ),
    );
    if (this.filter && this.filter !== "*" && this.folders.some((f) => f.id === this.filter)) {
      folders.append(
        button("Rename folder", () =>
          this.run(async () => {
            const f = this.folders.find((f) => f.id === this.filter);
            const title = prompt("Folder name", f.title)?.trim();
            if (title) await this.store.renameFolder(f.id, title);
          }),
        ),
        button("Move folder", () => this.run(() => this.chooseFolder(this.filter, true))),
        button("Delete folder", () =>
          this.run(async () => {
            await this.store.deleteFolder(this.filter);
            this.filter = "*";
            await this.refresh();
          }),
        ),
      );
    }
  }
  /** One card in All boards: thumbnail, folder, matching text and actions. */
  boardCard(board, matches) {
    const b = this.boards.get(board.id),
      card = el("article", undefined, "ws-card");
    card.draggable = !this.trashView;
    card.ondragstart = (e) => e.dataTransfer.setData("application/x-scratchy-board", b.id);
    const open = button(
      b.title,
      () =>
        this.run(async () => {
          if (this.trashView) return;
          this.$("ws-collection").close();
          await this.switchTo(b.id, matches);
        }),
      `${b.pinned ? "Pinned: " : ""}${b.title}`,
    );
    open.dataset.open = b.id;
    if (b.thumbnail instanceof Blob) {
      const img = el("img");
      img.alt = "";
      const url = URL.createObjectURL(b.thumbnail);
      this.urls.push(url);
      img.src = url;
      open.prepend(img);
    }
    card.append(open, el("small", this.folderPath(b.folderId) || "Root"));
    if (matches.length)
      card.append(
        el(
          "p",
          matches
            .map((m) => m.text)
            .join(" · ")
            .slice(0, 180),
          "ws-snippet",
        ),
      );
    const actions = el("div", undefined, "ws-card-actions");
    if (this.trashView) {
      card.append(
        el("small", `Expires ${new Date(b.deletedAt + TRASH_RETENTION).toLocaleDateString()}`),
      );
      actions.append(
        button(
          "Restore",
          () => this.run(() => this.boardAction("restore", b.id)),
          `Restore ${b.title}`,
        ),
      );
    } else
      for (const [action, text] of [
        ["pin", b.pinned ? "Unpin" : "Pin"],
        ["rename", "Rename"],
        ["duplicate", "Duplicate"],
        ["move", "Move"],
        ["history", "History"],
        ["trash", "Trash"],
      ])
        actions.append(
          button(text, () => this.run(() => this.boardAction(action, b.id)), `${text} ${b.title}`),
        );
    card.append(actions);
    return card;
  }
  async showHistory(id) {
    const project = this.projects.items.find((p) => p.id === this.boards.get(id)?.projectId);
    if (project?.managed) {
      await this.flushAll();
      return this.projects.history(project.id);
    }
    const s = this.sessions.get(id);
    if (s) await this.flush(s);
    this.historyBoard = id;
    this.$("ws-history-title").textContent = `History · ${this.boards.get(id).title}`;
    this.$("ws-preview").hidden = true;
    this.$("ws-restore-version").hidden = true;
    await this.renderHistory();
    if (!this.$("ws-history").open) this.$("ws-history").showModal();
  }
  async renderHistory() {
    const history = await this.store.history(this.historyBoard),
      list = this.$("ws-versions");
    list.replaceChildren();
    if (!history.length) list.append(el("p", "No historical versions yet. You can save one now."));
    for (const version of history)
      list.append(
        button(
          `Preview ${new Date(version.createdAt).toLocaleString()} · revision ${version.revision}`,
          () =>
            this.run(async () => {
              this.preview?.destroy();
              const host = this.$("ws-preview");
              host.replaceChildren();
              host.hidden = false;
              this.preview = this.S.mount(host, {
                scene: await this.store.version(version.id),
                mode: "view",
                theme: this.theme,
              });
              await this.preview.ready;
              this.installFileHandler();
              this.previewVersion = version.id;
              this.$("ws-restore-version").hidden = false;
            }),
        ),
      );
  }
  async restoreVersion(boardId, versionId) {
    const scene = await this.store.version(versionId);
    await this.switchTo(boardId);
    const s = this.active;
    await this.store.checkpoint(boardId);
    s.suppress = true;
    try {
      await s.ctrl.setScene(scene);
      await frame();
    } finally {
      s.suppress = false;
    }
    s.savedKey = null;
    await this.flush(s);
    this.$("ws-history").close();
    this.$("ws-collection").close();
  }
  download(name, blob) {
    return this.S.extras.download(name, blob);
  }
  pick(accept, fn) {
    const input = el("input");
    input.type = "file";
    input.accept = accept;
    input.multiple = accept !== ".zip";
    input.onchange = () =>
      this.run(async () => {
        for (const file of input.files) await fn(file);
      });
    input.click();
  }
  async loadFile(file, handle = null) {
    if (/\.md$/i.test(file.name) && !/\.excalidraw\.md$/i.test(file.name))
      return this.projects.importMarkdown(file);
    const result = await this.F.readDrawingFile(file);
    if (result.kind === "library") {
      if (!this.active) await this.createBoard();
      await this.active.ctrl.api.updateLibrary({
        libraryItems: result.blob,
        merge: true,
        openLibraryMenu: true,
      });
      return;
    }
    const b = await this.createBoard(result.scene, {
      title: this.F.drawingStem(file.name),
      fileName: file.name,
    });
    this.sessions.get(b.id).handle = handle;
    this.renderStatus();
  }
  async openFile() {
    if (typeof window.showOpenFilePicker === "function") {
      const handles = await showOpenFilePicker({ types: PICKERS, multiple: true });
      for (const handle of handles) await this.loadFile(await handle.getFile(), handle);
    } else
      this.pick(".excalidraw,.md,.svg,.png,.excalidrawlib,.json", (file) => this.loadFile(file));
  }
  async saveFile(s = this.active, saveAs = false) {
    if (this.projects.documentId) return this.projects.saveMaster();
    if (!s) return;
    await this.flush(s);
    let handle = saveAs ? null : s.handle,
      name = s.name;
    if (!handle && typeof window.showSaveFilePicker === "function")
      handle = await showSaveFilePicker({ suggestedName: name, types: PICKERS });
    if (handle) name = handle.name;
    const json = s.ctrl.getScene(),
      captured = JSON.parse(json),
      savedKey = contentKey(json);
    const snapshot = {
      getScene: () => json,
      export: (options) => this.S.exportScene(captured, options),
    };
    const blob = await this.F.drawingBlob(snapshot, name);
    if (handle) {
      const stream = await handle.createWritable();
      await stream.write(blob);
      await stream.close();
    } else this.download(name, blob);
    s.handle = handle;
    s.name = name;
    s.base = savedKey;
    s.dirty = contentKey(s.ctrl.getScene()) !== savedKey;
    await this.store.patch(s.board.id, { fileName: name });
    this.renderStatus();
  }
  async backup() {
    await this.projects.saveDraft();
    await this.flushAll();
    await this.projects.manager.idle();
    const data = await this.store.dump(),
      state = data.workspace.find((x) => x.id === "state");
    const blob = await createBackup(data);
    this.download(`scratchy-workspace-${new Date().toISOString().slice(0, 10)}.zip`, blob);
    await this.store.backedUp(state.changeSeq);
    await this.refresh();
    return blob;
  }
  async restoreBackup(file) {
    await this.flushAll();
    const data = await readBackup(file),
      result = await this.store.importArchive(data);
    await this.refresh();
    if (result.fresh) {
      for (const s of [...this.sessions.values()]) this.detach(s);
      this.openIds = this.state.openIds;
      this.activeId = this.state.activeId;
      this.theme = this.state.theme || this.theme;
      this.root.dataset.theme = this.theme;
      this.projects.restore(this.state);
      if (this.activeId) await this.activate(this.activeId);
      if (this.state.activeDocument) await this.projects.showMaster(this.state.activeDocument);
    } else {
      this.openIds = [...new Set([...this.openIds, ...this.state.openIds])];
      this.projects.sourceTabs = [
        ...new Set([
          ...this.projects.sourceTabs,
          ...(this.state.tabs || []).filter((t) => t.kind === "markdown").map((t) => t.id),
        ]),
      ];
    }
    await this.persistLayout();
    this.notice = `Restored ${result.added} boards; ${result.skipped} identical boards kept.`;
    this.render();
    return result;
  }
  bindFilesAndKeys() {
    window.addEventListener(
      "keydown",
      (e) => {
        if (!(e.ctrlKey || e.metaKey) || e.altKey) return;
        const key = e.key.toLowerCase();
        if (key === "p" && !e.shiftKey) {
          e.preventDefault();
          e.stopImmediatePropagation();
          this.showCollection();
        }
        if (key === "s") {
          e.preventDefault();
          e.stopImmediatePropagation();
          this.run(() => this.saveFile(this.active, e.shiftKey));
        }
        if (key === "o" && !e.shiftKey) {
          e.preventDefault();
          e.stopImmediatePropagation();
          this.run(() => this.openFile());
        }
      },
      true,
    );
    // Inspect image drops for embedded drawings, then replay ordinary image drops.
    const replayed = new WeakSet();
    this.root.addEventListener(
      "drop",
      (e) => {
        if (
          replayed.has(e) ||
          e.dataTransfer.types.includes("application/x-scratchy-board") ||
          e.dataTransfer.types.includes("application/x-scratchy-folder")
        )
          return;
        const files = [...(e.dataTransfer?.files || [])];
        if (
          !files.length ||
          !files.some((f) =>
            /\.(excalidraw(\.(json|md|svg|png))?|md|json|svg|png|excalidrawlib)$/i.test(f.name),
          )
        )
          return;
        e.preventDefault();
        e.stopPropagation();
        const target = e.target;
        this.run(async () => {
          for (const file of files) {
            try {
              await this.loadFile(file);
            } catch (error) {
              if (!/\.(png|svg)$/i.test(file.name) || /\.excalidraw\./i.test(file.name))
                throw error;
              const transfer = new DataTransfer();
              transfer.items.add(file);
              const drop = new DragEvent("drop", {
                bubbles: true,
                cancelable: true,
                dataTransfer: transfer,
                clientX: e.clientX,
                clientY: e.clientY,
              });
              replayed.add(drop);
              target.dispatchEvent(drop);
            }
          }
        });
      },
      true,
    );
    this.installFileHandler();
    document.addEventListener("visibilitychange", () => {
      if (document.hidden)
        this.run(async () => {
          await this.projects.saveDraft();
          await this.flushAll();
        });
    });
    window.addEventListener("beforeunload", (e) => {
      if (
        this.projects.timer ||
        [...this.sessions.values()].some(
          (s) => s.timer || s.pending || s.error || (s.handle && s.dirty),
        )
      )
        e.preventDefault();
    });
  }
  installFileHandler() {
    // Excalidraw releases the global consumer on unmount. Reattach the host's
    // consumer after closing a board or history preview, too.
    if (this.store && "launchQueue" in window)
      launchQueue.setConsumer((params) =>
        this.run(async () => {
          for (const handle of params.files || [])
            await this.loadFile(await handle.getFile(), handle);
        }),
      );
  }
}
