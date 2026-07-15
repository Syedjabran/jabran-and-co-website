// Shared Supabase connection for Jabran & Co
const SUPABASE_URL = "https://dvsaqjvcxqlzgpbvexnu.supabase.co";
const SUPABASE_KEY = "sb_publishable_h57UGgrQ7oFaRX8NTOKgYA_OGdWILM6";
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

/* ============================================================================
   1 · SESSION CONTEXT CACHE  (performance — Issue 3)

   MEASURED PROBLEM: every CRM page fired 13–19 auth round-trips before its own
   data loaded (crm_is_staff x2, crm_has_role x2, a SEQUENTIAL crm_has_role
   loop x7 for the account-menu role label, crm_staff_names returning every
   staff row, analytics_can, plus the pre-existing session_policy/login_event).

   FIX: one crm_session_context() call per session, cached in sessionStorage
   (5-minute TTL, cleared on sign-out). Every consumer — staff gate, nav-sync,
   watermark, account menu — reads the cache. 13–19 calls -> 1.

   SECURITY: the cache is a convenience only. RLS is the real boundary, so a
   tampered sessionStorage value grants no data. The RPC only ever returns
   information about auth.uid().
============================================================================ */
window.jco = window.jco || {};
(function () {
  if (jco._ctxReady) return;
  jco._ctxReady = true;

  var TTL_MS = 5 * 60 * 1000;
  var inflight = null;

  function key(uid) { return 'jco_ctx_' + uid; }

  jco.clearContext = function () {
    inflight = null;
    try {
      for (var i = sessionStorage.length - 1; i >= 0; i--) {
        var k = sessionStorage.key(i);
        if (k && k.indexOf('jco_ctx_') === 0) sessionStorage.removeItem(k);
      }
    } catch (e) {}
  };

  /* Resolves to the context object, or null when signed out. */
  jco.context = function () {
    if (inflight) return inflight;
    inflight = (async function () {
      var s;
      try { s = await sb.auth.getSession(); } catch (e) { return null; }
      if (!s || !s.data || !s.data.session) return null;
      var uid = s.data.session.user.id;
      try {
        var raw = sessionStorage.getItem(key(uid));
        if (raw) {
          var hit = JSON.parse(raw);
          if (hit && (Date.now() - hit.at) < TTL_MS && hit.ctx) return hit.ctx;
        }
      } catch (e) {}
      var r;
      try { r = await sb.rpc('crm_session_context'); } catch (e) { r = { error: e }; }
      if (!r || r.error || !r.data) {
        /* migration 027 not applied yet, or offline: fail safe, do not cache */
        return null;
      }
      try { sessionStorage.setItem(key(uid), JSON.stringify({ at: Date.now(), ctx: r.data })); } catch (e) {}
      return r.data;
    })();
    return inflight;
  };

  jco.isStaff = async function () {
    var c = await jco.context();
    return !!(c && c.is_staff === true);
  };
  jco.hasRole = async function (roles) {
    var c = await jco.context();
    if (!c || !c.roles) return false;
    for (var i = 0; i < roles.length; i++) if (c.roles.indexOf(roles[i]) > -1) return true;
    return false;
  };
  jco.can = async function (permission) {
    var c = await jco.context();
    return !!(c && c.analytics && c.analytics.indexOf(permission) > -1);
  };

  try {
    sb.auth.onAuthStateChange(function (ev) {
      if (ev === 'SIGNED_OUT') jco.clearContext();
      if (ev === 'SIGNED_IN') { inflight = null; }   /* rebuild for the new user */
    });
  } catch (e) {}
})();

