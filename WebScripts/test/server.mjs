// Tiny HTTP server for the detector tests: serves fixtures and fake media endpoints.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(here, 'fixtures');

const M3U8 = '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nseg0.ts\n#EXT-X-ENDLIST\n';
const MPD = '<?xml version="1.0"?><MPD xmlns="urn:mpeg:dash:schema:mpd:2011"></MPD>';

export function startServer(otherOrigin = '') {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const send = (status, type, body) => {
      res.writeHead(status, { 'Content-Type': type, 'Access-Control-Allow-Origin': '*' });
      res.end(body);
    };
    if (url.pathname === '/media/master.m3u8' || url.pathname === '/api/stream') {
      return send(200, 'application/vnd.apple.mpegurl', M3U8);
    }
    if (url.pathname === '/media/x.mpd') return send(200, 'application/dash+xml', MPD);
    if (url.pathname.startsWith('/media/')) return send(200, 'video/mp4', Buffer.alloc(16));
    const file = path.join(fixtures, path.basename(url.pathname));
    if (url.pathname.endsWith('.html') && fs.existsSync(file)) {
      const html = fs.readFileSync(file, 'utf8').replaceAll('{{OTHER}}', otherOrigin);
      return send(200, 'text/html; charset=utf-8', html);
    }
    return send(404, 'text/plain', 'not found');
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      resolve({ server, origin: `http://127.0.0.1:${port}` });
    });
  });
}
