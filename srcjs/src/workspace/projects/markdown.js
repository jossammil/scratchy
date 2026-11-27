// The master Markdown document. Headings are canvases and blocks are their
// elements; hidden scratchy:node/block comments give each a stable ID.
import { fromMarkdown } from "mdast-util-from-markdown";
import { toMarkdown } from "mdast-util-to-markdown";
import { parse as parseYaml, stringify as yaml } from "yaml";
import { uid } from "../model.js";

const markerRE = /^<!-- scratchy:(node|block) ([\w-]+)(?: ([\w -]+))? -->$/;
export const marker = (kind, id, flag = "") =>
  `<!-- scratchy:${kind} ${id}${flag ? ` ${flag}` : ""} -->`;
const plain = (n) => n.value ?? (n.children || []).map(plain).join(n.type === "list" ? "\n" : "");
const display = (n) =>
  n.type === "list"
    ? n.children
        .map((item, i) => `${n.ordered ? `${(n.start || 1) + i}.` : "•"} ${plain(item)}`)
        .join("\n")
    : n.type === "image"
      ? n.alt || "Image"
      : plain(n);
const links = (n) => [...(n.type === "link" ? [n.url] : []), ...(n.children || []).flatMap(links)];
function frontMatter(source) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(source);
  if (/^---\r?\n/.test(source) && !match) throw new Error("The YAML front matter is not closed.");
  const data = match ? parseYaml(match[1]) || {} : {};
  if (typeof data !== "object" || Array.isArray(data))
    throw new Error("Front matter must contain named settings.");
  return { data, offset: match?.[0].length || 0 };
}
export function parseMaster(source, { assignIds = false } = {}) {
  if (typeof source !== "string") throw new Error("A master document must be Markdown text.");
  let front = frontMatter(source),
    tree = fromMarkdown(source.slice(front.offset));
  const first = tree.children.find((n) => n.type !== "html" || !n.value.startsWith("<!--"));
  if (assignIds && first && first.type !== "heading") {
    source = source.slice(0, front.offset) + "\n# Overview\n\n" + source.slice(front.offset);
    front = frontMatter(source);
    tree = fromMarkdown(source.slice(front.offset));
  }
  // Put inline images on their own paragraphs so each image has an identity,
  // rather than silently dropping an image adjacent to ordinary body text.
  if (assignIds) {
    const images = tree.children
      .filter((n) => n.type === "paragraph" && n.children.length > 1)
      .flatMap((n) => n.children.filter((c) => c.type === "image"));
    if (images.length) {
      for (const img of images.reverse()) {
        const start = img.position.start.offset + front.offset,
          end = img.position.end.offset + front.offset;
        source = replace(source, start, end, `\n\n${source.slice(start, end)}\n\n`);
      }
      return parseMaster(source, { assignIds: true });
    }
  }
  const nodes = [],
    warnings = [],
    used = new Set(),
    inserts = [];
  let pending = null,
    current = null;
  for (const ast of tree.children) {
    const start = ast.position.start.offset + front.offset,
      end = ast.position.end.offset + front.offset;
    if (ast.type === "html") {
      const match = markerRE.exec(ast.value.trim());
      if (match) {
        pending = { kind: match[1], id: match[2], flag: match[3] || "", start, end };
        continue;
      }
      if (!ast.value.trim().startsWith("<!--"))
        warnings.push("HTML is preserved in the source and is not executed.");
      continue;
    }
    const kind = ast.type === "heading" ? "node" : "block";
    const identity =
      pending?.kind === kind
        ? pending
        : { id: uid(), kind, start, end: start, flag: "", missing: true };
    pending = null;
    if (used.has(identity.id))
      throw new Error(
        `Duplicate Scratchy ID ${identity.id}. Use Duplicate in the explorer, or remove copied ID comments before applying.`,
      );
    used.add(identity.id);
    if (assignIds && identity.missing)
      inserts.push({ start, text: `${marker(kind, identity.id)}\n` });
    const entry = {
      id: identity.id,
      start,
      end,
      markerStart: identity.start,
      markerEnd: identity.end,
      flag: identity.flag,
      ast,
      markdown: source.slice(start, end),
    };
    if (kind === "node") {
      const title = plain(ast).trim();
      if (!title) throw new Error("Give each heading a title.");
      const parent = [...nodes].reverse().find((n) => n.level < ast.depth);
      current = {
        ...entry,
        title,
        level: ast.depth,
        parentId: parent?.id || null,
        blocks: [],
        hidden: identity.flag.split(" ").includes("hidden"),
        include: !identity.flag.split(" ").includes("excluded"),
      };
      nodes.push(current);
    } else {
      if (!current) {
        warnings.push("Text before the first heading becomes an Overview canvas when applied.");
        continue;
      }
      const image =
        ast.type === "paragraph" && ast.children.length === 1 && ast.children[0].type === "image"
          ? ast.children[0]
          : null;
      const supported =
        ["paragraph", "list", "code"].includes(ast.type) &&
        !(
          ast.type === "list" &&
          ast.children.some((item) => item.children.some((child) => child.type !== "paragraph"))
        );
      if (!supported) warnings.push(`The ${ast.type} block is preserved as source text.`);
      if (/^\s*\|.*\|/m.test(entry.markdown) || /\$\$/.test(entry.markdown))
        warnings.push("Tables and equations are shown as source text in this release.");
      current.blocks.push({
        ...entry,
        kind: image ? "image" : supported ? ast.type : "unsupported",
        text: image ? image.alt || "Image" : supported ? display(ast) : entry.markdown,
        url: image?.url,
        links: [...new Set(links(ast))],
        supported,
      });
    }
  }
  if (inserts.length) {
    for (const insertion of inserts.reverse())
      source = source.slice(0, insertion.start) + insertion.text + source.slice(insertion.start);
    return parseMaster(source);
  }
  return {
    source,
    title: String(front.data.title || "Untitled project"),
    settings: front.data,
    nodes,
    warnings: [...new Set(warnings)],
  };
}
export const newMaster = (title = "New project") =>
  `---\n${yaml({ title })}---\n\n# Overview\n\nDescribe the project here.\n`;
