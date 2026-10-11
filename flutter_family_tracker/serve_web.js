const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const PORT = 8080;
const HOST = '0.0.0.0';
const WEB_DIR = path.join(__dirname, 'build', 'web');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

const COMPRESSIBLE = new Set([
  '.html',
  '.js',
  '.json',
  '.css',
  '.svg',
  '.wasm',
]);

const server = http.createServer((req, res) => {
  // CORS & Security headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin-allow-popups');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  let reqPath = decodeURI(req.url.split('?')[0]);
  if (reqPath === '/' || reqPath === '') {
    reqPath = '/index.html';
  }

  let filePath = path.join(WEB_DIR, reqPath);

  // Security check: ensure path is within WEB_DIR
  if (!filePath.startsWith(WEB_DIR)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.stat(filePath, (err, stats) => {
    let isSpaFallback = false;
    if (err || !stats.isFile()) {
      // Fallback to index.html for SPA routing
      filePath = path.join(WEB_DIR, 'index.html');
      isSpaFallback = true;
    }

    fs.stat(filePath, (statErr, finalStats) => {
      if (statErr || !finalStats.isFile()) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Build web assets not found. Run "flutter build web" first.');
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      const contentType = MIME_TYPES[ext] || 'application/octet-stream';
      const etag = `W/"${finalStats.size}-${finalStats.mtimeMs}"`;

      // Cache validation
      if (req.headers['if-none-match'] === etag) {
        res.writeHead(304);
        res.end();
        return;
      }

      // Headers
      const headers = {
        'Content-Type': contentType,
        'ETag': etag,
        'Vary': 'Accept-Encoding',
      };

      if (ext === '.html' || isSpaFallback) {
        // HTML should revalidate quickly so new deployments are picked up immediately
        headers['Cache-Control'] = 'no-cache, must-revalidate';
      } else {
        // Static assets (.wasm, .js, .ttf, images) are aggressively cached for 7 days
        headers['Cache-Control'] = 'public, max-age=604800, stale-while-revalidate=86400';
      }

      // Check gzip/deflate compression
      const acceptEncoding = req.headers['accept-encoding'] || '';
      const canCompress = COMPRESSIBLE.has(ext);

      if (canCompress && /\bgzip\b/.test(acceptEncoding)) {
        headers['Content-Encoding'] = 'gzip';
        res.writeHead(200, headers);
        const rawStream = fs.createReadStream(filePath);
        const gzipStream = zlib.createGzip({ level: 6 });
        rawStream.pipe(gzipStream).pipe(res);
      } else if (canCompress && /\bdeflate\b/.test(acceptEncoding)) {
        headers['Content-Encoding'] = 'deflate';
        res.writeHead(200, headers);
        const rawStream = fs.createReadStream(filePath);
        const deflateStream = zlib.createDeflate();
        rawStream.pipe(deflateStream).pipe(res);
      } else {
        headers['Content-Length'] = finalStats.size;
        res.writeHead(200, headers);
        fs.createReadStream(filePath).pipe(res);
      }
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`⚡ FamilyTracker High-Performance Web Server running at:`);
  console.log(`- Local:   http://localhost:${PORT}`);
  console.log(`- Network: http://192.168.29.186:${PORT}`);
  console.log(`- Gzip Compression: ENABLED`);
  console.log(`- Asset HTTP Caching: ENABLED (max-age 7 days)`);
});
