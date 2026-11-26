import { test } from "node:test";
import assert from "node:assert/strict";
import { sceneData, elementsBounds, placeRight, swapChart, chartIdOf, bytesToBase64 } from "../src/core/scene.js";

const box = (id, x, y, w = 10, h = 10, extra = {}) => ({ id, type: "rectangle", x, y, width: w, height: h, ...extra });

test("sceneData accepts JSON text, objects and nothing", () => {
  assert.deepEqual(sceneData('{"elements":[{"id":"a"}]}').elements, [{ id: "a" }]);
  assert.equal(sceneData(null).type, "excalidraw");
  assert.deepEqual(sceneData("").elements, []);
  assert.equal(sceneData({ appState: { viewBackgroundColor: "#fff" } }).appState.viewBackgroundColor, "#fff");
});

test("bounds skip deleted elements and handle negative sizes", () => {
  assert.equal(elementsBounds([]), null);
  const b = elementsBounds([box("a", 0, 0), box("b", 50, 20, -10, 5), box("c", 500, 500, 1, 1, { isDeleted: true })]);
  assert.deepEqual(b, { x0: 0, y0: 0, x1: 60, y1: 25 });
});

test("placeRight puts new elements 60px right of the drawing, tops aligned", () => {
  const placed = placeRight([box("a", 0, 100, 200, 50)], [box("n", -30, -30, 20, 20)]);
  assert.equal(placed[0].x, 260);
  assert.equal(placed[0].y, 100);
  assert.deepEqual(placeRight([], [box("n", 5, 5)]), [box("n", 5, 5)]);
});

test("swapChart keeps hand drawings and puts the new chart where the old one was", () => {
  const tag = { customData: { excalidrawer: { chart: "main" } } };
  const existing = [box("old1", 100, 100, 50, 50, tag), box("hand", 0, 0)];
  const { elements, hadOld } = swapChart(existing, [box("new1", 0, 0, 80, 40)], "main");
  assert.equal(hadOld, true);
  assert.deepEqual(elements.map((e) => e.id), ["hand", "new1"]);
  assert.equal(elements[1].x, 100);
  assert.equal(chartIdOf(elements[1]), "main");
  assert.equal(swapChart([box("hand", 0, 0)], [box("n", 0, 0)], "c").hadOld, false);
});

test("bytesToBase64 matches Node's encoder", () => {
  const bytes = new Uint8Array(100000).map((_, i) => (i * 7) % 256);
  assert.equal(bytesToBase64(bytes), Buffer.from(bytes).toString("base64"));
});
