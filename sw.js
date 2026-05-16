const CACHE_NAME = 'lucrex-v3';
const urlsToCache = [
  '/',
  '/login.html',
  '/otp.html',
  '/onboarding.html',
  '/feed.html',
  '/post.html',
  '/bid.html',
  '/profile.html',
  '/manifest.json'
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