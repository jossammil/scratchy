// The read-only browser slideshow.
import { renderSlide } from "./export.js";
export async function present(workspace, deck) {
  const dialog = document.createElement("dialog");
  dialog.className = "ws-presenter";
  dialog.setAttribute("aria-label", `${deck.title} slideshow`);
  const image = document.createElement("img");
  image.alt = deck.slides[0].node.title;
  const controls = document.createElement("nav"),
    status = document.createElement("span");
  status.setAttribute("aria-live", "polite");
  const button = (label, fn) => {
    const b = document.createElement("button");
    b.textContent = label;
    b.onclick = fn;
    controls.append(b);
    return b;
  };
  let index = 0,
    request = 0,
    url = null;
  const rendered = new Map();
  async function show(i) {
    index = Math.max(0, Math.min(deck.slides.length - 1, i));
    const ticket = ++request;
    const slide = deck.slides[index],
      label = `${index + 1} / ${deck.slides.length} · ${slide.node.title}`;
    status.textContent = `Rendering ${label}`;
    image.style.visibility = "hidden";
    previous.disabled = index === 0;
    next.disabled = index === deck.slides.length - 1;
    if (!rendered.has(index)) rendered.set(index, renderSlide(workspace.S, slide));
    const blob = await rendered.get(index);
    if (ticket !== request || !dialog.open) return;
    if (url) URL.revokeObjectURL(url);
    url = URL.createObjectURL(blob);
    image.src = url;
    image.alt = slide.node.title;
    await image.decode();
    if (ticket === request && dialog.open) {
      image.style.visibility = "visible";
      status.textContent = label;
    }
  }
  const previous = button("Previous slide", () => workspace.run(() => show(index - 1))),
    next = button("Next slide", () => workspace.run(() => show(index + 1)));
  controls.append(status);
  button("Fullscreen", () => workspace.run(() => dialog.requestFullscreen?.()));
  button("Exit slideshow", () => dialog.close());
  dialog.append(image, controls);
  workspace.root.append(dialog);
  dialog.onkeydown = (e) => {
    // Space advances unless it is pressing one of the slideshow's buttons.
    const space = e.key === " " && e.target.tagName !== "BUTTON";
    if (["ArrowRight", "PageDown"].includes(e.key) || space) {
      e.preventDefault();
      workspace.run(() => show(index + 1));
    }
    if (["ArrowLeft", "PageUp"].includes(e.key)) {
      e.preventDefault();
      workspace.run(() => show(index - 1));
    }
    if (e.key === "Home") workspace.run(() => show(0));
    if (e.key === "End") workspace.run(() => show(deck.slides.length - 1));
  };
  dialog.onclose = () => {
    request++;
    if (url) URL.revokeObjectURL(url);
    if (document.fullscreenElement === dialog) document.exitFullscreen?.();
    dialog.remove();
  };
  dialog.showModal();
  await show(0);
  next.focus();
  return dialog;
}
