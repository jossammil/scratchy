// The IndexedDB adapter. Every write is one transaction, revisions guard
// against stale windows, and images are stored once by content hash.
import {
  emptyScene,
  uid,
  packScene,
  unpackScene,
  HISTORY_LIMIT,
  SNAPSHOT_INTERVAL,
  TRASH_RETENTION,
  validFolderMove,
} from "./model.js";

const TABLES = [
  "boards",
  "folders",
  "revisions",
  "assets",
  "workspace",
  "projects",
  "documents",
  "projectVersions",
];
const request = (r) =>
  new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
export async function openWorkspace({
  name = "scratchy",
  blocked = () => {},
  changed = () => {},
} = {}) {
  const db = await new Promise((resolve, reject) => {
    const r = indexedDB.open(name, 3);
    r.onupgradeneeded = () => {
      if (!r.result.objectStoreNames.contains("kv")) r.result.createObjectStore("kv");
      for (const table of TABLES)
        if (!r.result.objectStoreNames.contains(table))
          r.result.createObjectStore(table, { keyPath: table === "assets" ? "key" : "id" });
    };
    r.onblocked = () =>
      blocked(
        "Close other Scratchy windows to finish upgrading this workspace. Your original drawing is preserved.",
      );
    r.onerror = () => reject(r.error);
    r.onsuccess = () => resolve(r.result);
  });
  db.onversionchange = () => {
    db.close();
    blocked("Scratchy was upgraded in another window. Reload this window to continue.");
  };
  const channel =
    typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(`${name}:workspace`);
  const listeners = new Set([changed]);
  const announce = () => {
    for (const fn of listeners) fn();
    channel?.postMessage("changed");
  };
  if (channel)
    channel.onmessage = () => {
      for (const fn of listeners) fn();
    };
  async function run(tables, mode, fn) {
    const tx = db.transaction(tables, mode);
    const done = new Promise((resolve, reject) => {
      tx.oncomplete = resolve;
      tx.onabort = () => reject(tx.error || new Error("Workspace transaction cancelled."));
      tx.onerror = () => {};
    });
    done.catch(() => {});
    const t = {
      get: (table, key) => request(tx.objectStore(table).get(key)),
      all: (table) => request(tx.objectStore(table).getAll()),
      put: (table, value, key) =>
        request(
          key === undefined
            ? tx.objectStore(table).put(value)
            : tx.objectStore(table).put(value, key),
        ),
      delete: (table, key) => request(tx.objectStore(table).delete(key)),
    };
    try {
      const result = await fn(t);
      await done;
      return result;
    } catch (error) {
      try {
        tx.abort();
      } catch {}
      await done.catch(() => {});
      throw error;
    }
  }
  const read = (tables, fn) => run(tables, "readonly", fn);
  async function write(fn) {
    const value = await run(TABLES, "readwrite", fn);
    announce();
    return value;
  }
  const touch = async (t) => {
    const state = await t.get("workspace", "state");
    state.changeSeq++;
    await t.put("workspace", state);
  };
  async function hydrate(t, record) {
    const refs = Object.values(record.fileRefs || {});
    const assets = new Map(
      await Promise.all(
        refs.map(async (ref) => [ref.assetKey, await t.get("assets", ref.assetKey)]),
      ),
    );
    return unpackScene(record, assets);
  }
  async function putAssets(t, packed) {
    for (const asset of packed.assets) await t.put("assets", asset);
  }
  const recordFor = (packed) => ({
    scene: packed.scene,
    fileRefs: packed.fileRefs,
    fingerprint: packed.fingerprint,
    labels: packed.labels,
  });
  function makeBoard(
    packed,
    { title = "Untitled", fileName = `${title}.excalidraw`, folderId = null, id = uid() } = {},
  ) {
    return {
      id,
      title,
      fileName,
      folderId,
      projectId: "my-sketches",
      pinned: false,
      revision: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      snapshotAt: Date.now(),
      deletedAt: null,
      ...recordFor(packed),
    };
  }
  async function snapshot(t, board) {
    const versions = (await t.all("revisions"))
      .filter((r) => r.boardId === board.id)
      .sort((a, b) => a.createdAt - b.createdAt || a.revision - b.revision);
    if (versions.at(-1)?.fingerprint === board.fingerprint) return;
    await t.put("revisions", {
      id: uid(),
      boardId: board.id,
      createdAt: Date.now(),
      revision: board.revision,
      scene: board.scene,
      fileRefs: board.fileRefs,
      fingerprint: board.fingerprint,
    });
    for (const old of versions.slice(0, Math.max(0, versions.length + 1 - HISTORY_LIMIT)))
      await t.delete("revisions", old.id);
    board.snapshotAt = Date.now();
  }
  async function gc(t) {
    const used = new Set();
    for (const record of [...(await t.all("boards")), ...(await t.all("revisions"))])
      for (const ref of Object.values(record.fileRefs || {})) used.add(ref.assetKey);
    for (const version of await t.all("projectVersions"))
      for (const record of version.boards || [])
        for (const ref of Object.values(record.fileRefs || {})) used.add(ref.assetKey);
    for (const p of await t.all("projects"))
      for (const ref of Object.values(p.resources || {})) used.add(ref.assetKey);
    for (const version of await t.all("projectVersions"))
      for (const ref of Object.values(version.project.resources || {})) used.add(ref.assetKey);
    for (const asset of await t.all("assets"))
      if (!used.has(asset.key)) await t.delete("assets", asset.key);
  }
  // The migration marker and the imported board commit together. Legacy keys are untouched.
  if (!(await read(["workspace"], (t) => t.get("workspace", "state")))) {
    const legacy = await read(["kv"], async (t) => ({
      scene: await t.get("kv", "scene"),
      name: await t.get("kv", "name"),
      theme: await t.get("kv", "theme"),
    }));
    const packed = await packScene(legacy.scene || emptyScene());
    await write(async (t) => {
      if (await t.get("workspace", "state")) return;
      const fileName = legacy.name || "Untitled.excalidraw";
      const board = makeBoard(packed, {
        id: legacy.scene ? "legacy-drawing" : uid(),
        title: fileName.replace(/\.(excalidraw(\.(md|svg|png|json))?|md|svg|png|json)$/i, ""),
        fileName,
      });
      board.placeholder = !legacy.scene;
      await putAssets(t, packed);
      await t.put("boards", board);
      await t.put("workspace", {
        id: "state",
        openIds: [board.id],
        activeId: board.id,
        theme: legacy.theme || null,
        libraryItems: [],
        changeSeq: 0,
        lastBackupSeq: -1,
        lastBackupAt: null,
      });
    });
  }
  const api = {
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    close() {
      channel?.close();
      db.close();
    },
    list: () =>
      read(["boards", "folders", "workspace", "projects", "documents"], async (t) => ({
        boards: await t.all("boards"),
        folders: await t.all("folders"),
        state: await t.get("workspace", "state"),
        projects: await t.all("projects"),
        documents: await t.all("documents"),
      })),
    async board(id) {
      return read(["boards", "assets"], async (t) => {
        const b = await t.get("boards", id);
        return b && { board: b, scene: await hydrate(t, b) };
      });
    },
    async create(scene = emptyScene(), meta = {}) {
      const packed = await packScene(scene);
      return write(async (t) => {
        const b = makeBoard(packed, meta);
        b.projectId = meta.projectId || "my-sketches";
        if (b.folderId && !(await t.get("folders", b.folderId))) b.folderId = null;
        await putAssets(t, packed);
        await t.put("boards", b);
        await touch(t);
        return b;
      });
    },
    async save(id, expectedRevision, scene, view, { rejectConflict = false } = {}) {
      const packed = await packScene(scene);
      return write(async (t) => {
        let b = await t.get("boards", id);
        if (!b)
          throw new Error(
            "This board is no longer available. Download the drawing to keep your work.",
          );
        const conflict = Boolean(b.deletedAt || b.revision !== expectedRevision);
        if (rejectConflict && conflict)
          throw new Error(
            "This project changed in another window. Finish editing text to recover your work as a whole project.",
          );
        if (conflict && b.fingerprint !== packed.fingerprint) {
          b = makeBoard(packed, { title: `${b.title} (recovered)`, folderId: b.folderId });
        } else if (b.deletedAt) return { board: b, conflict: false, deleted: true };
        const contentChanged = b.fingerprint !== packed.fingerprint;
        if (contentChanged) {
          const cleared =
            b.scene.elements.some((e) => !e.isDeleted) &&
            !packed.scene.elements.some((e) => !e.isDeleted);
          if (cleared || Date.now() - b.snapshotAt >= SNAPSHOT_INTERVAL) await snapshot(t, b);
          Object.assign(b, recordFor(packed), { revision: b.revision + 1, updatedAt: Date.now() });
          if (
            packed.scene.elements.some((e) => !e.isDeleted) ||
            packed.scene.appState?.viewBackgroundColor !== "#ffffff"
          )
            b.placeholder = false;
        }
        b.viewport = view || b.viewport;
        await putAssets(t, packed);
        await t.put("boards", b);
        if (contentChanged || conflict) await touch(t);
        return { board: b, conflict: conflict && id !== b.id };
      });
    },
    patch(id, fields) {
      return write(async (t) => {
        const b = await t.get("boards", id);
        if (!b) throw new Error("Board not found.");
        Object.assign(b, fields, { placeholder: false });
        if (b.folderId && !(await t.get("folders", b.folderId))) b.folderId = null;
        await t.put("boards", b);
        await touch(t);
        return b;
      });
    },
    layout(fields) {
      return write(async (t) => {
        const state = await t.get("workspace", "state");
        const changed = Object.entries(fields).some(
          ([key, value]) => JSON.stringify(state[key]) !== JSON.stringify(value),
        );
        Object.assign(state, fields);
        if (changed) state.changeSeq++;
        await t.put("workspace", state);
      });
    },
    library(items) {
      return write(async (t) => {
        const state = await t.get("workspace", "state");
        state.libraryItems = items;
        await t.put("workspace", state);
        await touch(t);
      });
    },
    checkpoint(id) {
      return write(async (t) => {
        const b = await t.get("boards", id);
        if (!b) throw new Error("Board not found.");
        await snapshot(t, b);
        await t.put("boards", b);
        await touch(t);
      });
    },
    history(id) {
      return read(["revisions"], async (t) =>
        (await t.all("revisions"))
          .filter((r) => r.boardId === id)
          .sort((a, b) => b.createdAt - a.createdAt || b.revision - a.revision),
      );
    },
    version(id) {
      return read(["revisions", "assets"], async (t) => {
        const r = await t.get("revisions", id);
        if (!r) throw new Error("Version not found.");
        return hydrate(t, r);
      });
    },
    trash(id) {
      return write(async (t) => {
        const b = await t.get("boards", id);
        if (!b) return;
        await snapshot(t, b);
        b.deletedAt = Date.now();
        await t.put("boards", b);
        await touch(t);
      });
    },
    restore(id) {
      return write(async (t) => {
        const b = await t.get("boards", id);
        if (!b) throw new Error("Board not found.");
        const folders = await t.all("folders");
        if (!folders.some((f) => f.id === b.folderId)) b.folderId = null;
        b.deletedAt = null;
        await t.put("boards", b);
        await touch(t);
        return b;
      });
    },
    folder(title, parentId = null) {
      return write(async (t) => {
        const f = {
          id: uid(),
          title,
          parentId: parentId && (await t.get("folders", parentId)) ? parentId : null,
        };
        await t.put("folders", f);
        await touch(t);
        return f;
      });
    },
    moveFolder(id, parentId) {
      return write(async (t) => {
        const folders = await t.all("folders");
        if (!validFolderMove(folders, id, parentId))
          throw new Error("A folder cannot be moved inside itself.");
        const f = folders.find((f) => f.id === id);
        if (!f) throw new Error("Folder not found.");
        f.parentId = parentId;
        await t.put("folders", f);
        await touch(t);
      });
    },
    renameFolder(id, title) {
      return write(async (t) => {
        const f = await t.get("folders", id);
        if (!f) throw new Error("Folder not found.");
        f.title = title;
        await t.put("folders", f);
        await touch(t);
      });
    },
    deleteFolder(id) {
      return write(async (t) => {
        const f = await t.get("folders", id);
        if (!f) return;
        for (const b of await t.all("boards"))
          if (b.folderId === id) {
            b.folderId = f.parentId;
            await t.put("boards", b);
          }
        for (const child of await t.all("folders"))
          if (child.parentId === id) {
            child.parentId = f.parentId;
            await t.put("folders", child);
          }
        await t.delete("folders", id);
        await touch(t);
      });
    },
    thumbnail(id, revision, thumbnail) {
      return write(async (t) => {
        const b = await t.get("boards", id);
        if (b && b.revision === revision) {
          b.thumbnail = thumbnail;
          await t.put("boards", b);
        }
      });
    },
    expire(now = Date.now()) {
      return write(async (t) => {
        let removed = false;
        for (const p of await t.all("projects"))
          if (p.deletedAt && now - p.deletedAt >= TRASH_RETENTION) {
            await t.delete("projects", p.id);
            await t.delete("documents", p.id);
            for (const v of await t.all("projectVersions"))
              if (v.projectId === p.id) await t.delete("projectVersions", v.id);
            removed = true;
          }
        for (const b of await t.all("boards"))
          if (b.deletedAt && now - b.deletedAt >= TRASH_RETENTION) {
            await t.delete("boards", b.id);
            for (const r of await t.all("revisions"))
              if (r.boardId === b.id) await t.delete("revisions", r.id);
            removed = true;
          }
        if (removed) {
          const ids = new Set((await t.all("boards")).map((b) => b.id)),
            state = await t.get("workspace", "state");
          state.openIds = state.openIds.filter((id) => ids.has(id));
          if (!ids.has(state.activeId)) state.activeId = state.openIds[0] || null;
          await t.put("workspace", state);
          await touch(t);
        }
        await gc(t);
      });
    },
    dump() {
      return read(TABLES, async (t) => {
        const result = {};
        for (const table of TABLES) result[table] = await t.all(table);
        return result;
      });
    },
    backedUp(sequence) {
      return write(async (t) => {
        const state = await t.get("workspace", "state");
        state.lastBackupSeq = sequence;
        state.lastBackupAt = Date.now();
        await t.put("workspace", state);
      });
    },
    async project(id) {
      return read(["projects", "documents", "assets"], async (t) => {
        const p = await t.get("projects", id);
        if (!p) return null;
        const document = await t.get("documents", id),
          resources = {};
        for (const [path, ref] of Object.entries(p.resources || {})) {
          const { assetKey, ...meta } = ref;
          const asset = await t.get("assets", assetKey);
          if (asset) resources[path] = { ...meta, dataURL: asset.dataURL };
        }
        return {
          ...p,
          source: document?.source ?? null,
          draft: document?.draft ?? null,
          draftBase: document?.draftBase ?? null,
          resourceFiles: resources,
        };
      });
    },
    draft(id, draft, base) {
      return write(async (t) => {
        const doc = await t.get("documents", id);
        if (!doc) throw new Error("Master document not found.");
        if (doc.draft === draft && doc.draftBase === base) return;
        doc.draft = draft;
        doc.draftBase = base;
        await t.put("documents", doc);
        await touch(t);
      });
    },
    async commitProject(project, expectedRevision, source, scenes, { preserveDraft = false } = {}) {
      const packed = await Promise.all(
        scenes.map(async ({ board, scene }) => ({ board, packed: await packScene(scene) })),
      );
      const resourcePack = await packScene({ ...emptyScene(), files: project.resourceFiles || {} });
      return write(async (t) => {
        const old = await t.get("projects", project.id);
        if (old && old.revision !== expectedRevision) {
          const error = new Error("This project changed in another window.");
          error.code = "PROJECT_CONFLICT";
          throw error;
        }
        for (const { board } of scenes) {
          const current = await t.get("boards", board.id);
          if (
            current?.projectId === project.id &&
            board.revision !== undefined &&
            current.revision !== board.revision
          ) {
            const error = new Error("A canvas changed while this project was being saved.");
            error.code = "PROJECT_CONFLICT";
            throw error;
          }
        }
        const oldDoc = await t.get("documents", project.id);
        if (old) {
          const versions = (await t.all("projectVersions"))
            .filter((v) => v.projectId === old.id)
            .sort((a, b) => a.createdAt - b.createdAt);
          await t.put("projectVersions", {
            id: uid(),
            projectId: old.id,
            createdAt: Date.now(),
            project: old,
            document: oldDoc || null,
            boards: (await t.all("boards")).filter((b) => b.projectId === old.id),
          });
          for (const v of versions.slice(0, Math.max(0, versions.length + 1 - HISTORY_LIMIT)))
            await t.delete("projectVersions", v.id);
        }
        const ids = new Set(packed.map((x) => x.board.id));
        if (old?.managed)
          for (const b of await t.all("boards"))
            if (b.projectId === old.id && !b.deletedAt && !ids.has(b.id)) {
              await snapshot(t, b);
              b.deletedAt = Date.now();
              await t.put("boards", b);
            }
        const { source: unused, resourceFiles, draft, draftBase, ...metadata } = project;
        const next = {
          ...metadata,
          resources: resourcePack.fileRefs,
          revision: (old?.revision ?? -1) + 1,
          updatedAt: Date.now(),
          createdAt: old?.createdAt || Date.now(),
        };
        await putAssets(t, resourcePack);
        await t.put("projects", next);
        await t.put("documents", {
          id: project.id,
          source,
          draft: preserveDraft ? (oldDoc?.draft ?? null) : null,
          draftBase: preserveDraft ? (oldDoc?.draftBase ?? null) : null,
        });
        const saved = [];
        for (const item of packed) {
          const existing = await t.get("boards", item.board.id);
          const b = {
            ...makeBoard(item.packed, item.board),
            ...existing,
            ...item.board,
            ...recordFor(item.packed),
            projectId: project.id,
            deletedAt: project.deletedAt || null,
            revision: (existing?.revision ?? -1) + 1,
            updatedAt: Date.now(),
            placeholder: false,
          };
          await putAssets(t, item.packed);
          await t.put("boards", b);
          saved.push(b);
        }
        await touch(t);
        return { project: next, boards: saved };
      });
    },
    projectHistory(id) {
      return read(["projectVersions"], async (t) =>
        (await t.all("projectVersions"))
          .filter((v) => v.projectId === id)
          .sort((a, b) => b.createdAt - a.createdAt),
      );
    },
    projectVersion(id) {
      return read(["projectVersions", "assets"], async (t) => {
        const v = await t.get("projectVersions", id);
        if (!v) throw new Error("Project version not found.");
        const scenes = [];
        for (const board of v.boards) scenes.push({ board, scene: await hydrate(t, board) });
        const resources = {};
        for (const [path, ref] of Object.entries(v.project.resources || {})) {
          const { assetKey, ...meta } = ref;
          resources[path] = { ...meta, dataURL: (await t.get("assets", assetKey)).dataURL };
        }
        return { ...v, scenes, resourceFiles: resources };
      });
    },
    projectMetadata(id, fields) {
      return write(async (t) => {
        const p = await t.get("projects", id);
        if (!p) throw new Error("Project not found.");
        Object.assign(p, fields);
        p.revision++;
        await t.put("projects", p);
        await touch(t);
        return p;
      });
    },
    async importArchive(data) {
      return write(async (t) => {
        const existing = new Map((await t.all("boards")).map((b) => [b.id, b]));
        const fresh =
          existing.size === 1 &&
          [...existing.values()][0].placeholder &&
          !(await t.all("folders")).length &&
          !(await t.all("revisions")).length;
        if (fresh) {
          await t.delete("boards", [...existing.keys()][0]);
          existing.clear();
        }
        const folderIds = new Map(data.folders.map((f) => [f.id, fresh ? f.id : uid()]));
        const boardIds = new Map(),
          projectIds = new Map(),
          unchanged = new Set();
        let added = 0,
          skipped = 0;
        const existingProjects = await t.all("projects"),
          docs = await t.all("documents");
        const incomingProjects = data.projects || [],
          incomingDocs = data.documents || [];
        const root = {
          id: uid(),
          title: `Restored ${new Date().toLocaleString()}`,
          parentId: null,
        };
        for (const p of incomingProjects.filter((p) => p.managed)) {
          const document = incomingDocs.find((d) => d.id === p.id);
          const same = existingProjects.find(
            (old) =>
              old.managed &&
              (old.id === p.id || old.importedFromId === p.id) &&
              Boolean(old.deletedAt) === Boolean(p.deletedAt) &&
              docs.find((d) => d.id === old.id)?.source === document?.source &&
              p.nodes.length === old.nodes.length &&
              p.nodes.every((n) => {
                const oldNode = old.nodes.find((x) => x.id === n.id),
                  incoming = data.boards.find((b) => b.id === n.boardId),
                  current = existing.get(oldNode?.boardId);
                return current && incoming && current.fingerprint === incoming.fingerprint;
              }),
          );
          const target = same?.id || (existingProjects.some((x) => x.id === p.id) ? uid() : p.id);
          projectIds.set(p.id, target);
          for (const b of data.boards.filter((b) => b.projectId === p.id)) {
            const node = p.nodes.find((n) => n.boardId === b.id),
              matching = same?.nodes.find((n) => n.id === node?.id);
            const old =
              (matching && existing.get(matching.boardId)) ||
              (same &&
                [...existing.values()].find(
                  (old) =>
                    old.projectId === same.id &&
                    (old.id === b.id || old.importedFromId === b.id) &&
                    old.fingerprint === b.fingerprint &&
                    Boolean(old.deletedAt) === Boolean(b.deletedAt),
                ));
            if (old && old.fingerprint === b.fingerprint) {
              boardIds.set(b.id, old.id);
              unchanged.add(b.id);
              skipped++;
            } else {
              boardIds.set(b.id, target !== p.id || existing.has(b.id) ? uid() : b.id);
              added++;
            }
          }
          if (!same) {
            await t.put("projects", {
              ...p,
              id: target,
              importedFromId: target !== p.id ? p.id : p.importedFromId,
              nodes: p.nodes.map((n) => ({ ...n, boardId: boardIds.get(n.boardId) })),
            });
            await t.put("documents", { ...document, id: target });
          }
        }
        for (const b of data.boards) {
          if (boardIds.has(b.id)) continue;
          const old = [...existing.values()].find(
            (x) =>
              (x.id === b.id || x.importedFromId === b.id) &&
              x.fingerprint === b.fingerprint &&
              Boolean(x.deletedAt) === Boolean(b.deletedAt),
          );
          if (old) {
            boardIds.set(b.id, old.id);
            unchanged.add(b.id);
            skipped++;
          } else {
            boardIds.set(b.id, existing.has(b.id) ? uid() : b.id);
            added++;
          }
        }
        if (added && data.boards.some((b) => !projectIds.has(b.projectId))) {
          if (!fresh) await t.put("folders", root);
          for (const f of data.folders)
            await t.put("folders", {
              ...f,
              id: folderIds.get(f.id),
              parentId: folderIds.get(f.parentId) || (fresh ? null : root.id),
            });
        }
        for (const asset of data.assets) await t.put("assets", asset);
        for (const b of data.boards) {
          const id = boardIds.get(b.id),
            old = existing.get(b.id),
            managed = projectIds.has(b.projectId);
          if (unchanged.has(b.id)) continue;
          await t.put("boards", {
            ...b,
            id,
            projectId: projectIds.get(b.projectId) || "my-sketches",
            importedFromId: id !== b.id ? b.id : b.importedFromId,
            placeholder: false,
            title: old && !managed ? `${b.title} (restored)` : b.title,
            folderId: managed ? null : folderIds.get(b.folderId) || (fresh ? null : root.id),
            thumbnail: null,
          });
        }
        const versions = await t.all("projectVersions");
        const versionKey = (v) =>
          `${v.projectId}:${v.document?.source}:${v.boards
            .map((b) => b.fingerprint)
            .sort()
            .join(":")}`;
        const versionKeys = new Set(versions.map(versionKey));
        for (const v of data.projectVersions || []) {
          const projectId = projectIds.get(v.projectId);
          if (!projectId) continue;
          for (const b of v.boards) if (!boardIds.has(b.id)) boardIds.set(b.id, uid());
          const copy = {
            ...v,
            id: uid(),
            projectId,
            project: {
              ...v.project,
              id: projectId,
              nodes: v.project.nodes.map((n) => ({ ...n, boardId: boardIds.get(n.boardId) })),
            },
            document: v.document && { ...v.document, id: projectId },
            boards: v.boards.map((b) => ({ ...b, id: boardIds.get(b.id), projectId })),
          };
          if (!versionKeys.has(versionKey(copy))) {
            await t.put("projectVersions", copy);
            versionKeys.add(versionKey(copy));
          }
        }
        for (const projectId of projectIds.values()) {
          const history = (await t.all("projectVersions"))
            .filter((v) => v.projectId === projectId)
            .sort((a, b) => b.createdAt - a.createdAt);
          for (const v of history.slice(HISTORY_LIMIT)) await t.delete("projectVersions", v.id);
        }
        const revisions = await t.all("revisions");
        const signatures = new Set(revisions.map((r) => `${r.boardId}:${r.fingerprint}`));
        for (const r of data.revisions) {
          const boardId = boardIds.get(r.boardId),
            signature = `${boardId}:${r.fingerprint}`;
          if (!signatures.has(signature)) {
            await t.put("revisions", { ...r, id: uid(), boardId });
            signatures.add(signature);
          }
        }
        // Imported histories obey the same bound as newly created histories.
        for (const boardId of new Set(boardIds.values())) {
          const rs = (await t.all("revisions"))
            .filter((r) => r.boardId === boardId)
            .sort((a, b) => b.createdAt - a.createdAt || b.revision - a.revision);
          for (const r of rs.slice(HISTORY_LIMIT)) await t.delete("revisions", r.id);
        }
        const state = await t.get("workspace", "state"),
          incoming = data.workspace.find((x) => x.id === "state");
        const libs = new Map((state.libraryItems || []).map((x) => [x.id, x]));
        const itemKey = ({ id, ...item }) => JSON.stringify(item);
        for (const item of incoming.libraryItems || []) {
          if (!libs.has(item.id)) libs.set(item.id, item);
          else if (![...libs.values()].some((old) => itemKey(old) === itemKey(item))) {
            const id = uid();
            libs.set(id, { ...item, id });
          }
        }
        state.libraryItems = [...libs.values()];
        state.changeSeq++;
        const importedOpen = incoming.openIds
          .map((id) => boardIds.get(id))
          .filter((id) => id && !data.boards.find((b) => boardIds.get(b.id) === id)?.deletedAt);
        state.openIds = [...new Set([...(fresh ? [] : state.openIds), ...importedOpen])];
        const tabs = (incoming.tabs || [])
          .map((tab) => ({
            ...tab,
            id: tab.kind === "markdown" ? projectIds.get(tab.id) : boardIds.get(tab.id),
          }))
          .filter((tab) => tab.id);
        state.tabs = [
          ...(fresh ? [] : state.tabs || []),
          ...tabs.filter(
            (tab) =>
              !(state.tabs || []).some(
                (old) => !fresh && old.kind === tab.kind && old.id === tab.id,
              ),
          ),
        ];
        if (fresh) state.activeDocument = projectIds.get(incoming.activeDocument) || null;
        if (fresh) {
          state.activeId = boardIds.get(incoming.activeId) || importedOpen[0] || null;
          state.theme = incoming.theme || state.theme;
        } else if (!state.activeId) state.activeId = importedOpen[0] || null;
        await t.put("workspace", state);
        await gc(t);
        return { added, skipped, fresh, boardIds: Object.fromEntries(boardIds) };
      });
    },
  };
  await write(async (t) => {
    if (!(await t.get("projects", "my-sketches")))
      await t.put("projects", {
        id: "my-sketches",
        title: "My sketches",
        managed: false,
        revision: 0,
        nodes: [],
        resources: {},
        createdAt: Date.now(),
        deletedAt: null,
      });
    for (const b of await t.all("boards"))
      if (!b.projectId) {
        b.projectId = "my-sketches";
        await t.put("boards", b);
      }
  });
  await api.expire();
  return api;
}
