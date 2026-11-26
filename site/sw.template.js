// excalidrawer's service worker, written by srcjs/tools/build-site.mjs.
// The page and the editor's core are cached at install; everything else
// (Mermaid, languages, fonts, stickers) is fetched into the cache in the
// background once the worker is active, and served from it after that.
const VERSION = "{{VERSION}}";
const CORE = {{CORE}};
const REST = {{REST}};
const CACHE = `excalidrawer-${VERSION}-{{BUILD}}`;

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) if (key.startsWith("excalidrawer-") && key !== CACHE) await caches.delete(key);
    await self.clients.claim();
    const cache = await caches.open(CACHE);
    // Fill in the rest for offline use, a few at a time; failures just wait for the next visit.
    for (let i = 0; i < REST.length; i += 6) {
      await Promise.all(REST.slice(i, i + 6).map(async (url) => {
        if (await cache.match(url)) return;
        try { const res = await fetch(url); if (res.ok) await cache.put(url, res); } catch {}
      }));
    }
  })());
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET" || new URL(req.url).origin !== location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(req, { ignoreSearch: req.mode === "navigate" || /\/app\.js$/.test(new URL(req.url).pathname) });
    if (hit) return hit;
    try {
      const res = await fetch(req);
      if (res.ok && res.type === "basic") cache.put(req, res.clone());
      return res;
    } catch (e) {
      if (req.mode === "navigate") { const page = await cache.match("./"); if (page) return page; }
      throw e;
    }
  })());
});
