const CACHE = 'maxikia-v4';

self.addEventListener('install', e => { self.skipWaiting(); });

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});

// ── NOTIFICACIONES PUSH ──
self.addEventListener('push', e => {
  const data = e.data?.json() || {};
  const titulo = data.titulo || 'Maxi⋊ia Express';
  const cuerpo = data.cuerpo || 'Actualización de tu pedido';
  const icono = data.icono || '/icon-192.png';
  const url = data.url || '/';

  e.waitUntil(
    self.registration.showNotification(titulo, {
      body: cuerpo,
      icon: icono,
      badge: '/icon-192.png',
      vibrate: [200, 100, 200],
      data: { url },
      actions: [
        { action: 'ver', title: 'Ver pedido' }
      ]
    })
  );
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = e.notification.data?.url || '/';
  e.waitUntil(
    clients.matchAll({ type: 'window' }).then(ws => {
      if (ws.length > 0) { ws[0].focus(); ws[0].navigate(url); }
      else clients.openWindow(url);
    })
  );
});
