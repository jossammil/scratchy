// Builds the website into site-dist/ (published with GitHub Pages):
//   index.html, app.js, app.css     the editor, from site/
//   editor/                         the bundle, copied from inst/htmlwidgets/lib/excalidraw-widget
//   stickers/                       the sticker libraries, from inst/stickers
//   sw.js                           the service worker, with the file lists filled in
// The R documentation (pkgdown) goes into site-dist/r/ separately (pages.yaml).
//   node srcjs/tools/build-site.mjs    (from the package root or srcjs/)
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const at = (...p) => join(root, ...p);
const out = at("site-dist");

const version = readFileSync(at("DESCRIPTION"), "utf8").match(/^Version:\s*(\S+)/m)[1];
const lib = at("inst/htmlwidgets/lib/excalidraw-widget");
const built = JSON.parse(readFileSync(join(lib, "VERSION.json"), "utf8"));
if (built.scratchy !== version) {
  console.error(`The editor bundle is ${built.scratchy} but DESCRIPTION is ${version}: run npm run build in srcjs first.`);
  process.exit(1);
}

// Keep an existing R documentation build (site-dist/r) when rebuilding locally.
const keepR = existsSync(join(out, "r")) ? join(root, ".site-r-keep") : null;
if (keepR) { rmSync(keepR, { recursive: true, force: true }); cpSync(join(out, "r"), keepR, { recursive: true }); }
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
if (keepR) { cpSync(keepR, join(out, "r"), { recursive: true }); rmSync(keepR, { recursive: true, force: true }); }

cpSync(lib, join(out, "editor"), { recursive: true, filter: (src) => !/headless\.html$/.test(src) });
cpSync(at("inst/stickers"), join(out, "stickers"), { recursive: true, filter: (src) => !/manifest\.csv$/.test(src) });
for (const f of ["app.js", "app.css", "manifest.webmanifest", "icon-192.png", "icon-512.png"]) cpSync(at("site", f), join(out, f));
cpSync(at("inst/COPYRIGHTS"), join(out, "COPYRIGHTS.txt"));
cpSync(at("LICENSE.md"), join(out, "LICENSE.md"));
writeFileSync(join(out, ".nojekyll"), "");

const fill = (text) => text.replaceAll("{{VERSION}}", version).replaceAll("{{EXCALIDRAW}}", built.excalidraw);
writeFileSync(join(out, "index.html"), fill(readFileSync(at("site/index.template.html"), "utf8")));

// The editor's core: the entry and the chunks it imports statically (not
// the ones it loads with import(), such as Mermaid and the languages).
const core = new Set();
const visit = (rel) => {
  if (core.has(rel)) return;
  core.add(rel);
  const code = readFileSync(join(out, rel), "utf8");
  for (const m of code.matchAll(/(?:from|import)\s*"(\.\/[^"]+\.js)"/g)) {
    visit(relative(out, resolve(dirname(join(out, rel)), m[1])));
  }
};
visit("editor/excalidraw-widget.js");

const walk = (dir) => readdirSync(dir).flatMap((f) => {
  const p = join(dir, f);
  return statSync(p).isDirectory() ? walk(p) : [relative(out, p)];
});
const all = walk(out).filter((f) => !f.startsWith("r/") && !/(^|\/)\.nojekyll$|\.LEGAL\.txt$|^sw\.js$/.test(f));
const CORE = ["./", "index.html", "app.js", "app.css", "manifest.webmanifest", "icon-192.png",
              "editor/excalidraw-widget.css", "editor/VERSION.json", "stickers/index.json", ...core];
const coreSet = new Set(CORE);
const REST = all.filter((f) => !coreSet.has(f)).sort();
// The cache name changes whenever any file does, so a rebuild is never served stale.
const hash = createHash("sha256");
for (const f of [...all].sort()) hash.update(f).update(readFileSync(join(out, f)));
writeFileSync(join(out, "sw.js"), fill(readFileSync(at("site/sw.template.js"), "utf8"))
  .replace("{{BUILD}}", hash.digest("hex").slice(0, 10))
  .replace("{{CORE}}", JSON.stringify(CORE))
  .replace("{{REST}}", JSON.stringify(REST)));

const size = (files) => (files.reduce((a, f) => a + (f === "./" ? 0 : statSync(join(out, f)).size), 0) / 1e6).toFixed(1);
console.log(`site-dist: scratchy ${version} (Excalidraw ${built.excalidraw}); ` +
            `${CORE.length} files (${size(CORE)} MB) cached at install, ${REST.length} more (${size(REST)} MB) in the background`);
