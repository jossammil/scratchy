# Projects, master Markdown and slides

Implemented on `codex/panels` as the next part of the [multi-board workspace](implementation-plan.md). The persistent project explorer and the All boards collection share the same saved canvases. Open tabs remain independent editing sessions. This is a standalone browser feature; R, Sketch Studio and denr keep their existing interfaces.

## Using projects

The left explorer lists projects and their nested canvases. Use **＋ Project**, then **＋ Canvas**, or import an ordinary `.md` file. A parent section has its own overview canvas as well as its children. The explorer's action buttons offer rename, child canvas, duplicate, move, slide inclusion, title visibility, reflow and trash. Drag a section onto another to nest it, or use **Move section…** to choose its parent and sibling order. Moves reject cycles and more than six heading levels.

Toggle the explorer with the top-left button or Cmd/Ctrl+\\. Resize its right edge with a pointer, or focus the separator and use the arrow keys. Width, collapsed state and expanded sections persist. The explorer becomes a drawer on narrow screens. **All boards** and Cmd/Ctrl+P retain the gallery, label search, pins and legacy folders.

Existing drawings migrate into **My sketches** without changing their scenes. **Link to Markdown** explicitly converts that collection: text becomes linked annotations in place, existing folders become parent overview canvases, and existing titles are hidden on the original canvases. Hand drawings, image files, positions and text styles remain intact. Conversion is recorded in project history.

## One source document per project

**Source** opens a master Markdown tab. Every heading is a canvas; heading depth establishes its parent. Body paragraphs, simple lists, code and images become elements on that heading's canvas. Code is displayed and is never executed. A block containing a single web link gets a native canvas link. Multiple inline links remain in the source, with plain display text on the canvas. Unsupported blocks remain in the source and display as text; tables, equations, Quarto options and R execution are future work.

```md
---
title: Research project
---
# Overview

Describe the project.

## Methods

- Collect data
- Review results

# Findings

![Results](assets/results.png)
```

Scratchy adds hidden `<!-- scratchy:node ID -->` and `<!-- scratchy:block ID -->` comments. Keep these comments with their headings and blocks when rearranging the source. Their identities preserve the matching canvases, drawings and text positions through renames and moves. Duplicate sections through the explorer, or remove copied ID comments; duplicate IDs are rejected. Removing an ID intentionally creates a new identity.

Inline images adjacent to text are separated into their own linked image blocks when applied.

Source edits remain a browser-saved draft until **Apply to canvases**. The preview reports new and removed canvases and unsupported content. Invalid YAML and duplicate IDs retain the draft without changing the saved project. **Discard draft** restores the current source. Text before the first heading becomes an Overview canvas when applied.

Canvas text changes flow back into the master after editing finishes, including new annotations and shape labels. Deleting body text removes its block; Undo restores it under the same identity. Deleting a title hides the title while retaining the canvas. Source edits retain drawing elements, positions, fonts and colors. **Reflow Markdown text** explicitly resets generated text positions; hand drawings and annotations remain in place.

**Add image…** embeds an image under a relative `assets/` path and applies the source and image together. Referenced images must be bundled with the project; Scratchy does not silently fetch remote resources. Missing images show a placeholder and block slide exports.

## Presentations

New canvases have a 1280 × 720 slide frame. Slides follow heading order, depth first. Exclude a canvas through its actions, or present just one section and its descendants. **Present** opens a read-only browser slideshow with arrow keys, Page Up/Down, Home/End, fullscreen and Escape.

**Export…** offers:

- **PowerPoint**: editable text boxes with their canvas positions, colors, sizes and fonts; drawings and images are embedded as transparent raster layers in stacking order. The target computer needs the named fonts for matching metrics. Choose Arial for more portable editable text. PowerPoint is an editable approximation; it does not preserve every Excalidraw text/font detail.
- **PDF**: rendered slide frames at double resolution, retaining the browser's canvas appearance. Pages use each frame's size.
- **Portable project ZIP**: `project.md`, readable nested `canvases/` files, relative images and a recovery manifest. It includes the current project and excludes historical versions and trash.

Drafts must be applied or discarded before presenting/exporting. Each deck uses one frozen snapshot. Content outside a slide frame is identified for review and clipped at the frame boundary. Full workspace ZIP remains the recovery format for project history, board history, trash, drafts, libraries and tabs. Both ZIP types restore from **All boards → Restore ZIP…**. Old version-one backups still import. Restoring preserves existing projects; conflicts become separate projects with independent canvas IDs, and repeat imports skip identical copies. Ordinary files can also be opened directly; importing `.md` creates a new project. The manifest is the authoritative recovery source, so externally edited exported files should be imported individually rather than edited inside a recovery ZIP.

## Storage and conflicts

IndexedDB version 3 adds projects, documents and whole-project versions to the existing board, asset and workspace stores. Original `kv` values remain intact. Project changes run through per-project queues and one transaction covering the master, hierarchy, scenes, assets and bounded history (50 versions). Revision comparisons protect both the project and its canvases. Concurrent stale edits recover a whole project rather than splitting a linked canvas from its source. An unchanged stale editor refreshes from the current project.

If canvases change after a draft begins, the source editor shows the current source beside the draft. Choose **Keep current source** or **Apply this draft**; earlier source and drawings remain in project history. Removing a section preserves the prior project version and trashes its canvases. Whole-project trash expires after 30 days. Source IDs and images survive portable and full backups; file handles and session Undo stacks do not.

Project and presentation code lives in its own `srcjs/src/workspace/projects/` and `presentations/` folders. Export libraries load on demand and are cached for offline use in the service worker's background pass. The shared editor only adds the optional `frameId` export argument. No R signatures changed. The site build includes a generated `workspace/THIRD-PARTY-NOTICES.txt` for bundled dependencies.

## Verification commands

From `srcjs/`:

```sh
npm ci
WITH_R=1 npm test
npm run build
npm run site
npm run e2e
BROWSER=webkit npm run e2e
npm run e2e:workspace
BROWSER=webkit npm run e2e:workspace
npm run e2e:projects
BROWSER=webkit npm run e2e:projects
```

From the repository root, run `Rscript -e 'devtools::test()'`. See [verification.md](verification.md) for observed results and environment limits. [roadmap.md](roadmap.md) holds the remaining work.
