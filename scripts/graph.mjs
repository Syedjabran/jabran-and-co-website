#!/usr/bin/env node
/* ============================================================================
   Jabran & Co — codebase graph
   Scans the repository (no network, no database) and writes
     docs/codebase-graph.json   nodes + edges, for tools and the visual map
     docs/CODEBASE-MAP.md       human summary with Mermaid diagrams
   Run:  npm run graph
   ============================================================================ */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const rootFiles = fs.readdirSync(ROOT).filter((f) => fs.statSync(path.join(ROOT, f)).isFile());
const pages = rootFiles.filter((f) => f.endsWith('.html')).sort();
const scripts = rootFiles.filter((f) => f.endsWith('.js')).sort();
const fnDir = path.join(ROOT, 'supabase', 'functions');
const functions = fs.existsSync(fnDir)
  ? fs.readdirSync(fnDir).filter((d) => fs.existsSync(path.join(fnDir, d, 'index.ts'))).sort()
  : [];

const nodes = new Map();
const edges = new Map();
function node(id, kind, extra = {}) {
  if (!nodes.has(id)) nodes.set(id, { id, kind, ...extra });
  else Object.assign(nodes.get(id), extra);
  return id;
}
function edge(from, to, kind) {
  const k = from + '|' + to + '|' + kind;
  if (from !== to && !edges.has(k)) edges.set(k, { from, to, kind });
}

const SNIPPETS = /snippet|insert-pack|-upgrade|revert-previous/;
function pageGroup(f) {
  if (SNIPPETS.test(f)) return 'snippet';
  if (f.startsWith('crm')) return 'crm';
  if (/-view\.html$/.test(f)) return 'document';
  if (/^(my-account|client-portal|reset-password|analytics-oauth|admin)\.html$/.test(f)) return 'portal';
  return 'public';
}
const titleOf = (src) => ((src.match(/<title>([^<]*)<\/title>/i) || [])[1] || '').trim();
const linesOf = (src) => src.split('\n').length;

