<?php
// feed-proxy.php — a tiny same-origin proxy for Contrapt stacks published
// to the web.
//
// WHY THIS EXISTS
// A web browser only lets a page read a response from a site that grants
// cross-origin permission (a CORS header). Most RSS feeds and APIs don't,
// so `url "…"` / `FeedItems(url "…")` in an EXPORTED Contrapt site fails
// even though it works in the Contrapt app (the app isn't a browser).
// The page CAN freely read from its own domain, though — so put this file
// beside your exported stack and fetch through it. Same origin, no CORS.
//
// USE (from a stack script):
//   put FeedItems(url "https://YOURSITE/feed-proxy.php?url=https://host/feed") into stories
//
// SECURITY: only the URLs you list below are fetchable, so this can't be
// turned into an open relay that strangers run traffic through. Add the
// feeds and APIs your stack needs.

$allowed = [
  'https://www.astronomy.com/tags/news/feed',
  // 'https://example.com/another-feed.xml',
];

$url = isset($_GET['url']) ? $_GET['url'] : '';
if (!in_array($url, $allowed, true)) {
  http_response_code(403);
  header('Content-Type: text/plain; charset=utf-8');
  echo "This proxy only serves its allow-listed URLs. Edit \$allowed in feed-proxy.php to add yours.";
  exit;
}

// Fetch server-side (no browser, no CORS) and hand the bytes back from our
// own origin. Pass the upstream content type through; default to XML.
$ctx = stream_context_create(['http' => ['timeout' => 15, 'header' => "User-Agent: Contrapt-Feed-Proxy\r\n"]]);
$body = @file_get_contents($url, false, $ctx);
if ($body === false) {
  http_response_code(502);
  header('Content-Type: text/plain; charset=utf-8');
  echo "The proxy couldn't reach $url.";
  exit;
}

$type = 'application/xml; charset=utf-8';
foreach ($http_response_header ?? [] as $h) {
  if (stripos($h, 'Content-Type:') === 0) { $type = trim(substr($h, 13)); break; }
}
header('Content-Type: ' . $type);
header('Access-Control-Allow-Origin: *'); // harmless; the page is already same-origin
echo $body;
