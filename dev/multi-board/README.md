# Scratchy multi-board workspace

Design notes for the standalone website's workspace. R widgets, Sketch Studio and denr use the shared editor without it.

- [Projects and slides](projects-and-slides.md): the explorer, master Markdown, presentations, and the storage, history and recovery rules for boards and projects.
- [Roadmap](roadmap.md): what comes next.

Tabs are open editing sessions; **All boards** (Cmd/Ctrl+P) holds the saved collection, and closing a tab never deletes a board. Each open board keeps its own editor, so switching keeps Undo during a visit. The left explorer adds projects whose canvases follow the headings of one Markdown document.

Browser autosave, saving an external file (Cmd/Ctrl+S) and a workspace backup are separate. **Back up ZIP** exports drawings plus organization and recovery data; **Restore ZIP…** validates the whole archive first, keeps existing drawings, and makes separate boards for conflicting versions. Drawings in the ZIP's `boards/` folder open directly in Excalidraw.

## Comparison provenance

[Excaliboard](https://excaliboard.ayush101.dev/#features) and its [changelog](https://excaliboard.ayush101.dev/changelog.html) document multiple boards, folders, search, history, trash, backup and collection export. [Syndra](https://syndra.nl/) exposes projects, folders, nested canvases, a minimap and diagramming shortcuts. These inspired the workspace and roadmap; their implementations were not copied.
