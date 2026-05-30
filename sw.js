const CACHE = 'maxikia-v5';
const PRECACHE = ['/', '/index.html', '/manifest.json', '/icon-192.png', '/icon-512.png'];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(PRECACHE).catch(() => {}))
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  // Network first, fallback to cache for navigation
  if (e.request.mode === 'navigate') {
    e.respondWith(
      fetch(e.request)
        .then(r => { const c = r.clone(); caches.open(CACHE).then(cache => cache.put(e.request, c)); return r; })
        .catch(() => caches.match('/index.html') || caches.match(e.request))
    );
    return;
  }
  // Cache first for static assets
  if (e.request.url.match(/\.(png|jpg|ico|svg|woff2|css)$/)) {
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request).then(r => {
        const c = r.clone(); caches.open(CACHE).then(cache => cache.put(e.request, c)); return r;
      }))
    );
    return;
  }
  // Network first for everything else
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});

// ── PUSH NOTIFICATIONS ──
self.addEventListener('push', e => {
  const data = e.data?.json() || {};
  const titulo = data.titulo || 'Maxi⋊ia Express';
  const cuerpo = data.cuerpo || 'Actualización de tu pedido';
  e.waitUntil(
    self.registration.showNotification(titulo, {
      body: cuerpo,
      icon: data.icono || '/icon-192.png',
      badge: '/icon-192.png',
      vibrate: [200, 100, 200],
      data: { url: data.url || '/' },
      actions: [{ action: 'ver', title: 'Ver pedido' }]
    })
  );
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = e.notification.data?.url || '/';
  e.waitUntil(
    clients.matchAll({ type: 'window' }).then(ws => {
      const w = ws.find(w => w.url === url);
      if (w) { w.focus(); } else { clients.openWindow(url); }
    })
  );
});
