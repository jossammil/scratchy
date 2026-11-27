import test from "node:test";
import assert from "node:assert/strict";
import {
  parseMaster,
  newMaster,
  renameNode,
  setBlockText,
  moveNode,
  duplicateNode,
  setNodeFlag,
  appendText,
  removeBlock,
} from "../src/workspace/projects/markdown.js";
import {
  projectScene,
  binding,
  cloneScene,
  adoptText,
} from "../src/workspace/presentations/layout.js";
import { emptyScene, packScene } from "../src/workspace/model.js";
import { createBackup, readBackup } from "../src/workspace/backup.js";
import { unzipSync, strFromU8 } from "fflate";

test("master headings get stable identities and preserve a parent overview", () => {
  const p = parseMaster(
    "---\ntitle: Research\n---\n\n# Overview\n\nA paragraph.\n\n## Methods\n\n- One\n- Two\n\n### Detail\n\n```r\nplot(1:5)\n```\n\n# Results\n",
    { assignIds: true },
  );
  assert.equal(p.title, "Research");
  assert.equal(p.nodes.length, 4);
  assert.equal(p.nodes[1].parentId, p.nodes[0].id);
  assert.equal(p.nodes[0].blocks[0].text, "A paragraph.");
  assert.deepEqual(parseMaster(p.source), p);
  assert.equal(p.nodes[2].blocks[0].kind, "code");
  assert.equal(p.nodes[1].blocks[0].text, "• One\n• Two");
  const initial = parseMaster("Text first.\n\n# Next", { assignIds: true });
  assert.equal(initial.nodes[0].title, "Overview");
  assert.equal(initial.nodes[0].blocks[0].text, "Text first.");
});
test("renaming, nesting, moving and duplicating retain source content and IDs", () => {
  const p = parseMaster("# A\n\nA body.\n\n## Child\n\nChild body.\n\n# B\n", { assignIds: true });
  let source = renameNode(p.source, p.nodes[0].id, "A renamed");
  source = moveNode(source, p.nodes[0].id, p.nodes[2].id);
  let q = parseMaster(source);
  assert.equal(q.nodes[0].title, "B");
  assert.equal(q.nodes[1].id, p.nodes[0].id);
  assert.equal(q.nodes[1].parentId, p.nodes[2].id);
  assert.equal(q.nodes[2].blocks[0].text, "Child body.");
  assert.throws(() => moveNode(source, q.nodes[1].id, q.nodes[2].id), /inside itself/);
  q = parseMaster(duplicateNode(source, p.nodes[0].id));
  assert.equal(q.nodes.length, 5);
  assert.equal(new Set(q.nodes.map((n) => n.id)).size, 5);
  assert.equal(q.nodes[3].title, "A renamed copy");
  assert.notEqual(q.nodes[3].blocks[0].id, p.nodes[0].blocks[0].id);
});
test("canvas text edits preserve links, simple lists, code and literal Markdown characters", () => {
  const p = parseMaster(
      "# A\n\nRead [the docs](https://example.com) now.\n\n- First\n- Second\n\n```r\nx <- 1\n```\n",
      { assignIds: true },
    ),
    n = p.nodes[0];
  let source = setBlockText(p.source, n.id, n.blocks[0].id, "Read the docs today.");
  assert.match(source, /\[the docs\]\(https:\/\/example.com\)/);
  source = setBlockText(source, n.id, n.blocks[1].id, "• First changed\n• Second\n• Third");
  assert.equal(parseMaster(source).nodes[0].blocks[1].kind, "list");
  source = setBlockText(source, n.id, n.blocks[2].id, "x <- 2");
  assert.match(source, /```r\nx <- 2/);
  source = appendText(source, n.id, "# literal [text] *asterisk*", "annotation");
  assert.equal(parseMaster(source).nodes.length, 1);
  assert.equal(parseMaster(source).nodes[0].blocks.at(-1).text, "# literal [text] *asterisk*");
  source = removeBlock(source, n.id, "annotation");
  assert.equal(parseMaster(source).nodes[0].blocks.length, 3);
});
test("invalid IDs, malformed YAML and excessive nesting are rejected without a partial parse", () => {
  const p = parseMaster(newMaster("Test"), { assignIds: true });
  assert.throws(
    () => parseMaster(p.source + p.source.slice(p.source.indexOf("<!--"))),
    /Duplicate Scratchy ID/,
  );
  assert.throws(() => parseMaster("---\ntitle: [\n---\n# A"));
  assert.throws(() => parseMaster("---\ntitle: Test"), /not closed/);
  const deep = parseMaster("# A\n\n## B\n\n###### C\n\n# D", { assignIds: true });
  assert.throws(() => moveNode(deep.source, deep.nodes[0].id, deep.nodes[3].id), /six/);
});
test("an image adjacent to paragraph text gets a separate linked image block", () => {
  const p = parseMaster("# Slide\n\nBody text.\n![Results](assets/results.png)\nMore text.", {
    assignIds: true,
  });
  assert.deepEqual(
    p.nodes[0].blocks.map((b) => b.kind),
    ["paragraph", "image", "paragraph"],
  );
  assert.equal(p.nodes[0].blocks[1].url, "assets/results.png");
  assert.deepEqual(parseMaster(p.source), p);
});
test("source refresh retains drawings, annotation positions and styles; reflow is explicit", () => {
  const p = parseMaster("# Title\n\nBody", { assignIds: true }),
    n = p.nodes[0];
  let scene = projectScene("project", n);
  const body = scene.elements.find((e) => binding(e)?.kind === "paragraph");
  body.x = 400;
  body.y = 370;
  body.fontSize = 40;
  body.strokeColor = "#e03131";
  scene.elements.push({ id: "drawing", type: "rectangle", x: 300, y: 400, width: 40, height: 60 });
  const q = parseMaster(setBlockText(p.source, n.id, n.blocks[0].id, "New body")).nodes[0],
    updated = projectScene("project", q, scene),
    changed = updated.elements.find((e) => e.id === body.id);
  assert.equal(changed.x, 400);
  assert.equal(changed.y, 370);
  assert.equal(changed.fontSize, 40);
  assert.equal(changed.strokeColor, "#e03131");
  assert.deepEqual(
    updated.elements.find((e) => e.id === "drawing"),
    scene.elements.at(-1),
  );
  assert.equal(
    projectScene("project", q, scene, { reflow: true }).elements.find((e) => e.id === body.id).x,
    64,
  );
  assert.equal(
    projectScene(
      "project",
      parseMaster(setNodeFlag(p.source, n.id, "hidden")).nodes[0],
      scene,
    ).elements.some((e) => binding(e)?.kind === "title"),
    false,
  );
  const adopted = adoptText(
    { ...emptyScene(), elements: [body] },
    "project",
    n.id,
    new Map([[body.id, n.blocks[0].id]]),
  );
  assert.equal(binding(adopted.elements[0]).role, "annotation");
  const clone = cloneScene(updated, "other", "copy");
  assert.equal(clone.elements[0].id, "slide_copy");
  assert.equal(binding(clone.elements.find((e) => e.type === "text")).nodeId, "copy");
});
test("project ZIP carries ordinary Markdown, nested canvases and complete recovery metadata", async () => {
  const parsed = parseMaster("---\ntitle: Portable\n---\n# Parent\n\n## Child", {
      assignIds: true,
    }),
    nodes = parsed.nodes.map((n, i) => ({
      id: n.id,
      parentId: n.parentId,
      title: n.title,
      level: n.level,
      boardId: `board-${i}`,
    }));
  const boards = [];
  for (const [i, node] of parsed.nodes.entries()) {
    const packed = await packScene(projectScene("project", node));
    boards.push({
      id: `board-${i}`,
      title: node.title,
      fileName: `${node.title}.excalidraw`,
      projectId: "project",
      folderId: null,
      revision: 0,
      createdAt: 1,
      updatedAt: 1,
      snapshotAt: 1,
      deletedAt: null,
      ...packed,
    });
  }
  const data = {
    boards,
    folders: [],
    revisions: [],
    assets: [],
    projects: [{ id: "project", title: "Portable", managed: true, nodes, resources: {} }],
    documents: [{ id: "project", source: parsed.source, draft: null }],
    projectVersions: [],
    workspace: [{ id: "state", openIds: ["board-0"], activeId: "board-0", libraryItems: [] }],
  };
  const zip = await createBackup(data, { projectId: "project" }),
    files = unzipSync(new Uint8Array(await zip.arrayBuffer()));
  assert.equal(strFromU8(files["project.md"]), parsed.source);
  assert.equal(Object.keys(files).filter((p) => p.startsWith("canvases/")).length, 2);
  assert.ok(Object.keys(files).some((p) => /canvases\/Parent--[^/]+\/Child--/.test(p)));
  assert.equal((await readBackup(zip)).projects[0].nodes[1].parentId, nodes[0].id);
});
