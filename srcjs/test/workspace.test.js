import test from "node:test";
import assert from "node:assert/strict";
import { zipSync, unzipSync, strToU8, strFromU8 } from "fflate";
import { emptyScene, packScene, unpackScene, searchBoards, folderDescendants, validFolderMove } from "../src/workspace/model.js";
import { createBackup, readBackup } from "../src/workspace/backup.js";

const imageScene = () => ({ ...emptyScene(), elements: [{ id: "image-1", type: "image", fileId: "file-1", customData: { scratchy: { chart: "original" } } }], files: { "file-1": { id: "file-1", mimeType: "image/png", created: 123, dataURL: "data:image/png;base64,aGVsbG8=" } } });
async function fixture() {
  const packed = await packScene(imageScene());
  const { assets, ...content } = packed;
  return { boards: [{ id: "board-1", title: "Original", fileName: "Original.excalidraw", folderId: "folder-1", pinned: true, revision: 2, createdAt: 1, updatedAt: 2, snapshotAt: 2, deletedAt: null, ...content }],
    folders: [{ id: "folder-1", title: "Research", parentId: null }],
    revisions: [{ id: "version-1", boardId: "board-1", revision: 1, createdAt: 1, scene: content.scene, fileRefs: content.fileRefs, fingerprint: content.fingerprint }],
    assets, workspace: [{ id: "state", openIds: ["board-1"], activeId: "board-1", libraryItems: [{ id: "library-1", status: "unpublished", created: 1, elements: [{ id: "library-shape", type: "rectangle", x: 0, y: 0, width: 100, height: 60 }] }], changeSeq: 3 }] };
}
test("image assets deduplicate by content without changing IDs, metadata or customData", async () => {
  const original = imageScene(), packed = await packScene(original);
  const second = await packScene({ ...original, files: { another: { ...original.files["file-1"], id: "another" } } });
  assert.equal(packed.assets[0].key, second.assets[0].key);
  assert.deepEqual(unpackScene(packed, new Map(packed.assets.map((a) => [a.key, a]))), original);
});
test("search requires every word, handles accents, ranks exact titles and ignores trash", () => {
  const boards = [
    { id: "1", title: "Overview", updatedAt: 10, labels: [{ id: "label", text: "Café retry policy" }] },
    { id: "2", title: "retry café", updatedAt: 1, labels: [] },
    { id: "3", title: "retry café", deletedAt: 5, labels: [] },
  ];
  const found = searchBoards(boards, "retry cafe");
  assert.deepEqual(found.map((r) => r.board.id), ["2", "1"]);
  assert.equal(found[1].matches[0].id, "label");
  assert.equal(searchBoards(boards, "missing cafe").length, 0);
});
test("nested folder moves reject cycles", () => {
  const folders = [{ id: "a", parentId: null }, { id: "b", parentId: "a" }, { id: "c", parentId: "b" }];
  assert.deepEqual([...folderDescendants(folders, "a")], ["a", "b", "c"]);
  assert.equal(validFolderMove(folders, "a", "c"), false);
  assert.equal(validFolderMove(folders, "c", "a"), true);
  assert.equal(validFolderMove(folders, "c", "unknown"), false);
});
test("full ZIP round trip includes ordinary drawings, assets, history and organization", async () => {
  const data = await fixture(), blob = await createBackup(data), restored = await readBackup(blob);
  assert.equal(restored.boards[0].title, "Original");
  assert.equal(restored.revisions.length, 1);
  assert.deepEqual(restored.assets, data.assets);
  assert.deepEqual(restored.workspace[0].libraryItems, data.workspace[0].libraryItems);
  const files = unzipSync(new Uint8Array(await blob.arrayBuffer()));
  const ordinary = JSON.parse(strFromU8(files["boards/board-1.excalidraw"]));
  assert.deepEqual(ordinary, imageScene());
});
test("damaged images, changed drawings and unsupported manifests fail before import", async () => {
  const blob = await createBackup(await fixture());
  const source = unzipSync(new Uint8Array(await blob.arrayBuffer()));
  const key = Object.keys(source).find((k) => k.startsWith("assets/"));
  await assert.rejects(readBackup(zipSync({ ...source, [key]: strToU8("damaged") })), /damaged image/);
  await assert.rejects(readBackup(zipSync({ ...source, "boards/board-1.excalidraw": strToU8(JSON.stringify(emptyScene())) })), /damaged .excalidraw/);
  const manifest = JSON.parse(strFromU8(source["manifest.json"])); manifest.version = 99;
  await assert.rejects(readBackup(zipSync({ ...source, "manifest.json": strToU8(JSON.stringify(manifest)) })), /unsupported/);
});
test("malformed folder trees and dangling asset references fail validation", async () => {
  const data = await fixture(); data.folders[0].parentId = "folder-1";
  await assert.rejects(readBackup(await createBackup(data)), /folder cycle/);
  const valid = unzipSync(new Uint8Array(await (await createBackup(await fixture())).arrayBuffer()));
  const manifest = JSON.parse(strFromU8(valid["manifest.json"])); manifest.data.boards[0].fileRefs["file-1"].assetKey = "missing";
  valid["manifest.json"] = strToU8(JSON.stringify(manifest));
  await assert.rejects(readBackup(zipSync(valid)), /missing image/);
});
