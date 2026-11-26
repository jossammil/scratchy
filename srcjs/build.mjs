// Builds the Excalidraw editor bundle into inst/htmlwidgets/lib/excalidraw-widget.
//   cd srcjs && npm install && npm run build
import * as esbuild from "esbuild";
import { cpSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

// One version for the R package and the bundle: DESCRIPTION's.
const version = readFileSync("../DESCRIPTION", "utf8").match(/^Version:\s*(\S+)/m)[1];
const pkg = JSON.parse(readFileSync("package.json", "utf8"));
if (pkg.version !== version) {
  console.error(`srcjs/package.json is ${pkg.version} but DESCRIPTION is ${version}; make them match.`);
  process.exit(1);
}
const excalidraw = JSON.parse(readFileSync("node_modules/@excalidraw/excalidraw/package.json", "utf8")).version;

const out = "../inst/htmlwidgets/lib/excalidraw-widget";
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

await esbuild.build({
  entryPoints: { "excalidraw-widget": "src/index.js" },
  bundle: true,
  minify: true,
  format: "esm",
  splitting: true,
  outdir: out,
  chunkNames: "chunks/[name]-[hash]",
  target: ["es2020"],
  jsx: "automatic",
  conditions: ["production"],
  define: {
    "process.env.NODE_ENV": '"production"',
    "process.env.IS_PREACT": '"false"',
    __EXCALIDRAWER_VERSION__: JSON.stringify(version),
  },
  banner: { js: `/*! excalidrawer ${version} (MIT). Bundles Excalidraw ${excalidraw} (MIT), React (MIT) and their dependencies: see excalidraw-widget.js.LEGAL.txt and the package's inst/COPYRIGHTS. */` },
  loader: { ".woff2": "file", ".ttf": "file", ".png": "file", ".svg": "file" },
  legalComments: "external",
  logLevel: "info",
});

// Open Peeps generator for the native renderer (runs in R's V8).
await esbuild.build({
  entryPoints: ["src/peeps.js"],
  bundle: true,
  minify: true,
  format: "iife",
  target: ["es2020"],
  outfile: "../inst/js/peeps.js",
  legalComments: "eof",
  logLevel: "info",
});

// Excalidraw's fonts, minus the 12 MB CJK font (loaded from the CDN if needed).
const fonts = "node_modules/@excalidraw/excalidraw/dist/prod/fonts";
for (const family of readdirSync(fonts)) {
  if (family === "Xiaolai") continue;
  cpSync(`${fonts}/${family}`, `${out}/fonts/${family}`, { recursive: true });
}

// Page used by R (through chromote) for Mermaid conversion and exact exports.
writeFileSync(`${out}/headless.html`, `<!doctype html>
<html><head><meta charset="utf-8"><link rel="stylesheet" href="excalidraw-widget.css"></head>
<body><script type="module" src="excalidraw-widget.js"></script></body></html>
`);

// The sticker libraries' list for the browser, from inst/stickers/manifest.csv.
function parseCsv(text) {
  const rows = [];
  let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { row.push(field); field = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(field); field = "";
      if (row.some((f) => f !== "")) rows.push(row);
      row = [];
    } else field += ch;
  }
  if (field !== "" || row.length) { row.push(field); rows.push(row); }
  return rows;
}
const [head, ...rows] = parseCsv(readFileSync("../inst/stickers/manifest.csv", "utf8"));
const stickers = rows.map((r) => {
  const o = Object.fromEntries(head.map((h, i) => [h, r[i]]));
  return { library: o.library, title: o.title, author: o.author, description: o.description,
           license: o.license, source: o.source, file: `${o.library}.excalidrawlib` };
});
writeFileSync("../inst/stickers/index.json", JSON.stringify(stickers, null, 2) + "\n");

// What denr and the site read to know which editor they have.
writeFileSync(`${out}/VERSION.json`, JSON.stringify({ excalidrawer: version, excalidraw }, null, 2) + "\n");

console.log("built", out, version);
