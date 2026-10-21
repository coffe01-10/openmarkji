// Local-only preview of a completed Flutter web build. No dependencies required.
import http from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { resolve, extname, sep } from 'node:path';
const root = resolve('build/web');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf' };
const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://localhost');
  if (url.pathname === '/phone') {
    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.end('<!doctype html><meta charset="utf-8"><title>OpenMarkji · 手机预览</title><style>body{margin:0;background:#e6e9ef;display:grid;place-items:center;min-height:100vh}iframe{border:0;border-radius:28px;box-shadow:0 12px 60px #16243b25;background:#fff;width:390px;height:844px;max-width:100vw;max-height:100vh}</style><iframe src="/" title="OpenMarkji 手机界面"></iframe>');
    return;
  }
  const path = resolve(root, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
  if (!path.startsWith(root + sep) || !existsSync(path) || !statSync(path).isFile()) { response.writeHead(404); response.end('Not found'); return; }
  response.setHeader('Content-Type', types[extname(path)] ?? 'application/octet-stream');
  response.setHeader('Cache-Control', 'no-store');
  createReadStream(path).pipe(response);
});
server.listen(5127, '127.0.0.1', () => console.log('OpenMarkji preview: http://127.0.0.1:5127 (phone: /phone)'));
