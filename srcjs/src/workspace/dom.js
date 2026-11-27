// Small DOM helpers shared by the workspace and project UIs.

/** Creates an element with optional text and class. */
export const el = (tag, text, cls) => {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (cls) node.className = cls;
  return node;
};

/**
 * Template tag for static markup laid out over several lines. Line breaks
 * between tags are dropped, so no stray text nodes appear; other line breaks
 * (inside a tag or in running text) become single spaces.
 */
export const html = (strings) =>
  strings
    .join("")
    .replace(/>\s*\n\s*/g, ">")
    .replace(/\s*\n\s*</g, "<")
    .replace(/\s*\n\s*/g, " ")
    .trim();
