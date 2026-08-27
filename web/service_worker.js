const CACHE_NAME = 'pocket-party-v1.0.0';
const APP_SHELL = [
  './',
  './index.html',
  './flutter.js',
  './flutter_bootstrap.js',
  './main.dart.js',
  './manifest.json',
  './favicon.png',
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/FontManifest.json',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/shaders/ink_sparkle.frag',
  './assets/shaders/stretch_effect.frag',
  './assets/assets/branding/icon_master.png',
  './assets/assets/data/trivia.json',
  './assets/assets/data/truth_or_dare.json',
  './assets/assets/data/pictionary.json',
  './assets/assets/data/act_it_out.json',
  './assets/assets/data/countdown.json',
  './assets/assets/data/imposter_words.json',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
  './canvaskit/chromium/canvaskit.js',
  './canvaskit/chromium/canvaskit.wasm',
];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('./index.html')));
    return;
  }
  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request).then(response => {
      if (response.ok && new URL(event.request.url).origin === self.location.origin) {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
      }
      return response;
    })),
  );
});
