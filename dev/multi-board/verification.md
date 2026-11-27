# Verification record

Verified the working implementation on `codex/panels`, based on `465d501`.

## Projects and slides verification (November 27, 2026)

The extension described in [projects-and-slides.md](projects-and-slides.md) was verified on the same local branch.

| Check | Result |
|---|---|
| JavaScript unit tests, `WITH_R=1 npm test` | 22 passed, including the R/JavaScript round trip. |
| Project acceptance suite | 19 checks passed in Chromium 158 and 19 in WebKit 27.2. |
| Existing workspace suite | 17 checks passed in each engine. |
| Existing editor suite | 13 checks passed in each engine. |
| Browser total | 98 checks passed across both engines. |
| R tests | 320 assertions passed; zero failures, the existing shiny build-version warning, three optional skips. |
| Independent source copy | A fresh `npm ci`, unit tests, editor/site builds and all 98 browser checks passed in `/private/tmp/scratchy-projects-clean-tbxscqbc`. No development node_modules or generated site files were copied into that build. |
| Reproducibility | The editor (225 files), native JS (9), stickers (14) and site (258, excluding R docs) matched the independently built output byte for byte. |
| Visual checks | Inspected desktop and 390 × 844 mobile source views and rendered browser slides. |
| Export contents | Parsed actual PPTX ZIP/XML for editable text and five slide parts; opened the generated PDF with pdf-lib and verified five 960 × 540 pages. |

Project checks exercise stable nested identities, preservation of drawing positions/styles and mounted sessions, native text entry, annotation deletion/Undo, title hiding, invalid drafts across reload, draft/current-source conflict review, outline changes and duplication, relative images, portable ZIP idempotence and conflict isolation, slide inclusion/order/navigation, missing-image blocking, viewport changes without history entries, whole-project recovery/history/trash, unchanged legacy appearance, responsive navigation, lazy tab restore, and full ZIP recovery including trashed canvases.

The final clean-build comparison followed the last source changes; the project suite was repeated after the slideshow rendering/loading-state adjustment. R tests ran after the editor build completed, so generated files remained available throughout the run. Installation reported the repository's existing React/Radix peer warnings and completed successfully.

PowerPoint output was inspected structurally; it was not manually opened in desktop PowerPoint. Font metrics depend on the target computer's installed fonts. PDF uses rendered pages. Quarto/R execution, live filesystem mirroring and broader Markdown rendering remain roadmap work. This is a local implementation, with no commit, merge or publication performed.

## Original workspace milestone checks

| Check | Result |
|---|---|
| JavaScript unit tests with `WITH_R=1 npm test` | 15 passed; includes the R/JavaScript Obsidian round trip. |
| Workspace acceptance suite, Chromium 158 | 17 passed. |
| Workspace acceptance suite, WebKit 27.2 | 17 passed. |
| Existing editor regressions, Chromium 158 | 13 passed. |
| Existing editor regressions, WebKit 27.2 | 13 passed. |
| R package tests, `devtools::test()` | 320 assertions passed, zero failures, one environment warning, three optional tests skipped. |
| Fresh source snapshot | Lockfile install, unit tests, editor build, site build, and all 60 browser checks passed without copying development node_modules or generated site files. |
| Generated-file comparison | Editor bundle directory (225 files), native JS (9), stickers (14), and website (250, excluding R documentation) matched the fresh build byte for byte. |
| Whitespace checks | `git diff --check` passed. |
| Visual review | Inspected the desktop editor and collection dialog in the in-app browser. Narrow-screen layout also passed browser acceptance checks at 390 × 844. |

The workspace suite covers a blocked IndexedDB upgrade, legacy drawing/image/customData preservation, independent Undo and viewport state, close/reopen, duplication without inherited file permissions, rename without remounting, file-download fallback, ordinary image drops, nested folders, label search, history preview/restore, trash expiry and asset cleanup, full ZIP restore, repeated/conflicting imports, concurrent browser windows, failed IndexedDB transactions with recovery download/retry, bounded history, 1,000 small boards, ten open editors, lazy reload and offline search.

The R warning says the installed shiny package was built with R 4.5.2. Two optional tests skipped because chromote could not be loaded, and one skipped because its presentation dependency was not installed. Browser tests separately exercised the shared JavaScript editor. Actual OS file-picker permissions, installed-PWA launch from the OS, and a physical iPhone were not manually tested. denr's vendored copy was not changed as part of this standalone-site work.

The fresh source snapshot was assembled from the modified tracked files and new source files in a temporary directory, with no `.git`, node_modules or copied site-dist. It is an independent build of the uncommitted implementation, not a claim that a new Git commit was created. npm reported the existing React/Radix peer warnings during installation; installation and builds completed successfully.

## Delivery state

Source, tests, generated editor artifacts and planning documents are present locally on `codex/panels`. The existing earlier plan is preserved in `previous-plan.md`; deferred features remain in `roadmap.md`. Production Pages deployment remains on main. No merge or publication was performed.
