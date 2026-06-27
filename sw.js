const CACHE_NAME = 'lucrex-v4';
const urlsToCache = [
  '/Lucrex/',
  '/Lucrex/login.html',
  '/Lucrex/otp.html',
  '/Lucrex/onboarding.html',
  '/Lucrex/feed.html',
  '/Lucrex/post.html',
  '/Lucrex/bid.html',
  '/Lucrex/profile.html',
  '/Lucrex/manifest.json'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(urlsToCache))
  );
});

self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => response || fetch(event.request))
  );
});