# Scratchy multi-board workspace

Development branch: `codex/panels`. The workspace is a standalone-browser feature; R widgets, Sketch Studio and denr continue to use the shared editor without workspace UI.

- [Earlier plan](previous-plan.md): preserved from the "Plan Scratchy feature additions" conversation, November 26, 2026. That plan proposed this folder but did not create it.
- [Implementation and verification](implementation-plan.md): accepted scope, architecture, defaults, executable checks and known limits.
- [Projects and slides](projects-and-slides.md): persistent explorer, linked Markdown, portable projects and presentations.
- [Roadmap](roadmap.md): subsequent work, separate from the first release.

The left project explorer now provides persistent navigation; Markdown headings and canvases share one outline. See [Projects and slides](projects-and-slides.md) for usage and synchronization rules.

The core idea is unchanged: tabs are open editing sessions, while All boards contains the saved collection. Closing a tab does not delete a board. Compared with the earlier plan, open boards retain separate editor instances so switching preserves Undo during a visit.

## Using the workspace

Choose **All boards** or press Cmd/Ctrl+P. Create drawings and nested folders, search titles and drawing text, pin boards, and reopen closed tabs. Board actions provide rename, duplicate, folder moves, history and trash. Folder deletion moves its contents up instead of deleting drawings. Drag and drop has keyboard-accessible alternatives.

Browser autosave, an external file saved with Cmd/Ctrl+S, and a workspace backup are separate. **Back up ZIP** exports drawings plus organization and recovery data. **Restore ZIP** validates the whole archive before importing, keeps existing drawings, and makes separate boards for conflicting versions. Drawings in `boards/` also open directly in Excalidraw.

## Comparison provenance

[Excaliboard](https://excaliboard.ayush101.dev/#features) and its [changelog](https://excaliboard.ayush101.dev/changelog.html) document multiple boards, folders, search, history, trash, backup and collection export. [Syndra](https://syndra.nl/) exposes projects, folders, nested canvases, a minimap and diagramming shortcuts. These inspired the workspace and roadmap; their implementations were not copied. Scratchy already supplies Mermaid, stickers, presets, animation, Obsidian files and R export tools. R D2 produces an SVG image; browser D2 and diagram-source editing remain roadmap work.
