/* Pulso: service worker. Cambia VERSION cada vez que publiques cambios. */
const VERSION = 'pulso-v6';
const SHELL = ['./', './index.html', './config.js', './manifest.webmanifest', './icons/icon.svg', './icons/icon-192.png', './icons/icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
const networkFirst = (req, key) => fetch(req).then(r => {
  if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(key || req, copy)); }
  return r;
}).catch(() => caches.match(key || req));

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Página y configuración: red primero (para recibir cambios), caché sin conexión
  if (req.mode === 'navigate') { e.respondWith(networkFirst(req, './index.html')); return; }
  if (url.origin === location.origin && url.pathname.endsWith('/config.js')) { e.respondWith(networkFirst(req)); return; }
  // Archivos propios, fuentes y la librería de Supabase: caché primero
  if (url.origin === location.origin || url.host.includes('fonts.g') || url.host === 'cdn.jsdelivr.net') {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
      if (r.ok || r.type === 'opaque') { const copy = r.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
      return r;
    })));
  }
  // Todo lo de Supabase (datos, sesión, tiempo real) va siempre directo a la red.
});
