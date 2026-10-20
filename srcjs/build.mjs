// Builds the Excalidraw editor bundle into inst/htmlwidgets/lib/excalidraw-widget.
//   cd srcjs && npm install && npm run build
import * as esbuild from "esbuild";
import { cpSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";

const out = "../inst/htmlwidgets/lib/excalidraw-widget";
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

await esbuild.build({
  entryPoints: { "excalidraw-widget": "src/widget.jsx" },
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
  },
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

console.log("built", out);
