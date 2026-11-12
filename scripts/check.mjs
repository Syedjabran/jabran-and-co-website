#!/usr/bin/env node
/* ============================================================================
   Jabran & Co — quality gate
   Zero dependencies. Run:  node scripts/check.mjs      (or: npm run check)
   Exits 1 on any ERROR. WARN lines are printed but do not fail the gate.

   Checks
     1. vercel.json is valid JSON
     2. every root *.js file parses
     3. every inline <script> in every *.html parses (classic JS) and every
        application/ld+json block is valid JSON
     4. every local href/src/poster/srcset in HTML points at a file that exists
     5. every <loc> in sitemap.xml maps to a page that exists
     6. no secrets in tracked text files (service-role JWTs, secret keys,
        private keys, provider API keys)
     7. supabase/functions/* and supabase/config.toml agree
   ============================================================================ */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const rel = (p) => path.relative(ROOT, p).split(path.sep).join('/');
let errors = 0, warns = 0;
const err = (m) => { errors++; console.log('  ERROR ' + m); };
const warn = (m) => { warns++; console.log('  WARN  ' + m); };
const section = (t) => console.log('\n• ' + t);

function trackedFiles() {
  try {
    return execFileSync('git', ['ls-files', '-co', '--exclude-standard'], { cwd: ROOT, encoding: 'utf8' })
      .split('\n').filter(Boolean).filter((f) => fs.existsSync(path.join(ROOT, f)));
  } catch {
    return fs.readdirSync(ROOT);
  }
}
const files = trackedFiles();
const rootFiles = files.filter((f) => !f.includes('/'));
const htmlFiles = rootFiles.filter((f) => f.endsWith('.html'));
const lineOf = (src, idx) => src.slice(0, idx).split('\n').length;

/* 1 · vercel.json ---------------------------------------------------------- */
section('vercel.json');
try { JSON.parse(fs.readFileSync(path.join(ROOT, 'vercel.json'), 'utf8')); console.log('  ok'); }
catch (e) { err('vercel.json: ' + e.message); }

/* 2 · root JS -------------------------------------------------------------- */
section('JavaScript files parse');
for (const f of rootFiles.filter((f) => f.endsWith('.js'))) {
  try { new vm.Script(fs.readFileSync(path.join(ROOT, f), 'utf8'), { filename: f }); }
  catch (e) { err(`${f}: ${e.message}`); }
}
console.log('  checked ' + rootFiles.filter((f) => f.endsWith('.js')).length + ' files');

