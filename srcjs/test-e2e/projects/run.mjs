// Real-browser acceptance checks for workspace persistence and recovery.
import { chromium, webkit } from "playwright";
import http from "node:http";
import { unzipSync, strFromU8 } from "fflate";
import { PDFDocument } from "pdf-lib";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const site = path.resolve(fileURLToPath(new URL("../../../site-dist/", import.meta.url)));
const types = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2",
  ".webmanifest": "application/manifest+json",
};
const server = http.createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    if (pathname === "/seed.html") {
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end("<!doctype html><title>Workspace fixture</title>");
      return;
    }
    let file = path.resolve(site, `.${pathname}`);
    if (!file.startsWith(site)) throw new Error("outside test site");
    if ((await stat(file)).isDirectory()) file = path.join(file, "index.html");
    res.writeHead(200, {
      "Content-Type": types[path.extname(file)] || "application/octet-stream",
      "Cache-Control": "no-cache",
    });
    res.end(await readFile(file));
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
const engine = process.env.BROWSER === "webkit" ? "webkit" : "chromium";
const browser =
  engine === "webkit"
    ? await webkit.launch()
    : await chromium.launch({ channel: "chrome" }).catch(() => chromium.launch());
const context = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  acceptDownloads: true,
});
const page = await context.newPage(),
  errors = [];
context.on("page", (p) => p.on("pageerror", (error) => errors.push(error.message)));
page.on("pageerror", (error) => errors.push(error.message));
const expect = (condition, message) => {
  if (!condition) throw new Error(message);
};
const ready = async (p = page) => {
  await p.waitForFunction(() => window.scratchy?.workspace, null, { timeout: 30000 });
};
const scene = () =>
  page.evaluate(() => window.scratchy.ctrl.getSceneData().elements.filter((e) => !e.isDeleted));
const add = async (id, p = page) => {
  await p.evaluate(async (id) => {
    await window.scratchy.ctrl.add({
      elements: [
        {
          id,
          type: "rectangle",
          x: 30,
          y: 30,
          width: 100,
          height: 60,
          strokeColor: "#1e1e1e",
          backgroundColor: "#a5d8ff",
          seed: 1,
          version: 1,
        },
      ],
    });
  }, id);
  await p.waitForFunction(
    (id) => window.scratchy.ctrl.api.getSceneElements().some((e) => e.id === id),
    id,
  );
};
let failed = 0,
  projectId,
  canvasId,
  archiveBytes;
async function check(name, fn) {
  try {
    const result = await fn();
    console.log(`PASS  ${name}${result ? `: ${result}` : ""}`);
  } catch (error) {
    failed++;
    console.log(`FAIL  ${name}: ${error.stack}`);
  }
}

