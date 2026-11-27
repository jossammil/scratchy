// The shared editor remains independent of the standalone workspace.
import Scratchy from "./editor/excalidraw-widget.js";
import { mountWorkspace } from "./workspace/index.js";

const boot = document.getElementById("boot");
try {
  const workspace = await mountWorkspace(document.getElementById("app"), { Scratchy });
  window.scratchy = {
    workspace,
    get ctrl() { return workspace.active?.ctrl; },
    get doc() { return workspace.active; },
    version: Scratchy.version,
  };
  boot.hidden = true;
} catch (error) {
  boot.textContent = `The workspace could not start: ${error.message}. Your existing browser data has not been deleted.`;
  boot.className = "error";
}
if ("serviceWorker" in navigator && (location.protocol === "https:" || ["localhost", "127.0.0.1"].includes(location.hostname))) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}
