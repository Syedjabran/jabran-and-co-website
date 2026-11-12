// Builds the Codebase Map artifact: template + repo graph + inventory + health list.
// usage: node build.mjs <repoRoot> <outHtml>
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const [repo, out] = process.argv.slice(2);
const g = JSON.parse(fs.readFileSync(path.join(repo, 'docs/codebase-graph.json'), 'utf8'));
const inv = JSON.parse(fs.readFileSync(path.join(repo, 'supabase/schema/objects.json'), 'utf8'));
const health = JSON.parse(fs.readFileSync(path.join(here, 'health.json'), 'utf8'));
// keep only fields the page uses
const keep = ['id', 'kind', 'label', 'group', 'title', 'file', 'lines', 'verifyJwt', 'serviceRole', 'unknown', 'missing'];
g.nodes = g.nodes.map((n) => Object.fromEntries(keep.filter((k) => n[k] !== undefined && n[k] !== '').map((k) => [k, n[k]])));
const safe = (o) => JSON.stringify(o).replace(/</g, '\\u003c');
let html = fs.readFileSync(path.join(here, 'template.html'), 'utf8');
html = html.replace('/*__GRAPH__*/null', safe(g))
  .replace('/*__HEALTH__*/[]', safe(health))
  .replace('/*__INV__*/{}', safe({ tables: inv.tables, views: inv.views, functions: inv.functions }));
fs.writeFileSync(out, html);
console.log('wrote', out, Math.round(html.length / 1024) + ' KB');
