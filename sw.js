// Cache only the public application shell. Never cache auth or business API data.
const VERSION='pos-shell-offline-v2';
const ASSETS=["/src/lan.mjs","/src/operations.mjs","/src/offline.mjs","/src/offline-store.mjs","/index.html","/manifest.webmanifest","/icons/pos-192.png","/icons/pos-512.png","/icons/pos-maskable.png","/src/app.mjs","/src/brand.mjs","/icons/sums-pos-approved.png","/src/login.mjs","/src/owner.mjs","/src/sales-insights.mjs","/src/refunds.mjs","/src/api.mjs","/src/config.mjs","/src/domain.mjs","/src/restaurant.mjs","/src/payments.mjs","/src/pos-experience.mjs","/src/realtime.mjs","/src/pwa.mjs","/src/i18n.mjs","/src/navigation.mjs","/src/style.css"];
self.addEventListener('install',e=>e.waitUntil(caches.open(VERSION).then(cache=>cache.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('pos-shell-')&&k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==self.location.origin)return;
 if(e.request.mode==='navigate'){e.respondWith(fetch(e.request).catch(()=>caches.match('/index.html')));return}
 if(!ASSETS.includes(u.pathname))return;
 e.respondWith(caches.open(VERSION).then(async cache=>{try{const response=await fetch(e.request,{cache:'no-cache'});if(response.ok)await cache.put(e.request,response.clone());return response}catch(error){const saved=await cache.match(e.request);if(saved)return saved;throw error}}));
});
