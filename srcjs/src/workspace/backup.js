// Workspace ZIP archives: ordinary .excalidraw files and project.md for
// people, plus manifest.json and assets/ for a complete, validated restore.
import { zip, unzip, strToU8, strFromU8 } from "fflate";
import { digest, packScene, unpackScene, HISTORY_LIMIT } from "./model.js";
import { parseMaster } from "./projects/markdown.js";

const archive = (files) =>
  new Promise((resolve, reject) =>
    zip(files, { level: 6 }, (error, data) => (error ? reject(error) : resolve(data))),
  );
const expand = (bytes) =>
  new Promise((resolve, reject) =>
    unzip(bytes, (error, data) => (error ? reject(error) : resolve(data))),
  );
const safeId = (id) => typeof id === "string" && /^[a-zA-Z0-9_-]{1,160}$/.test(id);
const fail = (message) => {
  throw new Error(`The workspace backup is invalid: ${message}`);
};

export async function createBackup(data, { projectId = null } = {}) {
  const files = {},
    assets = new Map(data.assets.map((a) => [a.key, a]));
  const manifest = {
    format: "scratchy-workspace",
    version: data.projects ? 2 : 1,
    exportedAt: Date.now(),
    data: structuredClone(data),
    paths: {},
  };
  manifest.data.boards = data.boards.map(({ thumbnail, ...board }) => board);
  manifest.data.assets = data.assets.map((a) => ({ key: a.key }));
  for (const asset of data.assets) files[`assets/${asset.key}.txt`] = strToU8(asset.dataURL);
  const slug = (s) =>
    s
      .normalize("NFKD")
      .replace(/[^a-zA-Z0-9_-]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 60) || "canvas";
  const project = data.projects?.find((p) => p.id === projectId);
  const nodePath = (node) => {
    const parts = [`${slug(node.title)}--${node.id.slice(0, 8)}`];
    let parent = node.parentId;
    while (parent) {
      const n = project.nodes.find((n) => n.id === parent);
      if (!n) break;
      parts.unshift(`${slug(n.title)}--${n.id.slice(0, 8)}`);
      parent = n.parentId;
    }
    return `canvases/${parts.join("/")}.excalidraw`;
  };
  for (const b of data.boards) {
    const node = project?.nodes.find((n) => n.boardId === b.id),
      path = node ? nodePath(node) : `boards/${b.id}.excalidraw`;
    manifest.paths[b.id] = path;
    files[path] = strToU8(JSON.stringify(unpackScene(b, assets), null, 2));
  }
  for (const p of data.projects || []) {
    const doc = data.documents?.find((d) => d.id === p.id);
    if (!doc?.source) continue;
    const prefix = projectId ? "" : `projects/${p.id}/`;
    files[`${prefix}project.md`] = strToU8(doc.source);
    for (const [path, ref] of Object.entries(p.resources || {})) {
      if (/^(?:\/|\\)|(^|[\\/])\.\.([\\/]|$)/.test(path) || /[\\\x00]/.test(path))
        throw new Error("An image resource has an unsafe path.");
      const value = assets.get(ref.assetKey)?.dataURL;
      if (!value) throw new Error("A project image is missing.");
      const split = value.indexOf(","),
        base64 = value.slice(0, split).endsWith(";base64");
      files[`${prefix}${path}`] = base64
        ? Uint8Array.from(atob(value.slice(split + 1)), (c) => c.charCodeAt(0))
        : strToU8(decodeURIComponent(value.slice(split + 1)));
    }
  }
  files["manifest.json"] = strToU8(JSON.stringify(manifest));
  files["README.txt"] = strToU8(
    "Scratchy workspace backup\n\nOpen files in boards/ in any Excalidraw editor. Restore this whole ZIP in Scratchy's All boards panel to recover folders, history, trash, tabs and libraries. assets/ and manifest.json hold recovery data. External file permissions and Undo sessions are not included.\n",
  );
  return new Blob([await archive(files)], { type: "application/zip" });
}

