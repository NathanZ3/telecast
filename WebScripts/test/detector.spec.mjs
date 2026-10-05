import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer } from './server.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const detector = fs.readFileSync(path.join(here, '..', 'src', 'detector.js'), 'utf8');

// Stands in for WKWebView's message handler: every frame keeps its own message list.
const stub = `
  window.__msgs = [];
  window.webkit = { messageHandlers: { castDetector: {
    postMessage: function (m) { window.__msgs.push(JSON.parse(JSON.stringify(m))); }
  } } };
`;

let main;
let other;

test.beforeAll(async () => {
  other = await startServer();
  main = await startServer(other.origin);
});

test.afterAll(async () => {
  main?.server.close();
  other?.server.close();
});

test.beforeEach(async ({ page }) => {
  await page.addInitScript({ content: stub });
  await page.addInitScript({ content: detector });
});

const messages = (frame) => frame.evaluate(() => window.__msgs || []);
const candidates = async (frame) => (await messages(frame)).filter((m) => m.kind === 'candidate');
const urls = async (frame) => (await candidates(frame)).map((m) => m.url);

test('reports a <video src> present in the HTML', async ({ page }) => {
  await page.goto(`${main.origin}/video-src.html`);
  await expect.poll(() => urls(page.mainFrame())).toContain(`${main.origin}/media/a.mp4`);
  const message = (await candidates(page.mainFrame())).find((m) => m.url.endsWith('/media/a.mp4'));
  expect(['video-src', 'media-event']).toContain(message.via);
  expect(message.frameURL).toBe(`${main.origin}/video-src.html`);
});

test('reports a <source> added after load', async ({ page }) => {
  await page.goto(`${main.origin}/source-tag.html`);
  await expect.poll(() => urls(page.mainFrame())).toContain(`${main.origin}/b.mp4`);
  const message = (await candidates(page.mainFrame())).find((m) => m.url.endsWith('/b.mp4'));
  expect(message.via).toBe('source');
  expect(message.mime).toBe('video/mp4');
});

test('reports a manifest fetched inside a cross-origin iframe, from that frame', async ({ page }) => {
  await page.goto(`${main.origin}/iframe-parent.html`);
  await expect.poll(() => page.frames().length).toBeGreaterThan(1);
  const child = page.frames().find((frame) => frame.url().startsWith(other.origin));
  expect(child).toBeTruthy();
  await expect.poll(() => urls(child)).toContain(`${other.origin}/media/master.m3u8`);
  const message = (await candidates(child)).find((m) => m.url.endsWith('master.m3u8'));
  expect(message.frameURL).toBe(`${other.origin}/iframe-child.html`);
  expect(message.via).toBe('fetch');
  expect(await urls(page.mainFrame())).not.toContain(`${other.origin}/media/master.m3u8`);
});

test('reports an XHR answered with an HLS content type even without extension', async ({ page }) => {
  await page.goto(`${main.origin}/xhr-hls.html`);
  await expect
    .poll(async () => (await candidates(page.mainFrame())).filter((m) => m.via === 'xhr').map((m) => m.url))
    .toContain(`${main.origin}/api/stream?id=1`);
  const message = (await candidates(page.mainFrame())).find((m) => m.via === 'xhr');
  expect(message.mime).toContain('mpegurl');
});

test('reports DASH manifests and keeps fetch() working', async ({ page }) => {
  await page.goto(`${main.origin}/fetch-ct.html`);
  await expect.poll(() => urls(page.mainFrame())).toContain(`${main.origin}/media/x.mpd`);
  await expect.poll(() => page.evaluate(() => window.__text || '')).toContain('#EXTM3U');
  expect(await page.evaluate(() => window.fetch.toString())).toContain('native code');
});

test('ignores blob: sources', async ({ page }) => {
  await page.goto(`${main.origin}/mse-blob.html`);
  await expect.poll(() => page.evaluate(() => window.__done === true)).toBe(true);
  const all = await messages(page.mainFrame());
  expect(all.some((m) => typeof m.url === 'string' && m.url.startsWith('blob:'))).toBe(false);
});

test('says hello with the user agent once per frame', async ({ page }) => {
  await page.goto(`${main.origin}/video-src.html`);
  const hellos = (await messages(page.mainFrame())).filter((m) => m.kind === 'hello');
  expect(hellos).toHaveLength(1);
  expect(hellos[0].userAgent).toContain('AppleWebKit');
});

test('is not installed twice when injected twice', async ({ page }) => {
  await page.addInitScript({ content: detector });
  await page.goto(`${main.origin}/fetch-ct.html`);
  await expect.poll(() => page.evaluate(() => window.__text || '')).toContain('#EXTM3U');
  const hellos = (await messages(page.mainFrame())).filter((m) => m.kind === 'hello');
  expect(hellos).toHaveLength(1);
  // The request is reported once before the response and once more when its content type is known,
  // but never twice with the same information.
  const mpd = (await candidates(page.mainFrame())).filter((m) => m.url.endsWith('/media/x.mpd') && m.via === 'fetch');
  const signatures = mpd.map((m) => m.mime || '');
  expect(new Set(signatures).size).toBe(signatures.length);
  expect(signatures).toContain('application/dash+xml');
});
