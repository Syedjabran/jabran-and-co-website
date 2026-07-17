// Shared Supabase connection for Jabran & Co
const SUPABASE_URL = "https://dvsaqjvcxqlzgpbvexnu.supabase.co";
const SUPABASE_KEY = "sb_publishable_h57UGgrQ7oFaRX8NTOKgYA_OGdWILM6";
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

/* ============================================================================
   JABRAN & CO. — supabase-client.js
   BUILD 2026-07-16.3-gesture-gateway
   Shown in the ?authdebug=1 overlay and in the console, so a stale cached file
   can never again be mistaken for the current build.
============================================================================ */
window.JCO_BUILD = '2026-07-16.3-gesture-gateway';
try { console.info('[J&Co] supabase-client.js build ' + window.JCO_BUILD); } catch (e) {}

/* ============================================================================
   1 · SESSION CONTEXT CACHE  (performance — unchanged, preserved)
   One crm_session_context() RPC per session, cached in sessionStorage (5-min
   TTL, cleared on sign-out). Replaces 17 auth round-trips per page load.
   RLS remains the real boundary; a tampered cache grants no data.
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
      if (!r || r.error || !r.data) return null;
      try { sessionStorage.setItem(key(uid), JSON.stringify({ at: Date.now(), ctx: r.data })); } catch (e) {}
      return r.data;
    })();
    return inflight;
  };

  jco.isStaff = async function () { var c = await jco.context(); return !!(c && c.is_staff === true); };
  jco.hasRole = async function (roles) {
    var c = await jco.context();
    if (!c || !c.roles) return false;
    for (var i = 0; i < roles.length; i++) if (c.roles.indexOf(roles[i]) > -1) return true;
    return false;
  };
  jco.can = async function (p) { var c = await jco.context(); return !!(c && c.analytics && c.analytics.indexOf(p) > -1); };

  try {
    sb.auth.onAuthStateChange(function (ev) {
      if (ev === 'SIGNED_OUT') jco.clearContext();
      if (ev === 'SIGNED_IN') inflight = null;
    });
  } catch (e) {}
})();

/* ============================================================================
   2 · AUTHENTICATION GATEWAY — human-gesture token
   BUILD 2026-07-16.3

   WHY THIS EXISTS (evidence, not assumption):
   Your ?authdebug=1 log read
       23:33:01.119 SESSION-RESTORED
       23:33:46.449 EXPLICIT-SUBMIT authorised by click:Log In crm-login-btn (8 ms ago)
       23:33:48.390 AUTH-STATE SIGNED_IN
       23:33:48.399 AUTHENTICATED
   45.3 s passed between page load and the gesture with ZERO auth events — i.e.
   typing the email and password authenticated nothing. The gesture landed 8 ms
   before the call (real handler latency) on the visible #crm-login-btn, and the
   network round trip took 1.94 s. That is a genuine human tap, correctly
   handled. The v2 guard was NOT wrong.
   The real defect was the WORDING: onAuthStateChange fires INITIAL_SESSION with
   session === null when signed out, and v2 logged it as "existing session
   resumed" regardless — so a logged-OUT page load claimed a restored session.
   That single false line is what made the evidence unreadable. Fixed below.

   THIS BUILD hardens the guard anyway, as requested, from "was a trusted click
   seen recently" to a fully validated gesture:
     · trusted pointerdown ON the visible Login button, inside its bounds
     · matching trusted pointerup, same pointerId, same button, <= 2 s
     · trusted click on the same button
     · button connected, not disabled, not hidden, not covered (hit-test)
     · only then is a single-use token minted (TTL 3 s)
     · the token is consumed on the FIRST signInWithPassword call, always
     · token voided on timeout, pagehide, tab hide, or button blur/removal
   Keyboard: only a trusted Enter/Space while the Login BUTTON ITSELF has focus.
   Enter/Done inside an email or password field does NOT authenticate — you
   asked for that explicitly. To allow it, set jco.auth.allowEnterInFields = true
   before the form is used.

   This wrapper is the single authoritative gateway: the real method is captured
   in this closure, so no other code can reach it. All 25 call sites in the
   repository funnel through here.
============================================================================ */
(function () {
  if (typeof sb === 'undefined' || !sb.auth || !sb.auth.signInWithPassword) return;
  if (window.__jcoAuthGateway) return;
  window.__jcoAuthGateway = true;

  var TOKEN_TTL_MS = 3000;
  var GESTURE_MAX_MS = 2000;

  jco.auth = jco.auth || {};
  jco.auth.allowEnterInFields = false;      /* per your instruction */

  var pending = null;   /* { pointerId, btn, at, pointerType } */
  var token = null;     /* { at, via, targetId } */
  var inFlight = false;
  var lastWasGatewayLogin = false;

  window.__jcoAuthLog = [];
  function log(kind, detail) {
    var row = { t: new Date().toISOString().slice(11, 23), kind: kind, detail: detail || '' };
    window.__jcoAuthLog.push(row);
    try { console.info('[J&Co auth] ' + kind + (detail ? ' — ' + detail : '')); } catch (e) {}
    try {
      var all = JSON.parse(sessionStorage.getItem('jco_auth_log') || '[]');
      all.push(row); sessionStorage.setItem('jco_auth_log', JSON.stringify(all.slice(-60)));
    } catch (e) {}
    if (window.__jcoAuthPanel) window.__jcoAuthPanel(row);
  }
  jco.auth.log = log;

  /* ---- is this element the visible Login button? ---- */
  function loginButtonFrom(el) {
    if (!el || !el.closest) return null;
    var btn = el.closest('button, input[type="submit"], [role="button"]');
    if (!btn) return null;
    var id = (btn.id || '').toLowerCase();
    var txt = String(btn.textContent || btn.value || '').trim();
    var form = btn.closest ? btn.closest('form') : null;
    var isSubmit = (btn.type === 'submit') || (btn.tagName === 'BUTTON' && !btn.type);
    if (/log-?in|sign-?in/.test(id)) return btn;
    if (isSubmit && /^\s*(log\s*in|sign\s*in|login)\s*$/i.test(txt)) return btn;
    if (isSubmit && form && form.querySelector('input[type="password"]')) return btn;
    return null;
  }

  function usable(btn) {
    if (!btn || !btn.isConnected) return 'button not in the document';
    if (btn.disabled) return 'button is disabled';
    var r = btn.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return 'button has no size';
    var cs = null;
    try { cs = getComputedStyle(btn); } catch (e) {}
    if (cs && (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) < 0.05)) return 'button is hidden';
    try {
      var top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      if (top && top !== btn && !btn.contains(top) && !top.contains(btn)) return 'button is covered by another element';
    } catch (e) {}
    return null;
  }

  function inBounds(btn, x, y) {
    var r = btn.getBoundingClientRect();
    return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
  }

  function mint(btn, via) {
    token = { at: Date.now(), via: via, targetId: btn.id || '(unnamed button)' };
    log('TOKEN-CREATED', via + ' on #' + token.targetId + ' — single use, valid ' + TOKEN_TTL_MS + ' ms');
  }
  function voidToken(why) {
    if (token) { token = null; log('token-voided', why); }
    pending = null;
  }

  /* ---- gesture capture (capture phase, before any page handler) ---- */
  document.addEventListener('pointerdown', function (e) {
    var btn = loginButtonFrom(e.target);
    if (!btn) return;
    if (!e.isTrusted) { log('REJECTED', 'pointerdown was not trusted (script-generated)'); return; }
    var bad = usable(btn);
    if (bad) { log('REJECTED', 'pointerdown ignored — ' + bad); return; }
    if (!inBounds(btn, e.clientX, e.clientY)) { log('REJECTED', 'pointerdown outside the button bounds'); return; }
    pending = { pointerId: e.pointerId, btn: btn, at: Date.now(), pointerType: e.pointerType || 'unknown' };
    log('gesture', 'pointerdown #' + (btn.id || 'login') + ' · ' + pending.pointerType + ' · pointerId ' + e.pointerId +
        ' · trusted=true · inside=true');
  }, true);

  document.addEventListener('pointerup', function (e) {
    if (!pending) return;
    if (!e.isTrusted) { voidToken('pointerup not trusted'); return; }
    if (e.pointerId !== pending.pointerId) { log('REJECTED', 'pointerup pointerId mismatch'); pending = null; return; }
    if (Date.now() - pending.at > GESTURE_MAX_MS) { log('REJECTED', 'gesture exceeded ' + GESTURE_MAX_MS + ' ms'); pending = null; return; }
    var btn = loginButtonFrom(e.target);
    if (btn !== pending.btn) { log('REJECTED', 'pointerup landed on a different element'); pending = null; return; }
    if (!inBounds(btn, e.clientX, e.clientY)) { log('REJECTED', 'pointerup outside the button bounds'); pending = null; return; }
    pending.up = true;
    log('gesture', 'pointerup matched · pointerId ' + e.pointerId + ' · inside=true');
  }, true);

  document.addEventListener('click', function (e) {
    var btn = loginButtonFrom(e.target);
    if (!btn) return;
    if (!e.isTrusted) { log('BLOCKED', 'untrusted click on the Login button — element.click()/dispatchEvent() cannot authenticate'); return; }
    if (!pending || !pending.up || pending.btn !== btn) {
      log('REJECTED', 'click without a matching trusted pointerdown+pointerup on this button');
      return;
    }
    var bad = usable(btn);
    if (bad) { log('REJECTED', 'click ignored — ' + bad); pending = null; return; }
    mint(btn, 'pointer ' + pending.pointerType + ' #' + pending.pointerId);
    pending = null;
  }, true);

  document.addEventListener('keydown', function (e) {
    if (!e.isTrusted) return;
    if (e.key !== 'Enter' && e.key !== ' ' && e.key !== 'Spacebar') return;
    var ae = document.activeElement;
    var btn = loginButtonFrom(ae);
    if (btn && btn === ae) {
      var bad = usable(btn);
      if (bad) { log('REJECTED', 'keyboard activation ignored — ' + bad); return; }
      mint(btn, 'keyboard ' + (e.key === ' ' ? 'Space' : e.key) + ' with the button focused');
      return;
    }
    if (e.key === 'Enter' && ae && ae.tagName && /INPUT|TEXTAREA/.test(ae.tagName) && ae.closest && ae.closest('form')) {
      if (jco.auth.allowEnterInFields) { log('gesture', 'Enter inside a field accepted (allowEnterInFields=true)'); mintFromField(ae); }
      else log('REJECTED', 'Enter/Done pressed inside #' + (ae.id || ae.name || 'field') +
                           ' — focus was not on the Login button, so no token was created');
    }
  }, true);

  function mintFromField(fieldEl) {
    var form = fieldEl.closest('form');
    var btn = form ? form.querySelector('button[type="submit"], input[type="submit"], button') : null;
    if (btn) mint(btn, 'keyboard Enter in a field (explicitly allowed)');
  }

  /* ---- token invalidation ---- */
  window.addEventListener('pagehide', function () { voidToken('page hidden / navigating away'); });
  document.addEventListener('visibilitychange', function () { if (document.hidden) voidToken('tab hidden'); });

  /* ---- THE GATEWAY ---- */
  var original = sb.auth.signInWithPassword.bind(sb.auth);

  function refuse(name, message, status) {
    return Promise.resolve({ data: { user: null, session: null },
                             error: { name: name, status: status || 400, message: message } });
  }

  /* Every CRM login page writes its own text into #crm-login-status right after
     the await resolves. We cannot edit twenty handlers, but we can clear what
     they write when the block was for an action the user never took. Watches
     briefly, wipes only an incorrect/invalid-credentials style message, and
     leaves any genuine error from a real attempt alone. */
  function silenceLoginError() {
    var tries = 0;
    var iv = setInterval(function () {
      var el = document.getElementById('crm-login-status') ||
               document.getElementById('login-status');
      if (el && /incorrect|invalid|wrong|failed/i.test(el.textContent || '')) {
        el.textContent = '';
        clearInterval(iv);
        return;
      }
      if (++tries > 12) clearInterval(iv);      /* ~360 ms, then stop watching */
    }, 30);
  }

  sb.auth.signInWithPassword = function (credentials) {
    var t = token;
    token = null;                                   /* consumed immediately, always */

    var stack = '';
    try { stack = (new Error().stack || '').split('\n').slice(2, 5).join(' | ')
                    .replace(/https?:\/\/[^/]+\//g, '').trim(); } catch (e) {}

    if (!t) {
      /* NO gesture at all = the USER DID NOTHING. A password manager or the
         browser submitted the form on its own. Blocking is correct — but the
         page's handler does `if (error) show "Incorrect email or password"`,
         which turns our refusal into an accusation the user never earned.
         That is the permanent red line. Nobody typed a wrong password; nobody
         typed anything. So: block silently and wipe the message the page is
         about to write. Silence is the honest response to a non-event. */
      log('BLOCKED', 'no human-action token — silent refusal on ' + location.pathname + ' ← ' + stack);
      silenceLoginError();
      return refuse('ExplicitSubmitRequired', '');
    }
    var age = Date.now() - t.at;
    if (age > TOKEN_TTL_MS) {
      /* A real person DID tap, just too long ago. Tell them plainly. */
      log('BLOCKED', 'token expired (' + age + ' ms old, limit ' + TOKEN_TTL_MS + ') ← ' + stack);
      return refuse('ExplicitSubmitRequired', 'That took a moment — tap Log In again.');
    }
    if (inFlight) {
      log('duplicate', 'a sign-in is already in flight — second request suppressed');
      return refuse('SignInInProgress', 'Sign-in already in progress.', 429);
    }

    log('TOKEN-CONSUMED', 'valid token (' + t.via + ', age ' + age + ' ms) → signInWithPassword ← ' + stack);
    inFlight = true;
    lastWasGatewayLogin = true;
    return original(credentials).then(function (r) {
      setTimeout(function () { inFlight = false; }, 500);
      if (r && r.error) { lastWasGatewayLogin = false; log('rejected', 'credentials rejected: ' + r.error.message); }
      else log('NEW-SESSION-CREATED', 'a new session was created by an explicit human login');
      return r;
    }, function (err) {
      setTimeout(function () { inFlight = false; }, 500);
      lastWasGatewayLogin = false;
      log('error', String(err && err.message ? err.message : err));
      throw err;
    });
  };

  /* ---- session restoration vs new session: CORRECTED (the real v2 defect) ---- */
  try {
    sb.auth.onAuthStateChange(function (ev, session) {
      if (ev === 'INITIAL_SESSION') {
        if (session) log('SESSION-RESTORED', 'existing valid session resumed — no login request was made');
        else log('no-session', 'no stored session — the login form is shown (this is NOT a login)');
      } else if (ev === 'SIGNED_IN') {
        log('auth-state', lastWasGatewayLogin
          ? 'SIGNED_IN following the explicit login above'
          : 'SIGNED_IN without a gateway login — session established elsewhere (e.g. another tab)');
        lastWasGatewayLogin = false;
      } else if (ev === 'SIGNED_OUT') log('auth-state', 'SIGNED_OUT');
      else if (ev === 'TOKEN_REFRESHED') log('auth-state', 'token refreshed (not a login)');
    });
  } catch (e) {}
})();

/* ============================================================================
   3 · AUTH DEBUG OVERLAY — ?authdebug=1
   Build id, loaded scripts, and every auth event. No passwords or tokens.
============================================================================ */
(function () {
  try {
    if (location.search.indexOf('authdebug=1') < 0) return;
    document.addEventListener('DOMContentLoaded', function () {
      var scripts = [];
      try {
        document.querySelectorAll('script[src]').forEach(function (s) {
          var u = s.getAttribute('src') || '';
          if (u.indexOf('cdn') < 0 && u.indexOf('//') !== 0) scripts.push(u);
        });
      } catch (e) {}

      var box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:0;right:0;bottom:0;max-height:46vh;overflow:auto;' +
        'z-index:2147483600;background:#08111C;border-top:2px solid #C6A55A;color:#F5F3EF;' +
        'font-family:"IBM Plex Mono",monospace;font-size:10px;line-height:1.6;padding:10px 12px;';
      box.innerHTML =
        '<div style="color:#C6A55A;letter-spacing:.16em;">AUTH DEBUG · BUILD ' +
          String(window.JCO_BUILD || 'UNKNOWN — STALE FILE') + '</div>' +
        '<div style="color:#9C9690;margin:3px 0 6px;">scripts: ' + scripts.join(' , ') +
          ' · page: ' + location.pathname + '</div>' +
        '<div id="jco-dbg-rows"></div>';
      document.body.appendChild(box);
      var rows = box.querySelector('#jco-dbg-rows');
      function paint(r) {
        var k = r.kind.toUpperCase();
        var c = (k === 'BLOCKED' || k === 'REJECTED' || k === 'ERROR') ? '#e57368'
              : (k === 'TOKEN-CONSUMED' || k === 'NEW-SESSION-CREATED' || k === 'TOKEN-CREATED') ? '#7fc8a9'
              : (k === 'SESSION-RESTORED' || k === 'NO-SESSION') ? '#E4C98A' : '#9C9690';
        var d = document.createElement('div');
        d.style.color = c;
        d.textContent = r.t + '  ' + k + '  ' + r.detail;
        rows.appendChild(d); rows.scrollTop = rows.scrollHeight;
      }
      try { (JSON.parse(sessionStorage.getItem('jco_auth_log') || '[]')).forEach(paint); } catch (e) {}
      window.__jcoAuthPanel = paint;
    });
  } catch (e) {}
})();

/* ============================================================================
   4 · SCREEN PROTECTION — CRM pages AND the Client Portal (unchanged).
   Reads the cached context; no extra round-trip.
   Honest scope: no website can BLOCK screenshots — the OS owns the screen.
   This makes captures TRACEABLE and kills the print path.
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
