const CACHE = 'maxikia-v3';

self.addEventListener('install', e => {
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// No cachear nada — siempre buscar en red
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  // Solo dejar pasar requests normales sin caché
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});
