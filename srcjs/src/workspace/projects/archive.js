import { createBackup, readBackup } from "../backup.js";
export async function projectArchive(workspace, projectId) {
  await workspace.flushAll(); await workspace.projects.manager.idle();
  const data = await workspace.store.dump(), p = data.projects.find((p) => p.id === projectId);
  if (!p?.managed || p.deletedAt) throw new Error("Choose an active Markdown project to export.");
  const doc = data.documents.find((d) => d.id === projectId); if (doc?.draft !== null) throw new Error("Apply or discard the master draft before exporting the project.");
  data.boards = data.boards.filter((b) => b.projectId === projectId && !b.deletedAt).map((b) => ({ ...b, folderId: null }));
  data.projects = [p]; data.documents = [doc]; data.revisions = []; data.projectVersions = []; data.folders = [];
  const ids = new Set(data.boards.map((b) => b.id)), used = new Set();
  for (const record of [...data.boards, { fileRefs: p.resources || {} }]) for (const ref of Object.values(record.fileRefs || {})) used.add(ref.assetKey);
  data.assets = data.assets.filter((a) => used.has(a.key));
  data.workspace = data.workspace.map((state) => ({ ...state, openIds: state.openIds.filter((id) => ids.has(id)), activeId: ids.has(state.activeId) ? state.activeId : data.boards[0]?.id || null, activeDocument: null, tabs: (state.tabs || []).filter((t) => t.kind === "canvas" ? ids.has(t.id) : t.id === projectId), lastBackupAt: null, lastBackupSeq: -1 }));
  return createBackup(data, { projectId });
}
export { readBackup };
