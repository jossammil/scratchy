import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { toObsidian, fromObsidian, isObsidian } from "../src/extras/obsidian.js";
import { presets, restyleElements } from "../src/extras/restyle.js";

const fixture = (f) => readFileSync(new URL(`./fixtures/${f}`, import.meta.url), "utf8");

test("reads the .excalidraw.md that R writes", () => {
  const fromR = JSON.parse(fromObsidian(fixture("r-scene.excalidraw.md")));
  const plain = JSON.parse(fixture("r-scene.excalidraw"));
  assert.equal(fromR.elements.length, plain.elements.length);
  assert.ok(fromR.elements.some((e) => e.type === "text" && e.text === "Ünïcode ✓ text"));
});

test("writes .excalidraw.md that reads back, compressed or not", () => {
  const json = fixture("r-scene.excalidraw");
  assert.equal(fromObsidian(toObsidian(json)), json);
  assert.equal(fromObsidian(toObsidian(json, { compress: false })).trim(), json.trim());
  assert.match(toObsidian(json), /excalidraw-plugin: parsed/);
  assert.match(toObsidian(json), /Idea \^/);
  assert.ok(isObsidian("a.excalidraw.md") && !isObsidian("a.md"));
  assert.throws(() => fromObsidian("# just notes"), /no Excalidraw drawing/);
});

test("R reads the .excalidraw.md written here", { skip: !process.env.WITH_R && "set WITH_R=1 to run (needs R)" }, () => {
  const dir = mkdtempSync(join(tmpdir(), "exr-"));
  const file = join(dir, "from-js.excalidraw.md");
  writeFileSync(file, toObsidian(fixture("r-scene.excalidraw")));
  const out = execFileSync("Rscript", ["-e", `devtools::load_all("${new URL("../..", import.meta.url).pathname}", quiet = TRUE); cat(length(read_excalidraw("${file}")$elements))`]).toString();
  assert.equal(Number(out.trim().split(/\s+/).pop()), JSON.parse(fixture("r-scene.excalidraw")).elements.length);
});

test("presets match the R package and restyle like exc_restyle()", () => {
  assert.deepEqual(Object.keys(presets), ["whiteboard", "xkcd", "blueprint", "chalkboard", "pencil", "marker"]);
  const els = [
    { id: "r", type: "rectangle", strokeColor: "#1e1e1e", backgroundColor: "#ffec99", fillStyle: "solid", roughness: 1, strokeWidth: 2, width: 100, height: 50 },
    { id: "b", type: "rectangle", strokeColor: "#1971c2", backgroundColor: "transparent", fillStyle: "solid", roughness: 1, strokeWidth: 2, width: 100, height: 50 },
    { id: "t", type: "text", strokeColor: "#1e1e1e", fontFamily: 5, text: "hi" },
    { id: "dot", type: "ellipse", strokeColor: "#1e1e1e", backgroundColor: "#1e1e1e", fillStyle: "solid", width: 6, height: 6 },
    { id: "img", type: "image", strokeColor: "#1e1e1e" },
  ];
  const { elements, background, textChanged } = restyleElements(els, "chalkboard");
  const by = Object.fromEntries(elements.map((e) => [e.id, e]));
  assert.equal(background, "#2f3d33");
  assert.equal(by.r.strokeColor, "#f1f3f5");   // dark ink becomes chalk
  assert.equal(by.r.fillStyle, "hachure");
  assert.equal(by.r.roughness, 2);
  assert.equal(by.b.strokeColor, "#1971c2");   // colours stay
  assert.equal(by.b.fillStyle, "solid");       // no fill, no change
  assert.equal(by.dot.fillStyle, "solid");     // small dots stay solid
  assert.equal(by.t.fontFamily, 5);
  assert.equal(by.t.customData.scratchy.font, "Architects Daughter");
  assert.equal(by.img, els[4]);
  assert.ok(textChanged);
  const only = restyleElements(els, "xkcd", new Set(["r"])).elements;
  assert.equal(only[1], els[1]);
  assert.equal(only[0].roughness, 2);
});