/* ============================================================================
   2 · EXPLICIT-SUBMIT LOGIN GUARD  (Issue 1)

   AUDIT RESULT (repository-wide, dump of 81 files): all 25 signInWithPassword
   call sites are inside a form submit handler with preventDefault(). There is
   NO input/change/blur/effect login trigger anywhere. The two ".click()" hits
   are CSV download links; the two "change" listeners are assignment dropdowns.
   The earlier guard did not fail — the live supabase-client.js never contained
   it (watermark-only copy was uploaded). It is now hardened and included here.

   RULE: signInWithPassword() proceeds ONLY within 4 s of a TRUSTED user
   gesture — a real pointerdown/click/Enter (event.isTrusted === true) inside a
   form. This is stricter than before: a bare 'submit' event no longer counts,
   because a password manager or script can fire one programmatically. Typing,
   autofill, credential restoration, auth-state listeners and reactive effects
   therefore cannot authenticate.

   NOT blocked: session restoration. An existing valid session still resumes —
   that is persistence, not a login event, and it never calls this method. Use
   ?authdebug=1 to see which of the two is actually happening.
============================================================================ */
(function () {
  if (typeof sb === 'undefined' || !sb.auth || !sb.auth.signInWithPassword) return;
  if (window.__jcoLoginGuard) return;
  window.__jcoLoginGuard = true;

  var INTENT_WINDOW_MS = 4000;
  var intentAt = 0, intentVia = '', inFlight = false;

  window.__jcoAuthLog = [];
  function log(kind, detail) {
    var row = { t: new Date().toISOString().slice(11, 23), kind: kind, detail: detail || '' };
    window.__jcoAuthLog.push(row);
    try { console.info('[J&Co auth] ' + kind + (detail ? ' — ' + detail : '')); } catch (e) {}
    try {
      var all = JSON.parse(sessionStorage.getItem('jco_auth_log') || '[]');
      all.push(row); sessionStorage.setItem('jco_auth_log', JSON.stringify(all.slice(-40)));
    } catch (e) {}
    if (window.__jcoAuthPanel) window.__jcoAuthPanel(row);
  }

  function mark(via) { intentAt = Date.now(); intentVia = via; }

  /* Only TRUSTED gestures count. isTrusted is false for script-dispatched
     events, which is exactly how password managers auto-submit. */
  document.addEventListener('pointerdown', function (e) {
    if (!e.isTrusted) return;
    var t = e.target && e.target.closest ? e.target.closest('button, input[type="submit"], [role="button"]') : null;
    if (t) mark('pointerdown:' + (t.id || t.textContent || 'button').toString().trim().slice(0, 24));
  }, true);

  document.addEventListener('click', function (e) {
    if (!e.isTrusted) { log('ignored', 'untrusted click (script/password-manager) — not a login intent'); return; }
    var t = e.target && e.target.closest ? e.target.closest('button, input[type="submit"], [role="button"]') : null;
    if (!t) return;
    var label = ((t.textContent || t.value || '') + ' ' + (t.id || '')).trim();
    if (t.type === 'submit' || /log\s*in|sign\s*in|login|continue/i.test(label)) mark('click:' + label.slice(0, 24));
  }, true);

  document.addEventListener('keydown', function (e) {
    if (!e.isTrusted || e.key !== 'Enter') return;
    var t = e.target;
    if (t && t.closest && t.closest('form')) mark('enter-key');
  }, true);

  var original = sb.auth.signInWithPassword.bind(sb.auth);

  sb.auth.signInWithPassword = function (credentials) {
    var age = Date.now() - intentAt;
    if (!intentAt || age > INTENT_WINDOW_MS) {
      var stack = '';
      try { stack = (new Error().stack || '').split('\n').slice(2, 5).join(' | ').replace(/https?:\/\/[^/]+\//g, ''); } catch (e) {}
      log('BLOCKED', 'sign-in without a trusted gesture on ' + location.pathname + ' ← ' + stack);
      return Promise.resolve({
        data: { user: null, session: null },
        error: { name: 'ExplicitSubmitRequired', status: 400,
                 message: 'Click the Log In button to sign in.' }
      });
    }
    if (inFlight) {
      log('duplicate', 'second sign-in suppressed (double-click)');
      return Promise.resolve({
        data: { user: null, session: null },
        error: { name: 'SignInInProgress', status: 429, message: 'Sign-in already in progress.' }
      });
    }
    log('explicit-submit', 'authorised by ' + intentVia + ' (' + age + ' ms ago) → signInWithPassword');
    intentAt = 0;                       /* one gesture authorises exactly one call */
    inFlight = true;
    return original(credentials).then(function (r) {
      setTimeout(function () { inFlight = false; }, 500);
      log(r && r.error ? 'rejected' : 'authenticated', r && r.error ? r.error.message : 'session created');
      return r;
    }, function (err) {
      setTimeout(function () { inFlight = false; }, 500);
      log('error', String(err && err.message ? err.message : err));
      throw err;
    });
  };

  /* Distinguish restoration from login, exactly as required. */
  try {
    sb.auth.onAuthStateChange(function (ev) {
      if (ev === 'INITIAL_SESSION') log('session-restored', 'existing session resumed — no login request was made');
      else if (ev === 'SIGNED_IN') log('auth-state', 'SIGNED_IN fired');
      else if (ev === 'SIGNED_OUT') log('auth-state', 'SIGNED_OUT fired');
      else if (ev === 'TOKEN_REFRESHED') log('auth-state', 'token refreshed (no login)');
    });
  } catch (e) {}
})();

/* ============================================================================
   3 · AUTH DEBUG OVERLAY — add ?authdebug=1 to any page URL.
   Renders the auth event log on-screen, so the login behaviour can be proven
   on a tablet with no DevTools. Never shows passwords or tokens.
============================================================================ */
(function () {
  try {
    if (location.search.indexOf('authdebug=1') < 0) return;
    document.addEventListener('DOMContentLoaded', function () {
      var box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:0;right:0;bottom:0;max-height:42vh;overflow:auto;' +
        'z-index:2147483600;background:#08111C;border-top:2px solid #C6A55A;color:#F5F3EF;' +
        'font-family:"IBM Plex Mono",monospace;font-size:10px;line-height:1.6;padding:10px 12px;';
      box.innerHTML = '<div style="color:#C6A55A;letter-spacing:.18em;margin-bottom:6px;">' +
        'AUTH DEBUG — every auth event on this page. BLOCKED = a sign-in was refused.</div><div id="jco-dbg-rows"></div>';
      document.body.appendChild(box);
      var rows = box.querySelector('#jco-dbg-rows');
      function paint(r) {
        var c = r.kind === 'BLOCKED' ? '#e57368'
              : (r.kind === 'explicit-submit' || r.kind === 'authenticated') ? '#7fc8a9'
              : (r.kind === 'session-restored') ? '#E4C98A' : '#9C9690';
        var d = document.createElement('div');
        d.style.color = c;
        d.textContent = r.t + '  ' + r.kind.toUpperCase() + '  ' + r.detail;
        rows.appendChild(d);
        rows.scrollTop = rows.scrollHeight;
      }
      try { (JSON.parse(sessionStorage.getItem('jco_auth_log') || '[]')).forEach(paint); } catch (e) {}
      window.__jcoAuthPanel = paint;
    });
  } catch (e) {}
})();

/* ============================================================================
   4 · SCREEN PROTECTION — CRM pages AND the Client Portal.
   Unchanged in behaviour; now reads the cached context instead of firing its
   own crm_has_role round-trip (one fewer request per page).

   Honest scope: no website can technically BLOCK screenshots — that power
   belongs to the operating system. This makes every capture TRACEABLE:
   · Watermark — every signed-in session EXCEPT owner/super_admin gets a faint
     overlay (account email · date). Self-restores if removed.
   · Print lockdown — printing a CRM/portal page yields a notice, not data.
   · The public website carries no watermark: it is public by definition.
============================================================================ */
(function () {
  if (window.__jcoWatermark) return;
  window.__jcoWatermark = true;

  var page = (location.pathname.split('/').pop() || '').toLowerCase();
  var protectedPage = page.indexOf('crm') === 0 || page === 'my-account.html' ||
                      page.indexOf('-view.html') > -1;
  if (!protectedPage) return;

  try {
    var pcss = document.createElement('style');
    pcss.textContent = '@media print{ body > *{display:none !important;} ' +
      'body:after{content:"Printing is disabled for JABRAN & CO. internal pages."; ' +
      'display:block; font-family:monospace; padding:40px;} }';
    document.head.appendChild(pcss);
  } catch (e) {}

  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    async function apply() {
      try {
        if (document.getElementById('jco-wm')) return;
        var ctx = await jco.context();
        if (!ctx) return;
        if (ctx.roles && (ctx.roles.indexOf('owner') > -1 || ctx.roles.indexOf('super_admin') > -1)) return;
        var stamp = (ctx.email || 'user') + ' \u00b7 ' + new Date().toISOString().slice(0, 10);
        var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="420" height="220">' +
          '<text x="0" y="120" font-family="monospace" font-size="15" ' +
          'fill="rgba(198,165,90,0.09)" transform="rotate(-28 210 110)">' +
          stamp.replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</text></svg>';
        var wm = document.createElement('div');
        wm.id = 'jco-wm';
        wm.style.cssText = 'position:fixed;inset:0;z-index:2147482000;pointer-events:none;' +
          'background-image:url("data:image/svg+xml;utf8,' + encodeURIComponent(svg) + '");' +
          'background-repeat:repeat;';
        document.body.appendChild(wm);
        new MutationObserver(function () {
          if (!document.getElementById('jco-wm')) document.body.appendChild(wm);
        }).observe(document.body, { childList: true });
      } catch (e) {}
    }
    apply();
    try { sb.auth.onAuthStateChange(function (ev) { if (ev === 'SIGNED_IN') apply(); }); } catch (e) {}
  });
})();