export function setProjectTitle(source, title) {
  const { data, offset } = frontMatter(source);
  return `---\n${yaml({ ...data, title })}---\n${source.slice(offset)}`;
}
const replace = (source, start, end, text) => source.slice(0, start) + text + source.slice(end);
export function nodeRange(parsed, id, subtree = false) {
  const n = parsed.nodes.find((n) => n.id === id);
  if (!n) throw new Error("Canvas heading not found.");
  const next = parsed.nodes.find((x) => x.start > n.start && (!subtree || x.level <= n.level));
  return { node: n, start: n.markerStart, end: next?.markerStart ?? parsed.source.length };
}
export function renameNode(source, id, title) {
  const n = parseMaster(source).nodes.find((n) => n.id === id);
  if (!n) throw new Error("Canvas heading not found.");
  const value = title.replace(/\s+/g, " ").trim();
  if (!value) throw new Error("The canvas title cannot be empty.");
  const heading = toMarkdown({
    type: "root",
    children: [{ ...n.ast, children: [{ type: "text", value }] }],
  }).trimEnd();
  return replace(source, n.start, n.end, heading);
}
export function setNodeFlag(source, id, flag, value = true) {
  const n = parseMaster(source).nodes.find((n) => n.id === id);
  if (!n) throw new Error("Canvas heading not found.");
  const flags = new Set(n.flag.split(" ").filter(Boolean));
  if (value) flags.add(flag);
  else flags.delete(flag);
  return replace(source, n.markerStart, n.markerEnd, marker("node", id, [...flags].join(" ")));
}
function editInline(ast, text) {
  const old = plain(ast),
    leaves = [];
  const collect = (n) => {
    if (typeof n.value === "string") leaves.push(n);
    else (n.children || []).forEach(collect);
  };
  collect(ast);
  let prefix = 0,
    suffix = 0;
  while (prefix < old.length && prefix < text.length && old[prefix] === text[prefix]) prefix++;
  while (
    suffix < old.length - prefix &&
    suffix < text.length - prefix &&
    old.at(-suffix - 1) === text.at(-suffix - 1)
  )
    suffix++;
  const end = old.length - suffix,
    inserted = text.slice(prefix, text.length - suffix);
  let at = 0,
    done = false;
  for (const leaf of leaves) {
    const value = leaf.value,
      last = at + value.length;
    if (last >= prefix && at <= end && !done) {
      const from = Math.max(0, prefix - at),
        to = Math.min(value.length, Math.max(from, end - at));
      leaf.value = value.slice(0, from) + inserted + value.slice(to);
      done = true;
    } else if (at < end && last > prefix)
      leaf.value = value.slice(Math.min(value.length, end - at));
    at = last;
  }
  if (!leaves.length) ast.children = [{ type: "text", value: text }];
  return ast;
}
export function setBlockText(source, nodeId, blockId, text) {
  const parsed = parseMaster(source),
    node = parsed.nodes.find((n) => n.id === nodeId),
    block = node?.blocks.find((b) => b.id === blockId);
  if (!block) return appendText(source, nodeId, text, blockId);
  let ast = structuredClone(block.ast);
  if (block.kind === "code") ast.value = text;
  else if (block.kind === "list") {
    ast.children = text.split("\n").map((line, i) => {
      const value = line.replace(/^\s*(?:[•*+-]|\d+[.)])\s+/, ""),
        old = ast.children[i];
      return {
        type: "listItem",
        spread: false,
        children: [editInline(old?.children[0] || { type: "paragraph", children: [] }, value)],
      };
    });
  } else ast = editInline(ast, text);
  return replace(
    source,
    block.start,
    block.end,
    toMarkdown({ type: "root", children: [ast] }).trimEnd(),
  );
}
export function appendText(source, nodeId, text, id = uid()) {
  const range = nodeRange(parseMaster(source), nodeId),
    block = toMarkdown({
      type: "root",
      children: [{ type: "paragraph", children: [{ type: "text", value: text }] }],
    });
  return replace(source, range.end, range.end, `\n${marker("block", id)}\n${block}\n`);
}
export function removeBlock(source, nodeId, blockId) {
  const b = parseMaster(source)
    .nodes.find((n) => n.id === nodeId)
    ?.blocks.find((b) => b.id === blockId);
  return b ? replace(source, b.markerStart, b.end, "") : source;
}
export function addNode(source, title, parentId = null, id = uid()) {
  const parsed = parseMaster(source),
    parent = parsed.nodes.find((n) => n.id === parentId),
    level = parent ? parent.level + 1 : 1;
  if (level > 6)
    throw new Error("Markdown supports six heading levels. Choose a shallower parent.");
  const at = parent ? nodeRange(parsed, parentId, true).end : source.length;
  const heading = toMarkdown({
    type: "root",
    children: [{ type: "heading", depth: level, children: [{ type: "text", value: title }] }],
  });
  return replace(source, at, at, `\n${marker("node", id)}\n${heading}\n`);
}
export function moveNode(source, id, parentId = null, beforeId = null) {
  let parsed = parseMaster(source);
  const range = nodeRange(parsed, id, true);
  const children = parsed.nodes.filter((n) => n.start >= range.node.start && n.start < range.end);
  if (children.some((n) => n.id === parentId || n.id === beforeId))
    throw new Error("A project section cannot be moved inside itself.");
  const parent = parsed.nodes.find((n) => n.id === parentId),
    delta = (parent ? parent.level + 1 : 1) - range.node.level;
  if (children.some((n) => n.level + delta > 6))
    throw new Error("This move would exceed six Markdown heading levels.");
  let segment = source.slice(range.start, range.end);
  for (const n of [...children].reverse())
    segment = replace(
      segment,
      n.start - range.start,
      n.end - range.start,
      toMarkdown({ type: "root", children: [{ ...n.ast, depth: n.level + delta }] }).trimEnd(),
    );
  source = replace(source, range.start, range.end, "");
  parsed = parseMaster(source);
  const at = beforeId
    ? nodeRange(parsed, beforeId).start
    : parentId
      ? nodeRange(parsed, parentId, true).end
      : source.length;
  return replace(source, at, at, `\n${segment.trim()}\n\n`);
}
export function removeNode(source, id) {
  const r = nodeRange(parseMaster(source), id, true);
  return replace(source, r.start, r.end, "");
}
export function duplicateNode(source, id) {
  const parsed = parseMaster(source),
    r = nodeRange(parsed, id, true);
  let segment = source.slice(r.start, r.end);
  segment = segment.replace(
    /<!-- scratchy:(node|block) ([\w-]+)(?: ([\w -]+))? -->/g,
    (_, kind, old, flag) => marker(kind, uid(), flag),
  );
  const copy = parseMaster(segment).nodes[0];
  segment = renameNode(segment, copy.id, `${r.node.title} copy`);
  return replace(source, r.end, r.end, `\n${segment}\n`);
}
