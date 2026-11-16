const CACHE_NAME = "ramp-admin-shell-v12";
const SHELL_FILES = [
  "/static/form-ux.js?v=2",
  "/static/app.js?v=9",
  "/static/style.css?v=8",
  "/static/polish.css?v=11",
  "/static/favicon.svg",
  "/static/offline.html",
];
const MAX_PAGE_AGE = 8 * 60 * 60 * 1000;

async function savePage(cache, request, response) {
  const headers = new Headers(response.headers);
  headers.set("X-Ramp-Cached-At", String(Date.now()));
  await cache.put(
    request,
    new Response(response.clone().body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    }),
  );
}

async function removeExpiredPages(cache) {
  const keys = await cache.keys();
  await Promise.all(keys.map(async (request) => {
    const response = await cache.match(request);
    const savedAt = Number(response?.headers.get("X-Ramp-Cached-At"));
    if (savedAt && Date.now() - savedAt > MAX_PAGE_AGE) {
      await cache.delete(request);
    }
  }));
}

async function cachedPage(request, url) {
  const cache = await caches.open(CACHE_NAME);
  let page = await cache.match(request);
  let cacheKey = request;
  if (!page) {
    url.search = "";
    cacheKey = url.href;
    page = await cache.match(cacheKey);
  }
  const savedAt = Number(page?.headers.get("X-Ramp-Cached-At"));
  if (page && savedAt && Date.now() - savedAt <= MAX_PAGE_AGE) {
    const body = await page.text();
    const headers = new Headers(page.headers);
    headers.delete("Content-Length");
    headers.delete("Content-Encoding");
    headers.set("Cache-Control", "no-store");
    return new Response(
      body.replace("<head>", '<head><meta name="ramp-cache-fallback" content="true">'),
      { status: page.status, statusText: page.statusText, headers },
    );
  }
  if (page) await cache.delete(cacheKey);
  return (await cache.match("/static/offline.html")) ||
    new Response("Offline. Reconnect to load this page.", {
      status: 503,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
}

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)),
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith("ramp-admin-shell-") && key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ),
    ),
  );
  self.clients.claim();
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "CLEAR_RAMP_CACHE") {
    event.waitUntil(caches.delete(CACHE_NAME));
  }
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;
  if (request.mode === "navigate") {
    event.waitUntil(caches.open(CACHE_NAME).then(removeExpiredPages));
  }

  if (url.pathname.startsWith("/static/")) {
    event.respondWith(
      fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
        }
        return response;
      }).catch(async () => (await caches.match(request)) ||
        new Response("Offline asset unavailable.", {
          status: 503,
          headers: { "Content-Type": "text/plain; charset=utf-8" },
        })),
    );
    return;
  }

  if (request.mode !== "navigate" || url.pathname === "/login") return;
  event.respondWith(
    fetch(request).then(async (response) => {
      const finalPath = new URL(response.url).pathname;
      if (response.ok && finalPath !== "/login" && !url.pathname.endsWith(".csv")) {
        await savePage(await caches.open(CACHE_NAME), request, response);
        return response;
      }
      if (response.status >= 502 && response.status <= 504) return cachedPage(request, url);
      return response;
    }).catch(() => cachedPage(request, url)),
  );
});
