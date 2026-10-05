// Builds TeleCast/Resources/blocklist.json (WebKit content rules) and adhosts.txt from domains.txt.
// Usage: node tools/blocklist/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const resources = path.resolve(here, '..', '..', 'TeleCast', 'Resources');

const domains = [
  ...new Set(
    fs
      .readFileSync(path.join(here, 'domains.txt'), 'utf8')
      .split(/\r?\n/)
      .map((line) => line.trim().toLowerCase())
      .filter((line) => line && !line.startsWith('#'))
  ),
].sort();

const escapeRegex = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Same pattern as AdGuard's Safari converter: scheme, optional subdomains, the domain, then a delimiter.
const rules = domains.map((domain) => ({
  trigger: { 'url-filter': `^[htpsw]+:\\/\\/([a-z0-9-]+\\.)?${escapeRegex(domain)}[\\/:&?]?` },
  action: { type: 'block' },
}));

fs.mkdirSync(resources, { recursive: true });
fs.writeFileSync(path.join(resources, 'blocklist.json'), JSON.stringify(rules, null, 1) + '\n');
fs.writeFileSync(path.join(resources, 'adhosts.txt'), domains.join('\n') + '\n');
console.log(`${rules.length} règles écrites dans ${path.join(resources, 'blocklist.json')}`);
