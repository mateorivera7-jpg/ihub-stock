// Guarda la app para abrir rápido y sin señal; el stock siempre se pide primero a la red.
const CACHE = "ihub-v3";
const BASE = ["./", "index.html", "manifest.webmanifest", "icon-192.png", "logo-blanco.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(BASE))); self.skipWaiting(); });
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin) return;
  e.respondWith(
    fetch(e.request).then(r => {
      const copia = r.clone();
      caches.open(CACHE).then(c => c.put(url.pathname.endsWith("catalogo.json") ? "data/catalogo.json" : e.request, copia));
      return r;
    }).catch(() => caches.match(url.pathname.endsWith("catalogo.json") ? "data/catalogo.json" : e.request))
  );
});
