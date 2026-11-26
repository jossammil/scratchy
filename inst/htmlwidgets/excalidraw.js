// htmlwidgets binding. The editor bundle is an ES module that loads after
// this script, so rendering waits for it.
(function () {
  if (!window.scratchyReady) {
    window.scratchyReady = new Promise(function (resolve) {
      if (window.scratchyLib) resolve(window.scratchyLib);
      else window.__scratchyResolve = resolve;
    });
  }
})();

HTMLWidgets.widget({
  name: "excalidraw",
  type: "output",
  factory: function (el, width, height) {
    return {
      renderValue: function (x) {
        window.scratchyReady.then(function (lib) {
          lib.render(el, x);
        });
      },
      resize: function (width, height) {}
    };
  }
});
