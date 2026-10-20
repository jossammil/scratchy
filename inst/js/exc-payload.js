// Helpers for Excalidraw's embedded-scene payloads (.excalidraw.svg/.png).
var ExcPayload = (function () {
  "use strict";
  var table = null;

  function makeTable() {
    var t = new Array(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
      t[n] = c >>> 0;
    }
    return t;
  }

  return {
    // PNG chunk CRC (over chunk type + data).
    crc32: function (bytes) {
      table = table || makeTable();
      var c = 0xffffffff;
      for (var i = 0; i < bytes.length; i++) c = table[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
      return (c ^ 0xffffffff) >>> 0;
    },
    // Parse the JSON envelope; return the byte string as numbers so R can
    // inflate it. Legacy payloads are plain scene JSON.
    decode: function (s) {
      var o = JSON.parse(s);
      if (!("encoded" in o)) {
        if (o.type === "excalidraw") return { plain: true, json: s };
        throw new Error("Unrecognised Excalidraw payload");
      }
      if (o.encoding !== "bstring") throw new Error("Unknown payload encoding " + o.encoding);
      var e = o.encoded, out = new Array(e.length);
      for (var i = 0; i < e.length; i++) out[i] = e.charCodeAt(i);
      return { plain: false, compressed: !!o.compressed, bytes: out };
    }
  };
})();
