// htmlwidgets binding. The editor bundle is an ES module that loads after
// this script, so rendering waits for it.
(function () {
  if (!window.excalidrawerReady) {
    window.excalidrawerReady = new Promise(function (resolve) {
      if (window.excalidrawerLib) resolve(window.excalidrawerLib);
      else window.__excalidrawerResolve = resolve;
    });
  }
})();

HTMLWidgets.widget({
  name: "excalidraw",
  type: "output",
  factory: function (el, width, height) {
    return {
      renderValue: function (x) {
        window.excalidrawerReady.then(function (lib) {
          lib.render(el, x);
        });
      },
      resize: function (width, height) {}
    };
  }
});