function scanCode(id, src) {
  for (const m of src.matchAll(/\.from\(\s*['"]([a-z0-9_]+)['"]\s*\)/g)) {
    // storage.from('bucket') vs table
    const before = src.slice(Math.max(0, m.index - 12), m.index);
    if (/storage\s*$/.test(before)) edge(id, node('bucket:' + m[1], 'bucket', { label: m[1] }), 'storage');
    else edge(id, node('db:' + m[1], 'table', { label: m[1] }), 'data');
  }
  for (const m of src.matchAll(/\.rpc\(\s*['"]([a-z0-9_]+)['"]/g)) edge(id, node('rpc:' + m[1], 'rpc', { label: m[1] }), 'rpc');
  for (const m of src.matchAll(/functions\.invoke\(\s*['"]([a-z0-9-]+)['"]/g)) edge(id, 'fn:' + m[1], 'invokes');
  for (const m of src.matchAll(/functions\/v1\/([a-z0-9-]+)/g)) edge(id, 'fn:' + m[1], 'invokes');
}

const EXTERNAL = [
  [/api\.resend\.com/, 'Resend (email)'],
  [/api\.anthropic\.com/, 'Anthropic API'],
  [/generativelanguage\.googleapis\.com/, 'Google Gemini'],
  [/analyticsdata\.googleapis\.com/, 'GA4 Data API'],
  [/searchconsole\.googleapis\.com|webmasters/, 'Search Console API'],
  [/oauth2\.googleapis\.com|accounts\.google\.com/, 'Google OAuth'],
  [/graph\.facebook\.com|facebook\.com\/v\d/, 'Meta Graph API'],
  [/linkedin\.com\/oauth|api\.linkedin\.com/, 'LinkedIn API'],
  [/GMAIL_RELAY_URL/, 'Gmail relay (Apps Script)'],
];

/* functions first so page edges can attach to them */
for (const f of functions) {
  const src = fs.readFileSync(path.join(fnDir, f, 'index.ts'), 'utf8');
  node('fn:' + f, 'function', { label: f, file: `supabase/functions/${f}/index.ts`, lines: linesOf(src) });
  scanCode('fn:' + f, src);
  for (const [re, name] of EXTERNAL) if (re.test(src)) edge('fn:' + f, node('ext:' + name, 'external', { label: name }), 'calls');
  if (/SUPABASE_SERVICE_ROLE_KEY/.test(src)) nodes.get('fn:' + f).serviceRole = true;
}
const cfg = fs.existsSync(path.join(ROOT, 'supabase/config.toml')) ? read('supabase/config.toml') : '';
for (const m of cfg.matchAll(/\[functions\.([a-z0-9-]+)\]\s*\nverify_jwt\s*=\s*(true|false)/g)) {
  if (nodes.has('fn:' + m[1])) nodes.get('fn:' + m[1]).verifyJwt = m[2] === 'true';
}

for (const f of scripts) {
  const src = read(f);
  node('js:' + f, 'script', { label: f, file: f, lines: linesOf(src) });
  scanCode('js:' + f, src);
  for (const m of src.matchAll(/['"]([a-z0-9-]+\.js)['"]/g)) if (scripts.includes(m[1])) edge('js:' + f, 'js:' + m[1], 'loads');
}

for (const f of pages) {
  const src = read(f);
  const id = 'page:' + f;
  node(id, 'page', { label: f, file: f, group: pageGroup(f), title: titleOf(src), lines: linesOf(src) });
  for (const m of src.matchAll(/<script[^>]+src="([^"]+)"/g)) {
    const s = m[1];
    if (scripts.includes(s)) edge(id, 'js:' + s, 'includes');
    else if (/^https?:/.test(s)) {
      const lib = /supabase-js@([\d.]+)/.test(s) ? 'supabase-js ' + s.match(/supabase-js@([\d.]+)/)[1]
        : /Chart\.js\/([\d.]+)/.test(s) ? 'Chart.js ' + s.match(/Chart\.js\/([\d.]+)/)[1]
        : /qrcode/.test(s) ? 'qrcodejs' : /googletagmanager/.test(s) ? 'Google Tag Manager' : null;
      if (lib) edge(id, node('lib:' + lib, 'library', { label: lib }), 'includes');
    }
  }
  if (/connect\.facebook\.net|fbq\(/.test(src)) edge(id, node('ext:Meta Pixel', 'external', { label: 'Meta Pixel' }), 'tracks');
  if (/snap\.licdn\.com|px\.ads\.linkedin/.test(src)) edge(id, node('ext:LinkedIn Insight', 'external', { label: 'LinkedIn Insight' }), 'tracks');
  for (const m of src.matchAll(/href="([a-z0-9-]+\.html)(?:[#?][^"]*)?"/g)) {
    edge(id, 'page:' + m[1], 'links');
    if (!pages.includes(m[1])) node('page:' + m[1], 'page', { label: m[1], file: m[1], group: 'missing', title: '(missing)' });
  }
  scanCode(id, src);
}

/* any invoke edge pointing at a function folder that doesn't exist */
for (const e of edges.values()) if (e.to.startsWith('fn:') && !nodes.has(e.to)) node(e.to, 'function', { label: e.to.slice(3), missing: true });

/* classify db objects with the production inventory (supabase/schema/objects.json) */
const invPath = path.join(ROOT, 'supabase', 'schema', 'objects.json');
const inv = fs.existsSync(invPath) ? JSON.parse(fs.readFileSync(invPath, 'utf8')) : { tables: [], views: [], functions: [] };
const VIEWS = new Set(inv.views), TABLES = new Set(inv.tables), FNS = new Set(inv.functions);
for (const n of nodes.values()) {
  if (n.kind === 'table') {
    if (VIEWS.has(n.label)) n.kind = 'view';
    else if (!TABLES.has(n.label) && inv.tables.length) n.unknown = true;   // referenced but not in production
    n.domain = n.label.split('_')[0];
  } else if (n.kind === 'rpc' && inv.functions.length && !FNS.has(n.label)) n.unknown = true;
}
const unusedTables = inv.tables.filter((t) => !nodes.has('db:' + t));
const unusedViews = inv.views.filter((t) => !nodes.has('db:' + t));

const out = {
  generated: new Date().toISOString().slice(0, 10),
  counts: {},
  unused: { tables: unusedTables, views: unusedViews },
  nodes: [...nodes.values()].sort((a, b) => a.id.localeCompare(b.id)),
  edges: [...edges.values()],
};
for (const n of out.nodes) out.counts[n.kind] = (out.counts[n.kind] || 0) + 1;
out.counts.edges = out.edges.length;
fs.writeFileSync(path.join(ROOT, 'docs', 'codebase-graph.json'), JSON.stringify(out, null, 1) + '\n');

/* ---------- Markdown summary ---------- */
const by = (k) => out.nodes.filter((n) => n.kind === k);
const outE = (id, kind) => out.edges.filter((e) => e.from === id && (!kind || e.kind === kind));
const inE = (id, kind) => out.edges.filter((e) => e.to === id && (!kind || e.kind === kind));
const md = [];
md.push('# Codebase map', '', `Generated by \`npm run graph\` on ${out.generated} from the source (no database access).`,
  'Machine-readable graph: [`codebase-graph.json`](codebase-graph.json).', '');
md.push('| Kind | Count |', '|---|---|', ...Object.entries(out.counts).map(([k, v]) => `| ${k} | ${v} |`), '');

md.push('## Layers', '', '```mermaid', 'flowchart LR');
md.push('  subgraph Browser["Browser (Vercel static)"]');
for (const g of ['public', 'portal', 'document', 'crm']) md.push(`    ${g}["${g} pages (${by('page').filter((p) => p.group === g).length})"]`);
md.push('    shared["shared scripts (' + by('script').length + ')"]', '  end');
md.push('  subgraph Supabase', '    db[("Postgres: tables/views used by code (' + (by('table').length + by('view').length) + ')")]',
  '    rpc["RPCs called (' + by('rpc').length + ')"]', '    fns["Edge functions (' + by('function').length + ')"]',
  '    st[("Storage: ' + by('bucket').map((b) => b.label).join(', ') + '")]', '  end');
md.push('  ext["External: ' + by('external').map((x) => x.label).join(', ') + '"]');
md.push('  public & portal & document & crm --> shared --> db & rpc', '  crm & portal --> fns', 'shared --> fns', 'fns --> db & st & ext', '  crm --> st', '```', '');

md.push('## Edge functions', '', '```mermaid', 'flowchart LR');
for (const f of by('function')) {
  const fid = f.label.replace(/-/g, '_');
  md.push(`  ${fid}["${f.label}${f.verifyJwt === false ? ' (public)' : ''}"]`);
  for (const e of inE(f.id, 'invokes')) md.push(`  ${e.from.replace(/\W/g, '_')}["${nodes.get(e.from).label}"] --> ${fid}`);
  for (const e of outE(f.id, 'calls')) md.push(`  ${fid} --> ${e.to.replace(/\W/g, '_')}(["${nodes.get(e.to).label}"])`);
}
md.push('```', '');

md.push('## Pages', '', '| Page | Group | Shared scripts | Tables/views | RPCs | Functions |', '|---|---|---|---|---|---|');
for (const p of by('page').filter((p) => p.group !== 'missing')) {
  const s = outE(p.id, 'includes').filter((e) => e.to.startsWith('js:')).map((e) => nodes.get(e.to).label).join(', ');
  md.push(`| ${p.label} | ${p.group} | ${s || '–'} | ${outE(p.id, 'data').length} | ${outE(p.id, 'rpc').length} | ${outE(p.id, 'invokes').map((e) => nodes.get(e.to).label).join(', ') || '–'} |`);
}
md.push('');
const missing = by('page').filter((p) => p.group === 'missing');
if (missing.length) md.push('## Links to pages that do not exist', '', ...missing.map((m) => `- \`${m.label}\` ← ${inE(m.id, 'links').map((e) => nodes.get(e.from).label).join(', ')}`), '');

md.push('## Most-used tables and views', '', '| Object | Used by (files) |', '|---|---|');
for (const t of [...by('table'), ...by('view')].map((t) => [t, inE(t.id).length]).sort((a, b) => b[1] - a[1]).slice(0, 25)) md.push(`| ${t[0].label} | ${t[1]} |`);
md.push('');
const unknown = out.nodes.filter((n) => n.unknown);
if (unknown.length) md.push('## Referenced in code but not found in production', '', ...unknown.map((n) => `- \`${n.label}\` (${n.kind}) ← ${inE(n.id).map((e) => nodes.get(e.from).label).join(', ')}`), '');
md.push('## Production objects no file references directly', '',
  'Used only inside the database (triggers, RPCs, views) or not used yet.', '',
  `**Tables (${unusedTables.length}):** ${unusedTables.join(', ') || '–'}`, '',
  `**Views (${unusedViews.length}):** ${unusedViews.join(', ') || '–'}`, '');
fs.writeFileSync(path.join(ROOT, 'docs', 'CODEBASE-MAP.md'), md.join('\n'));

console.log('graph:', JSON.stringify(out.counts));
