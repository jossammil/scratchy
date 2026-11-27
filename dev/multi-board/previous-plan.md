# Scratchy multi-board workspace

**Start with named board tabs in the standalone browser editor.** A user should be able to draw an overview, open a second board for a detail sketch, switch between them, and reopen Scratchy offline with both drawings intact. Linked child boards and side-by-side editing are useful follow-ups, and both can build on the same board storage.

## What the comparison showed

| Project | What it offers | What that suggests for Scratchy |
|---|---|---|
| **Scratchy 0.1.0** | The browser editor autosaves one scene and its filename in IndexedDB. Scratchy already has editable Mermaid diagrams, sticker libraries, Obsidian files, animated SVGs, and R chart and slide exports. Its R D2 helper embeds a rendered SVG. [Browser source](https://github.com/jossammil/scratchy/blob/465d501440f8af545458c23c45309147e62acd23/site/app.js) · [R D2 implementation](https://github.com/jossammil/scratchy/blob/465d501440f8af545458c23c45309147e62acd23/R/d2.R) | The immediate gap is keeping several drawings available. Today, **New drawing** resets the active canvas, and **Open** loads into that same slot. |
| **Excaliboard** | Folders, pinned boards, thumbnails, search inside drawings, a keyboard switcher, per-board history, recoverable trash, folder mirroring, ZIP backup, and folder-to-PDF export. [Feature tour](https://excaliboard.ayush101.dev/#features) · [Developer’s extension listing](https://chromewebstore.google.com/detail/excaliboard/oninpelcdhnmoenohnkoilllhgadchbo) | Adopt its distinction between closing a board and losing access to it. Tabs handle the drawings in use, while an **All boards** list makes every saved drawing reachable. |
| **Syndra** | Its creator describes nested canvases for subprocesses, actions on drawn objects, peer-to-peer collaboration, Mermaid and D2 editing, and image and video support. The creator also notes limited testing of diagram-to-source round trips. [Syndra](https://syndra.nl/) · [Creator’s walkthrough and discussion](https://www.reddit.com/r/SideProject/comments/1y1rxsh/i_made_an_excalidraw_variant_that_scratches_my/) | The strongest fit is **open a detail board from a shape**. A chart, process step, or diagram node could lead to supporting work, with a breadcrumb back to the overview. |

## Deliverable on `codex/panels`

The checkout was clean on the existing local `codex/panels` branch. Its head matched GitHub’s `main` at `465d501` on November 26, 2026. The selected deliverable is **research and planning**. The proposed folder has not yet been created.

Create `dev/multi-board/` on `codex/panels`. The repository already excludes `dev/` from R package builds. Put three documents there:

- `README.md` — the source-linked comparison, including which features Scratchy already provides in the browser versus R and which peer features are documented by their creators.
- `roadmap.md` — the prioritized milestones below, with a user workflow and completion criteria for each.
- `implementation-plan.md` — storage migration, editor lifecycle, file handling, offline build changes, and test cases. Verify the planning diff is confined to the new folder on `codex/panels`.

## Feature roadmap

1. **Named boards and tabs.** Create, rename, duplicate, switch, and close tabs. Reopen closed tabs from **All boards**. Move unwanted boards to recoverable trash. Restore open tabs and the active board after reload. Opening an existing drawing creates a board.
2. **Find and back up a collection.** Add folders, pins, thumbnails, and a keyboard switcher that searches board titles and text labels. Export and restore a workspace ZIP containing ordinary `.excalidraw` files and a manifest for names, order, and relationships. Deliver backup before automatic folder mirroring.
3. **Link an overview to its details.** Add **Create detail board** to a selected shape. Use stable board IDs so renaming either drawing preserves the link. Show the parent path and a return action. A Scratchy-specific example is an R-generated chart whose annotated point opens a board explaining the underlying result.
4. **Compare two boards.** Add **Open beside** for comparing a draft and revision or a chart and its detail board. Give each pane its own viewport and route keyboard commands and exports to the focused pane. Follow with ordered board export for reports or slides, building on Scratchy’s existing R presentation tools.

## Programming plan for the first milestone

- **Migrate the existing drawing first.** Upgrade the browser’s IndexedDB with per-board records keyed by stable IDs and a workspace record for tab order and selection. Import the existing `scene` and `name` together in one transaction, including embedded images. Preserve the global theme. Make the upgrade safe to retry and surface storage failures with a file-download recovery action.
- **Give each board an isolated editing session.** Keep one editor mounted for the active tab. Before switching, capture the outgoing scene directly from the controller and await its save. Bind delayed callbacks to their originating board ID, then destroy the old controller and mount the destination board. Scratchy’s current `setScene()` adds files to the live editor and records an undo step, so reusing it alone could mix image assets or undo histories across boards. [Shared editor controller](https://github.com/jossammil/scratchy/blob/465d501440f8af545458c23c45309147e62acd23/srcjs/src/core/mount.jsx)
- **Make browser autosave and file saving distinct.** Show whether the active board is saved in this browser. Keep external file handles and unsaved-to-file indicators board-specific. Route **Open**, dropped drawing files, and installed-app file launches through the same board-import path. Keep library imports as library actions. **Save** and **Save as** operate on the selected board, and a duplicate gets its own identity and file destination.
- **Keep the first integration in the standalone site.** Use the existing `Scratchy.mount()` controller and native `.excalidraw` format. Add the workspace modules to the site build and its offline startup cache. The first milestone requires no new public R functions. Document the later integration points for the R widget, Sketch Studio, and denr.

## Acceptance checks

- Upgrade a browser containing a named drawing with an embedded image. Verify the migrated board opens intact, survives an offline reload, and appears exactly once.
- Draw on A, immediately switch to B, edit B, then return to A. Verify both drawings, images, backgrounds, filenames, and exports. Undo on B must never reveal content from A.
- Close and reopen a tab, duplicate a board, and trash and restore it. Confirm each action has a distinct result and saving a duplicate cannot overwrite the original file.
- Exercise file-picker and download-based browsers, keyboard-only navigation, and a narrow screen. Simulate a failed storage write and two browser tabs editing the same board. Require a visible recovery path that preserves the user’s drawing.
- Run the existing JavaScript tests and extend the Chromium and WebKit browser checks for these workflows when implementation begins.

