# Implementation and verification

The subsequent [projects and slides implementation](projects-and-slides.md) extends this release with a persistent explorer, master Markdown and presentations. The details below record the original workspace milestone.

## Accepted release

Named board tabs; All boards; nested folders; pins; thumbnails; per-board editing sessions; searchable titles and drawing labels; version history; recoverable trash; full ZIP backup and additive restore. Keep production deployment on main and develop on `codex/panels`.

Approved choices: ZIP rather than folder mirroring; preserve Undo for open tabs during a visit; preserve current drawings during ZIP restore; include history, trash, libraries and layout in full backups. Asset search, PDF and the other follow-ups are in the roadmap.

## Code organization

`srcjs/src/workspace/` contains domain rules, the IndexedDB adapter, ZIP handling, the standalone UI and its styles. The site bootstrap calls `mountWorkspace()`; the site builder bundles this folder separately from the editor and includes it in the startup cache. The workspace is not added to the R widget bundle.

The shared editor receives additive `initialViewport`, `onStateChange(data)` and `onLibraryChange(items)` options. `controller.set({ name })` changes export naming without remounting. Existing callers retain their defaults. `window.scratchy.ctrl` and `.doc` refer to the active session; `.workspace` exposes the standalone host for diagnostics and browser verification.

## Persistence and recovery

The `scratchy` IndexedDB database upgrades from version 1 to 2. The legacy `kv` store remains intact. Initialization copies its scene, name and theme together with a workspace marker in one transaction, so retries do not duplicate a migrated drawing. A blocked upgrade asks other windows to close; save errors expose retry and drawing-download actions.

Boards have stable IDs, independently versioned content, file references and viewport state. Folders and workspace layout are separate records. SHA-256 image keys avoid storing the same data URL in every historical scene. Excalidraw file IDs and metadata are preserved when scenes are reassembled. Garbage collection removes assets no longer referenced by current or historical drawings.

Save queues are per session and debounced 300 ms. Switching, closing and backup capture the editor directly and await saves. Only the visible editor receives keyboard commands. Inactive open editors retain Undo; closed editors are released. Reload restores tabs lazily and starts new Undo sessions. External writable handles exist only in memory and never follow duplicates or restored boards.

Version history keeps the latest 50 entries. Changed work produces a checkpoint every five minutes; clearing, restoring and trashing also preserve the current drawing. Trash expires after 30 days, with cleanup at workspace startup. Viewport/selection changes do not create history. Revision comparisons prevent stale browser windows from overwriting newer content: incoming edits become a recovered board instead.

Archives use `scratchy-workspace` format version 1. Current drawings are ordinary `.excalidraw` files; the manifest and shared assets carry organization, history, trash, libraries and layout. Validation checks records, relationships, fingerprints and image content before an import transaction. Existing boards are preserved; identical imports are skipped and conflicting versions get separate IDs. External file permissions and Undo stacks are excluded.

## Build and checks

From the repository root:

```sh
cd srcjs
npm ci
npm test
npm run build
npm run site
npm run e2e
BROWSER=webkit npm run e2e
npm run e2e:workspace
BROWSER=webkit npm run e2e:workspace
```

The unit tests cover search, folder rules, image preservation and archive integrity. Browser tests exercise the real IndexedDB implementation, migration, isolated editing, history, restore conflicts, storage failure, import/export, keyboard controls, offline behavior and responsive layout. CI repeats the builds and checks committed editor artifacts. Run `Rscript -e 'devtools::test()'` for shared-editor regressions; optional Chrome tests require the usual local dependencies.

Verify rebuilding the committed editor produces no additional diff. In a clean checkout, the commands above must install from the lockfile and reproduce the site. Test previews remain local to the feature branch until merge/publication is explicitly requested.

## Practical limits

Browser storage is not an off-device backup. ZIP status records an export initiated by the application; browsers do not confirm that a downloaded file was retained. Abrupt termination before a debounced write completes can lose those latest unsaved changes. Open editor instances consume memory; close unused tabs to release them. Undo is session-only. Full archives can be large, although internal image storage is shared. Review `verification.md` for the checks actually completed on this checkout.