try {
  console.log(`projects engine: ${engine} ${browser.version()}`);
  await page.goto(url);
  await ready();
  await check("Markdown creates a nested project with stable framed canvases", async () => {
    const result = await page.evaluate(async () => {
      const w = window.scratchy.workspace,
        r = await w.projects.manager.create(
          "Research",
          "---\ntitle: Research\n---\n# Overview\n\nProject body.\n\n## Methods\n\nRead [the docs](https://example.com).\n\n- First\n- Second\n\n# Findings\n\nLast slide.",
        );
      await w.switchTo(r.project.nodes[0].boardId);
      return { id: r.project.id, boardId: r.project.nodes[0].boardId, nodes: r.project.nodes };
    });
    projectId = result.id;
    canvasId = result.boardId;
    expect(result.nodes.length === 3, "missing canvases");
    expect(result.nodes[1].parentId === result.nodes[0].id, "wrong hierarchy");
    const elements = await scene();
    expect(
      elements.some((e) => e.type === "frame" && e.width === 1280 && e.height === 720),
      "slide frame missing",
    );
    expect(
      (await page.locator(`[data-node-id="${result.nodes[0].id}"]`).count()) === 1,
      "explorer missing node",
    );
  });
  await check(
    "source applies retain drawing IDs, positions, styles and mounted sessions",
    async () => {
      await page.evaluate(async (id) => {
        const w = window.scratchy.workspace;
        await w.active.ctrl.add({
          elements: [
            {
              id: "retained-shape",
              type: "rectangle",
              x: 800,
              y: 420,
              width: 130,
              height: 90,
              backgroundColor: "#a5d8ff",
            },
          ],
        });
        await w.flush();
        const elements = w.active.ctrl.api
          .getSceneElements()
          .map((e) =>
            e.type === "text" && e.originalText === "Project body."
              ? {
                  ...e,
                  x: 140,
                  y: 260,
                  strokeColor: "#e03131",
                  version: e.version + 1,
                  versionNonce: e.versionNonce + 1,
                }
              : e,
          );
        w.active.ctrl.api.updateScene({ elements, captureUpdate: "IMMEDIATELY" });
        await new Promise(requestAnimationFrame);
        await w.flush();
        window.retainedController = w.active.ctrl;
        const p = await w.store.project(id);
        await w.projects.manager.apply(
          id,
          p.source.replace("Project body.", "Updated project body."),
        );
      }, projectId);
      const es = await scene(),
        text = es.find((e) => e.originalText === "Updated project body.");
      expect(
        text?.x === 140 && text?.y === 260 && text?.strokeColor === "#e03131",
        JSON.stringify(text),
      );
      expect(
        es.some((e) => e.id === "retained-shape"),
        "drawing removed",
      );
      expect(
        await page.evaluate(() => window.retainedController === window.scratchy.ctrl),
        "editor remounted",
      );
    },
  );
  await check(
    "canvas text and shape labels enter Markdown once; deletion and Undo stay linked",
    async () => {
      await page.evaluate(async () => {
        const w = window.scratchy.workspace;
        await w.active.ctrl.add({
          elements: [
            {
              id: "new-annotation",
              type: "text",
              x: 600,
              y: 500,
              width: 220,
              height: 36,
              text: "Canvas annotation",
              originalText: "Canvas annotation",
              fontSize: 28,
              fontFamily: 5,
            },
          ],
        });
        await w.flush();
      });
      let source = await page.evaluate(
        async (id) => (await window.scratchy.workspace.store.project(id)).source,
        projectId,
      );
      expect(source.split("Canvas annotation").length === 2, "annotation not linked exactly once");
      await page.evaluate(async () => {
        const w = window.scratchy.workspace;
        const elements = w.active.ctrl.api
          .getSceneElements()
          .map((e) =>
            e.id === "new-annotation"
              ? { ...e, isDeleted: true, version: e.version + 1, versionNonce: e.versionNonce + 1 }
              : e,
          );
        w.active.ctrl.api.updateScene({ elements, captureUpdate: "IMMEDIATELY" });
        await new Promise(requestAnimationFrame);
        await w.flush();
      });
      source = await page.evaluate(
        async (id) => (await window.scratchy.workspace.store.project(id)).source,
        projectId,
      );
      expect(!source.includes("Canvas annotation"), "deleted text remained in source");
      await page
        .locator(".ws-editor:not([hidden]) .excalidraw")
        .click({ position: { x: 500, y: 430 } });
      await page.keyboard.press(`${process.platform === "darwin" ? "Meta" : "Control"}+z`);
      await page.waitForFunction(() =>
        window.scratchy.ctrl.api.getSceneElements().some((e) => e.id === "new-annotation"),
      );
      await page.evaluate(() => window.scratchy.workspace.flush());
      source = await page.evaluate(
        async (id) => (await window.scratchy.workspace.store.project(id)).source,
        projectId,
      );
      expect(source.split("Canvas annotation").length === 2, "Undo duplicated or lost source text");
    },
  );
  await check(
    "native text editing saves the drawing and links its text when editing finishes",
    async () => {
      await page.locator(".ws-editor:not([hidden]) .excalidraw").focus();
      await page.keyboard.press("t");
      const box = await page.locator(".ws-editor:not([hidden])").boundingBox();
      await page.mouse.click(box.x + box.width * 0.65, box.y + box.height * 0.65);
      const input = page.locator("textarea.excalidraw-wysiwyg");
      await input.waitFor();
      await input.fill("Native text draft");
      await page.waitForTimeout(450);
      expect(
        !(
          await page.evaluate(
            async (id) => (await window.scratchy.workspace.store.project(id)).source,
            projectId,
          )
        ).includes("Native text draft"),
        "unfinished editor text changed master source",
      );
      await page.keyboard.press("Escape");
      await page.waitForFunction(
        async (id) =>
          (await window.scratchy.workspace.store.project(id)).source.includes("Native text draft"),
        projectId,
      );
    },
  );
  await check("title deletion hides its title and keeps the canvas", async () => {
    await page.evaluate(async () => {
      const w = window.scratchy.workspace;
      w.active.ctrl.api.updateScene({
        elements: w.active.ctrl.api
          .getSceneElements()
          .map((e) =>
            e.customData?.scratchy?.markdown?.kind === "title"
              ? { ...e, isDeleted: true, version: e.version + 1, versionNonce: e.versionNonce + 1 }
              : e,
          ),
        captureUpdate: "IMMEDIATELY",
      });
      await new Promise(requestAnimationFrame);
      await w.flush();
    });
    const p = await page.evaluate(
      async (id) => window.scratchy.workspace.store.project(id),
      projectId,
    );
    expect(p.nodes.length === 3 && p.nodes[0].hidden, "title deletion trashed canvas");
  });
  await check(
    "master drafts survive reload and invalid YAML leaves canvases unchanged",
    async () => {
      await page.evaluate((id) => window.scratchy.workspace.projects.showMaster(id), projectId);
      await page.locator("#master-text").fill("---\ntitle: [\n---\n# Broken");
      await page.evaluate(() => window.scratchy.workspace.projects.saveDraft());
      expect(await page.locator("#master-apply").isDisabled(), "invalid draft can be applied");
      const before = await page.evaluate(
        async (id) => (await window.scratchy.workspace.store.project(id)).revision,
        projectId,
      );
      await page.reload();
      await ready();
      await page.locator("#master-text").waitFor();
      expect(
        (await page.locator("#master-text").inputValue()).includes("# Broken"),
        "draft lost on reload",
      );
      expect(
        (await page.evaluate(
          async (id) => (await window.scratchy.workspace.store.project(id)).revision,
          projectId,
        )) === before,
        "invalid source changed project",
      );
      await page.locator("#master-discard").click();
      await page.waitForFunction(() => !window.scratchy.workspace.projects.dirty);
    },
  );
  await check("draft/canvas conflicts expose both sources and retain the original", async () => {
    await page
      .locator("#master-text")
      .fill(
        (await page.locator("#master-text").inputValue()).replace(
          "Updated project body.",
          "Draft body.",
        ),
      );
    await page.evaluate(() => window.scratchy.workspace.projects.saveDraft());
    await page.evaluate(async (id) => {
      const w = window.scratchy.workspace,
        p = await w.store.project(id);
      await w.projects.manager.apply(
        id,
        p.source.replace("Updated project body.", "Concurrent source."),
        { force: true },
      );
      await w.store.draft(id, document.querySelector("#master-text").value, p.revision);
      await w.refresh();
    }, projectId);
    expect(await page.locator("#master-conflict").isVisible(), "conflict comparison missing");
    expect(
      (await page.locator("#master-current").textContent()).includes("Concurrent source."),
      "current source unavailable",
    );
    await page.locator("#master-force").click();
    await page.waitForFunction(() => !window.scratchy.workspace.projects.dirty);
    expect(
      await page.evaluate(
        async (id) =>
          (await window.scratchy.workspace.store.project(id)).source.includes("Draft body."),
        projectId,
      ),
      "chosen draft lost",
    );
    expect(
      await page.evaluate(
        async (id) =>
          (await window.scratchy.workspace.store.projectHistory(id)).some((v) =>
            v.document?.source.includes("Concurrent source."),
          ),
        projectId,
      ),
      "concurrent source not retained in history",
    );
  });
  await check(
    "source renames, nesting, duplicate sections and includes update the explorer",
    async () => {
      await page.evaluate(async (id) => {
        const w = window.scratchy.workspace,
          p = await w.store.project(id);
        await w.projects.manager.apply(id, p.source.replace("# Findings", "## Findings renamed"));
        await w.projects.manager.duplicateCanvas(id, p.nodes[0].id);
      }, projectId);
      const p = await page.evaluate(
        async (id) => window.scratchy.workspace.store.project(id),
        projectId,
      );
      expect(p.nodes.length === 6, `node count ${p.nodes.length}`);
      expect(
        p.nodes[2].parentId === p.nodes[0].id && p.nodes[2].title === "Findings renamed",
        "outline/source mismatch",
      );
      await page.evaluate(async (id) => {
        const w = window.scratchy.workspace,
          p = await w.store.project(id);
        const source = p.source.replace(
          `scratchy:node ${p.nodes[3].id}`,
          `scratchy:node ${p.nodes[3].id} excluded`,
        );
        await w.projects.manager.apply(id, source);
        await w.projects.showMaster(id);
      }, projectId);
      expect(
        await page
          .locator("#master-text")
          .inputValue()
          .then((s) => s.includes("excluded")),
        "slide exclusion lost",
      );
    },
  );
  await check("relative images commit with source and are present in portable ZIP", async () => {
    await page.evaluate(async () => {
      const w = window.scratchy.workspace;
      const bytes = Uint8Array.from(
        atob(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jX1sAAAAASUVORK5CYII=",
        ),
        (c) => c.charCodeAt(0),
      );
      await w.projects.addImage(new File([bytes], "pixel.png", { type: "image/png" }));
    });
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      page.evaluate((id) => window.scratchy.workspace.projects.export(id, "zip"), projectId),
    ]);
    archiveBytes = await readFile(await download.path());
    const files = unzipSync(archiveBytes);
    expect(Boolean(files["project.md"]), "master missing");
    expect(
      Object.keys(files).some((p) => /assets\/.*pixel.png/.test(p)),
      "relative resource missing",
    );
    const manifest = JSON.parse(strFromU8(files["manifest.json"]));
    expect(
      manifest.data.projectVersions.length === 0 && manifest.data.revisions.length === 0,
      "portable archive includes recovery history",
    );
  });
  await check(
    "project ZIP merges without sharing canvases and repeated import skips duplicates",
    async () => {
      const result = await page.evaluate(
        async (bytes) => {
          const w = window.scratchy.workspace;
          const original = [...w.projects.items].filter((p) => p.managed).length;
          const a = await w.restoreBackup(new Blob([new Uint8Array(bytes)]));
          const b = await w.restoreBackup(new Blob([new Uint8Array(bytes)]));
          return { original, count: w.projects.items.filter((p) => p.managed).length, a, b };
        },
        [...archiveBytes],
      );
      expect(result.b.added === 0 && result.count === result.original, JSON.stringify(result));
      await page.evaluate(async (id) => {
        const w = window.scratchy.workspace,
          p = await w.store.project(id);
        await w.projects.manager.apply(id, p.source.replace("Draft body.", "Newer body."));
      }, projectId);
      const merged = await page.evaluate(
        async (bytes) => {
          const w = window.scratchy.workspace,
            a = await w.restoreBackup(new Blob([new Uint8Array(bytes)])),
            b = await w.restoreBackup(new Blob([new Uint8Array(bytes)]));
          const dump = await w.store.dump(),
            projects = dump.projects.filter((p) => p.managed);
          return {
            a,
            b,
            count: projects.length,
            unique: new Set(projects.flatMap((p) => p.nodes.map((n) => n.boardId))).size,
            nodes: projects.flatMap((p) => p.nodes).length,
          };
        },
        [...archiveBytes],
      );
      expect(
        merged.a.added === 6 && merged.b.added === 0 && merged.unique === merged.nodes,
        JSON.stringify(merged),
      );
    },
  );
  await check(
    "browser slideshow uses depth-first included slides and keyboard navigation",
    async () => {
      await page.evaluate(
        (id) =>
          window.scratchy.workspace.switchTo(
            window.scratchy.workspace.projects.items.find((p) => p.id === id).nodes[0].boardId,
          ),
        projectId,
      );
      const action = page.evaluate(
        (id) => window.scratchy.workspace.projects.export(id, "present"),
        projectId,
      );
      await Promise.race([
        page.locator(".ws-presenter").waitFor(),
        page
          .getByRole("button", { name: "Continue with slide frames" })
          .waitFor()
          .then(() => page.getByRole("button", { name: "Continue with slide frames" }).click()),
      ]);
      await action;
      await page.locator(".ws-presenter img").waitFor();
      expect(
        (await page.locator(".ws-presenter nav span").textContent()).startsWith("1 / 5"),
        "included order/count wrong",
      );
      await page.keyboard.press("ArrowRight");
      expect(
        (await page.locator(".ws-presenter nav span").textContent()).includes("Methods"),
        "keyboard did not advance",
      );
      await page.waitForFunction(
        () =>
          document.querySelector(".ws-presenter img")?.alt === "Methods" &&
          document.querySelector(".ws-presenter img")?.style.visibility === "visible",
      );
      await page.screenshot({ path: `/private/tmp/scratchy-slideshow-${engine}.png` });
      await page.keyboard.press("Escape");
    },
  );
  await check("PowerPoint has editable text; PDF has fixed 16:9 pages", async () => {
    const exportFile = async (kind) => {
      const wait = page.waitForEvent("download");
      const action = page.evaluate(
        ({ id, kind }) => window.scratchy.workspace.projects.export(id, kind),
        { id: projectId, kind },
      );
      const overflow = page.getByRole("button", { name: "Continue with slide frames" });
      await Promise.race([
        overflow
          .waitFor({ timeout: 10000 })
          .then(() => overflow.click())
          .catch(() => {}),
        action,
      ]);
      const d = await wait;
      await action;
      return readFile(await d.path());
    };
    const pptx = unzipSync(await exportFile("pptx")),
      slides = Object.keys(pptx).filter((p) => /^ppt\/slides\/slide\d+\.xml$/.test(p));
    expect(slides.length === 5, `slides ${slides.length}`);
    expect(
      slides.some((p) => strFromU8(pptx[p]).includes("<a:t>Newer body.</a:t>")),
      "editable text not present in slide XML",
    );
    const pdf = await PDFDocument.load(await exportFile("pdf"));
    expect(pdf.getPageCount() === 5, `PDF pages ${pdf.getPageCount()}`);
    expect(
      pdf.getPage(0).getWidth() === 960 && pdf.getPage(0).getHeight() === 540,
      "wrong PDF slide size",
    );
  });
  await check(
    "stale canvas edits recover an entire project without overwriting the current source",
    async () => {
      const other = await context.newPage();
      await other.goto(url);
      await ready(other);
      await other.evaluate((id) => window.scratchy.workspace.switchTo(id), canvasId);
      await page.evaluate(async (id) => {
        const w = window.scratchy.workspace,
          p = await w.store.project(id);
        await w.projects.manager.apply(
          id,
          p.source.replace("Newer body.", "Current window source."),
        );
      }, projectId);
      await add("stale-shape", other);
      await other.evaluate(() => window.scratchy.workspace.flush());
      const result = await other.evaluate(async () => {
        const w = window.scratchy.workspace,
          p = await w.store.project(w.active.board.projectId);
        return { title: p.title, count: p.nodes.length };
      });
      expect(result.title.includes("recovered") && result.count === 6, JSON.stringify(result));
      expect(
        await page.evaluate(
          async (id) =>
            (await window.scratchy.workspace.store.project(id)).source.includes(
              "Current window source.",
            ),
          projectId,
        ),
        "current project overwritten",
      );
      await other.close();
    },
  );
  await check("project history restores outline and source; trash restores as a unit", async () => {
    const result = await page.evaluate(async (id) => {
      const w = window.scratchy.workspace,
        history = await w.store.projectHistory(id),
        version = history.find((v) => v.project.nodes.length === 3);
      await w.projects.manager.restoreVersion(id, version.id);
      const p = await w.store.project(id);
      await w.projects.manager.trashProject(id);
      const trashed = (await w.store.list()).boards
        .filter((b) => p.nodes.some((n) => n.boardId === b.id))
        .every((b) => b.deletedAt);
      await w.projects.manager.trashProject(id, true);
      return {
        count: p.nodes.length,
        trashed,
        restored: (await w.store.project(id)).deletedAt === null,
      };
    }, projectId);
    expect(result.count === 3 && result.trashed && result.restored, JSON.stringify(result));
  });
  await check("sidebar preferences and master tabs restore lazily; mobile fits", async () => {
    await page.evaluate((id) => window.scratchy.workspace.projects.showMaster(id), projectId);
    await page.evaluate(async () => {
      const w = window.scratchy.workspace;
      w.projects.width(340);
      await w.persistLayout();
    });
    await page.reload();
    await ready();
    await page.locator("#master-text").waitFor();
    expect(
      (await page.evaluate(() => window.scratchy.workspace.projects.sidebarWidth)) === 340,
      "width lost",
    );
    expect(
      (await page.evaluate(() => window.scratchy.workspace.sessions.size)) === 1,
      "opened all canvas editors",
    );
    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByRole("button", { name: "Toggle project explorer" }).click();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      "mobile overflow",
    );
    await page.screenshot({ path: `/private/tmp/scratchy-projects-${engine}-mobile.png` });
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.getByRole("button", { name: "Toggle project explorer" }).click();
    await page.screenshot({ path: `/private/tmp/scratchy-projects-${engine}.png` });
  });
  await check(
    "ordinary drawings link to Markdown without moving or restyling their contents",
    async () => {
      await page.evaluate(async () => {
        const w = window.scratchy.workspace;
        await w.switchTo(
          [...w.boards.values()].find((b) => b.projectId === "my-sketches" && !b.deletedAt).id,
        );
        await w.active.ctrl.add({
          elements: [
            {
              id: "legacy-label",
              type: "text",
              x: 310,
              y: 180,
              width: 178,
              height: 38,
              text: "Original label",
              originalText: "Original label",
              fontSize: 30,
              fontFamily: 2,
              strokeColor: "#e03131",
            },
          ],
        });
        await w.flush();
        window.beforeLegacy = w.active.ctrl.api.getSceneElements();
        await w.projects.manager.adoptLegacy("my-sketches");
      });
      const kept = await page.evaluate(() => {
        const now = window.scratchy.ctrl.api.getSceneElements();
        return window.beforeLegacy.every((old) => {
          const e = now.find((e) => e.id === old.id);
          return (
            e &&
            ["x", "y", "width", "height", "fontSize", "fontFamily", "strokeColor", "text"].every(
              (k) => e[k] === old[k],
            )
          );
        });
      });
      expect(kept, "legacy drawing appearance changed");
    },
  );
  await check(
    "missing images block exports, and viewport-only saves do not create project versions",
    async () => {
      const result = await page.evaluate(async (id) => {
        const w = window.scratchy.workspace,
          p = await w.store.project(id);
        await w.projects.manager.apply(id, p.source + "\n![Missing](assets/missing.png)\n");
        await w.switchTo(p.nodes.at(-1).boardId);
        let message;
        try {
          await w.projects.export(id, "pdf");
        } catch (e) {
          message = e.message;
        }
        const before = (await w.store.projectHistory(id)).length;
        w.active.ctrl.api.scrollToContent([], { animate: false });
        w.active.ctrl.api.updateScene({ appState: { zoom: { value: 1.23 } } });
        await new Promise(requestAnimationFrame);
        await w.flush();
        return { message, before, after: (await w.store.projectHistory(id)).length };
      }, projectId);
      expect(
        result.message?.includes("missing image") && result.before === result.after,
        JSON.stringify(result),
      );
    },
  );
  await check(
    "full recovery ZIP restores projects, drafts, history and Markdown tabs in a fresh browser",
    async () => {
      const [download] = await Promise.all([
        page.waitForEvent("download"),
        page.evaluate(() => window.scratchy.workspace.backup()),
      ]);
      const bytes = await readFile(await download.path());
      const c = await browser.newContext(),
        fresh = await c.newPage();
      await fresh.goto(url);
      await ready(fresh);
      const result = await fresh.evaluate(
        async (bytes) => {
          const w = window.scratchy.workspace,
            r = await w.restoreBackup(new Blob([new Uint8Array(bytes)])),
            dump = await w.store.dump();
          const repeat = await w.restoreBackup(new Blob([new Uint8Array(bytes)]));
          return {
            fresh: r.fresh,
            projects: dump.projects.filter((p) => p.managed).length,
            versions: dump.projectVersions.length,
            repeat: repeat.added,
          };
        },
        [...bytes],
      );
      expect(
        result.fresh && result.projects >= 3 && result.versions > 0 && result.repeat === 0,
        JSON.stringify(result),
      );
      await c.close();
    },
  );
  await check("no browser page errors", () => expect(!errors.length, errors.join("\n")));
} finally {
  await browser.close();
  server.close();
}
console.log(failed ? `${failed} project checks failed` : "all project checks passed");
process.exitCode = failed ? 1 : 0;