// Validate every record, image and ordinary drawing before any IndexedDB write.
export async function readBackup(value) {
  let files, manifest;
  try {
    files = await expand(
      value instanceof Uint8Array ? value : new Uint8Array(await value.arrayBuffer()),
    );
    manifest = JSON.parse(strFromU8(files["manifest.json"]));
  } catch {
    fail("the ZIP or manifest could not be read.");
  }
  if (manifest.format !== "scratchy-workspace" || ![1, 2].includes(manifest.version))
    fail("unsupported backup format or version.");
  const data = manifest.data;
  for (const table of ["boards", "folders", "revisions", "assets", "workspace"])
    if (!Array.isArray(data?.[table])) fail(`missing ${table}.`);
  for (const table of ["boards", "folders", "revisions"]) {
    const ids = data[table].map((r) => r.id);
    if (ids.some((id) => !safeId(id)) || new Set(ids).size !== ids.length)
      fail(`invalid or repeated ${table} IDs.`);
  }
  const state = data.workspace.find((s) => s.id === "state");
  if (!state || !Array.isArray(state.openIds) || !Array.isArray(state.libraryItems))
    fail("missing workspace layout or library.");
  if (state.libraryItems.some((item) => !safeId(item.id) || !Array.isArray(item.elements)))
    fail("invalid imported library.");
  const folderIds = new Set(data.folders.map((f) => f.id)),
    boardIds = new Set(data.boards.map((b) => b.id));
  for (const f of data.folders) {
    if (typeof f.title !== "string" || (f.parentId !== null && !folderIds.has(f.parentId)))
      fail("invalid folder.");
    const seen = new Set([f.id]);
    let parent = f.parentId;
    while (parent) {
      if (seen.has(parent)) fail("folder cycle.");
      seen.add(parent);
      parent = data.folders.find((x) => x.id === parent).parentId;
    }
  }
  const keys = new Set();
  data.assets = await Promise.all(
    data.assets.map(async (ref) => {
      if (typeof ref.key !== "string" || !/^[a-f0-9]{64}$/.test(ref.key) || keys.has(ref.key))
        fail("invalid image ID.");
      keys.add(ref.key);
      const bytes = files[`assets/${ref.key}.txt`];
      if (!bytes) fail("missing image.");
      const dataURL = strFromU8(bytes);
      if ((await digest(dataURL)) !== ref.key) fail("damaged image.");
      return { key: ref.key, dataURL };
    }),
  );
  const assets = new Map(data.assets.map((a) => [a.key, a]));
  data.projects ||= [];
  data.documents ||= [];
  data.projectVersions ||= [];
  const versionBoards = data.projectVersions.flatMap((v) => v.boards || []);
  for (const record of [...data.boards, ...data.revisions, ...versionBoards]) {
    if (
      !Number.isSafeInteger(record.revision) ||
      record.revision < 0 ||
      !Number.isFinite(record.createdAt)
    )
      fail("invalid version metadata.");
    if (
      !record.scene ||
      !Array.isArray(record.scene.elements) ||
      typeof record.fileRefs !== "object" ||
      record.fileRefs === null
    )
      fail("invalid saved drawing.");
    for (const ref of Object.values(record.fileRefs))
      if (!assets.has(ref.assetKey)) fail("a drawing refers to a missing image.");
    const packed = await packScene(unpackScene(record, assets));
    if (packed.fingerprint !== record.fingerprint) fail("damaged drawing content.");
    if ("boardId" in record) {
      if (!boardIds.has(record.boardId)) fail("history refers to a missing board.");
    } else if (data.boards.includes(record)) {
      if (
        typeof record.title !== "string" ||
        typeof record.fileName !== "string" ||
        (record.folderId !== null && !folderIds.has(record.folderId))
      )
        fail("invalid board metadata.");
      if (record.deletedAt !== null && !Number.isFinite(record.deletedAt))
        fail("invalid trash date.");
      if (!Number.isFinite(record.updatedAt) || !Number.isFinite(record.snapshotAt))
        fail("invalid board dates.");
      try {
        const ordinary = JSON.parse(
          strFromU8(files[manifest.paths?.[record.id] || `boards/${record.id}.excalidraw`]),
        );
        if ((await packScene(ordinary)).fingerprint !== record.fingerprint)
          fail("drawing and recovery data disagree.");
      } catch {
        fail("missing or damaged .excalidraw file.");
      }
      record.labels = packed.labels;
      record.thumbnail = null;
    }
  }
  const projectIds = new Set();
  const validateProject = (p, doc, historical = false) => {
    if (!safeId(p.id) || !Array.isArray(p.nodes) || typeof p.title !== "string")
      fail("invalid project metadata.");
    const ids = new Set(p.nodes.map((n) => n.id));
    if (ids.size !== p.nodes.length) fail("duplicate project nodes.");
    for (const n of p.nodes)
      if (
        !safeId(n.id) ||
        !safeId(n.boardId) ||
        (n.parentId !== null && !ids.has(n.parentId)) ||
        (!historical && !boardIds.has(n.boardId))
      )
        fail("invalid project hierarchy.");
    for (const ref of Object.values(p.resources || {}))
      if (!assets.has(ref.assetKey)) fail("a project refers to a missing image.");
    if (p.managed) {
      if (typeof doc?.source !== "string") fail("missing master Markdown.");
      let parsed;
      try {
        parsed = parseMaster(doc.source);
      } catch {
        fail("invalid master Markdown.");
      }
      if (
        parsed.nodes.length !== p.nodes.length ||
        parsed.nodes.some(
          (n) => !ids.has(n.id) || p.nodes.find((x) => x.id === n.id).parentId !== n.parentId,
        )
      )
        fail("Markdown and project hierarchy disagree.");
    }
  };
  for (const p of data.projects) {
    if (projectIds.has(p.id)) fail("duplicate project IDs.");
    projectIds.add(p.id);
    validateProject(
      p,
      data.documents.find((d) => d.id === p.id),
    );
  }
  for (const v of data.projectVersions) {
    if (!projectIds.has(v.projectId) || !Array.isArray(v.boards)) fail("invalid project history.");
    validateProject(v.project, v.document, true);
  }
  if (
    state.openIds.some((id) => !boardIds.has(id)) ||
    (state.activeId !== null && !boardIds.has(state.activeId))
  )
    fail("tabs refer to missing boards.");
  for (const id of boardIds)
    if (data.revisions.filter((r) => r.boardId === id).length > HISTORY_LIMIT)
      fail("too many historical versions.");
  return data;
}