/* 3 · inline scripts ------------------------------------------------------- */
section('Inline <script> blocks parse');
let inlineCount = 0;
const SCRIPT_RE = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
// Blank out HTML comments (keeping offsets) so commented-out markup is ignored.
const stripComments = (s) => s.replace(/<!--[\s\S]*?-->/g, (c) => c.replace(/[^\n]/g, ' '));
for (const f of htmlFiles) {
  const src = stripComments(fs.readFileSync(path.join(ROOT, f), 'utf8'));
  let m;
  while ((m = SCRIPT_RE.exec(src))) {
    const attrs = m[1] || '', body = m[2] || '';
    if (/\bsrc\s*=/.test(attrs) || !body.trim()) continue;
    const type = ((attrs.match(/\btype\s*=\s*["']?([^"'\s>]+)/i) || [])[1] || 'text/javascript').toLowerCase();
    const line = lineOf(src, m.index);
    if (type === 'application/ld+json') {
      try { JSON.parse(body); } catch (e) { err(`${f}:${line} ld+json: ${e.message}`); }
    } else if (type === 'text/javascript' || type === 'application/javascript') {
      inlineCount++;
      try { new vm.Script(body, { filename: `${f}:${line}` }); }
      catch (e) { err(`${f}:${line} inline script: ${e.message}`); }
    } else if (type === 'module') {
      warn(`${f}:${line} module script not syntax-checked`);
    }
  }
}
console.log('  checked ' + inlineCount + ' inline scripts in ' + htmlFiles.length + ' pages');

/* 4 · local references ----------------------------------------------------- */
section('Local links and assets exist');
const exists = new Set(files.map((f) => f.toLowerCase()));
const ATTR_RE = /\b(href|src|poster|srcset)\s*=\s*"([^"]*)"/gi;
let refCount = 0;
function checkRef(f, src, idx, raw) {
  let v = raw.trim();
  if (!v || /^(https?:|\/\/|mailto:|tel:|sms:|whatsapp:|#|javascript:|data:|blob:)/i.test(v)) return;
  if (/[`'+{}$<>]/.test(v)) return;               // built by JS / template
  v = v.split('#')[0].split('?')[0];
  if (!v || v === '/') return;
  let p = decodeURIComponent(v.replace(/^\.\//, '').replace(/^\//, ''));
  if (p.endsWith('/')) p += 'index.html';
  refCount++;
  const lc = p.toLowerCase();
  if (exists.has(lc)) {
    if (!files.includes(p)) warn(`${f}:${lineOf(src, idx)} "${raw}" differs in letter case from the file on disk`);
    return;
  }
  if (!path.extname(p) && exists.has(lc + '.html')) {
    warn(`${f}:${lineOf(src, idx)} "${raw}" relies on extensionless URL resolution (${p}.html)`);
    return;
  }
  if (KNOWN_MISSING.has(p)) { warn(`${f}:${lineOf(src, idx)} "${raw}" — known missing page (see docs/AUDIT-2026-11-12.md)`); return; }
  err(`${f}:${lineOf(src, idx)} broken reference "${raw}"`);
}
// Pages that are linked but were never built. Tracked in the audit; the owner
// decides whether to build them or drop the links. New broken links still fail.
const KNOWN_MISSING = new Set([]);
for (const f of htmlFiles) {
  const src = stripComments(fs.readFileSync(path.join(ROOT, f), 'utf8'));
  // ignore references that live inside <script> blocks (built at runtime)
  const masked = src.replace(SCRIPT_RE, (s) => ' '.repeat(s.length));
  let m;
  while ((m = ATTR_RE.exec(masked))) {
    if (m[1].toLowerCase() === 'srcset') {
      for (const part of m[2].split(',')) checkRef(f, src, m.index, part.trim().split(/\s+/)[0] || '');
    } else checkRef(f, src, m.index, m[2]);
  }
}
console.log('  checked ' + refCount + ' references');

/* 5 · sitemap ------------------------------------------------------------- */
section('sitemap.xml entries exist');
try {
  const sm = fs.readFileSync(path.join(ROOT, 'sitemap.xml'), 'utf8');
  const locs = [...sm.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((x) => x[1]);
  for (const loc of locs) {
    let p = new URL(loc).pathname.replace(/^\//, '');
    if (!p || p.endsWith('/')) p += 'index.html';
    if (!exists.has(p.toLowerCase()) && !exists.has((p + '.html').toLowerCase())) err(`sitemap.xml: ${loc} has no page`);
  }
  console.log('  checked ' + locs.length + ' URLs');
} catch (e) { err('sitemap.xml: ' + e.message); }

/* 6 · secrets ------------------------------------------------------------- */
section('No secrets committed');
const TEXT_EXT = /\.(html?|js|mjs|cjs|ts|json|md|txt|xml|toml|ya?ml|sql|css|env.*)$/i;
const SECRET_PATTERNS = [
  [/sb_secret_[A-Za-z0-9_-]{10,}/, 'Supabase secret key'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'private key'],
  [/\bre_[A-Za-z0-9]{8}_[A-Za-z0-9]{16,}/, 'Resend API key'],
  [/\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{24,}/, 'AI provider secret key'],
  [/\bAIza[0-9A-Za-z_-]{35}\b/, 'Google API key'],
  [/\bgh[pousr]_[A-Za-z0-9]{30,}/, 'GitHub token'],
  [/\bxox[abpr]-[A-Za-z0-9-]{10,}/, 'Slack token'],
];
for (const f of files) {
  if (!TEXT_EXT.test(f) || f === 'scripts/check.mjs' || f === '.env.example') continue;
  const src = fs.readFileSync(path.join(ROOT, f), 'utf8');
  for (const [re, name] of SECRET_PATTERNS) {
    const m = src.match(re);
    if (m) err(`${f}:${lineOf(src, m.index)} looks like a ${name}`);
  }
  for (const m of src.matchAll(/eyJ[A-Za-z0-9_-]{10,}\.(eyJ[A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}/g)) {
    try {
      const claims = JSON.parse(Buffer.from(m[1], 'base64url').toString('utf8'));
      if (claims.role && claims.role !== 'anon') err(`${f}:${lineOf(src, m.index)} JWT with role "${claims.role}"`);
    } catch { /* not a JWT */ }
  }
}
console.log('  scanned ' + files.filter((f) => TEXT_EXT.test(f)).length + ' text files');

/* 7 · edge functions ------------------------------------------------------ */
section('Supabase edge functions');
const fnDir = path.join(ROOT, 'supabase', 'functions');
if (fs.existsSync(fnDir)) {
  const dirs = fs.readdirSync(fnDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('_')).map((d) => d.name);
  for (const d of dirs) if (!fs.existsSync(path.join(fnDir, d, 'index.ts'))) err(`supabase/functions/${d} has no index.ts`);
  const cfgPath = path.join(ROOT, 'supabase', 'config.toml');
  const cfg = fs.existsSync(cfgPath) ? fs.readFileSync(cfgPath, 'utf8') : '';
  const declared = [...cfg.matchAll(/^\[functions\.([a-z0-9-]+)\]/gm)].map((x) => x[1]);
  for (const d of dirs) if (!declared.includes(d)) err(`supabase/config.toml has no [functions.${d}] (verify_jwt must be explicit)`);
  for (const d of declared) if (!dirs.includes(d)) err(`supabase/config.toml declares ${d} but supabase/functions/${d} is missing`);
  console.log('  ' + dirs.length + ' functions, ' + declared.length + ' declared in config.toml');
}

console.log(`\n${errors ? 'FAILED' : 'PASSED'} — ${errors} error(s), ${warns} warning(s)`);
process.exit(errors ? 1 : 0);
