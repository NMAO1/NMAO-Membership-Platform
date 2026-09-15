/* NMAO PWA service worker — minimal, network-first with cache fallback.
   Lives at the site ROOT so its scope ("/") can control /portal.html (Member)
   and /dashboard.html (Staff). A fetch handler is required for PWA installability
   (Play/TWA packaging via PWABuilder). Bump CACHE to force clients to update. */
const CACHE = 'nmao-pwa-v1';

self.addEventListener('install', (e) => { self.skipWaiting(); });

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    // Drop old caches on version bump.
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;                 // never cache POST/auth calls
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;  // let cross-origin (Supabase/Stripe) pass through untouched
  e.respondWith((async () => {
    try {
      const res = await fetch(req);
      // Cache same-origin static assets + the app shell for offline fallback.
      if (res && res.status === 200) {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
      }
      return res;
    } catch (_err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      // Last resort: the shell page so a launch offline still renders.
      return (await caches.match('/portal.html')) || (await caches.match('/dashboard.html')) || Response.error();
    }
  })());
});
