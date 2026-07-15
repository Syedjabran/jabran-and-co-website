// Shared Supabase connection for Jabran & Co
const SUPABASE_URL = "https://dvsaqjvcxqlzgpbvexnu.supabase.co";
const SUPABASE_KEY = "sb_publishable_h57UGgrQ7oFaRX8NTOKgYA_OGdWILM6";
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);




/* ============================================================================
   SCREEN PROTECTION (appended) — covers CRM pages AND the Client Portal,
   because every one of them loads supabase-client.js.

   Honest scope, stated plainly: no website can technically BLOCK screenshots
   — that power belongs to the operating system, not the browser. What this
   layer does is make every capture TRACEABLE and close the adjacent leaks:

   · Watermark — every signed-in session EXCEPT owner/super_admin renders a
     faint repeating overlay (account email · date) on CRM + portal pages.
     A leaked screenshot names its leaker. Self-restores if removed.
   · Print lockdown — Ctrl+P / browser print of CRM + portal pages produces
     a notice page instead of data.
   · The public website carries no watermark: it is public by definition,
     so a screenshot of it reveals nothing a visitor can't already see.
============================================================================ */
(function () {
  if (window.__jcoWatermark) return;
  window.__jcoWatermark = true;

  var page = (location.pathname.split('/').pop() || '').toLowerCase();
  var protectedPage = page.indexOf('crm') === 0 || page === 'my-account.html' ||
                      page.indexOf('-view.html') > -1;
  if (!protectedPage) return;

  /* print lockdown (CSS is bulletproof for the print path) */
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
        var s = await sb.auth.getSession();
        if (!s.data || !s.data.session) return;
        var clean = false;
        try {
          var r = await sb.rpc('crm_has_role', { roles: ['owner', 'super_admin'] });
          clean = !!(r && r.data === true);
        } catch (e) {}
        if (clean) return;                            /* owner sees clean screens */
        var stamp = (s.data.session.user.email || 'user') + ' \u00b7 ' +
                    new Date().toISOString().slice(0, 10);
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
    try { sb.auth.onAuthStateChange(function () { apply(); }); } catch (e) {}
  });
})();

/* ============================================================================
   EXPLICIT-SUBMIT LOGIN GUARD  (Issue 2)
   Loaded by EVERY authenticated surface (CRM, admin, employee, client portal,
   modals, legacy forms), so this is the single chokepoint every login path
   must pass through — the centralisation the fix needs without introducing a
   framework or rewriting each form.

   RULE ENFORCED: sb.auth.signInWithPassword() only proceeds when it is the
   direct consequence of an explicit user submission — a real form submit, a
   click on a submit/Log In control, or Enter pressed inside a form. Any call
   arriving from an input/change/blur handler, a watcher, a timer, a restored-
   credential path, or browser/password-manager autofill is refused before it
   reaches the network, and the reason is logged to the console with the page
   that attempted it.

   Also enforced here: no duplicate in-flight sign-in from rapid double-clicks.
   The intent is consumed on use, so one click can authorise exactly one call.

   NOT changed: session restoration. A previously signed-in user still resumes
   their session on load — that is persistence, not a login event, and it does
   not touch signInWithPassword.
============================================================================ */
(function () {
  if (typeof sb === 'undefined' || !sb || !sb.auth || !sb.auth.signInWithPassword) return;
  if (window.__jcoLoginGuard) return;
  window.__jcoLoginGuard = true;

  var INTENT_WINDOW_MS = 4000;
  var intentAt = 0, inFlight = false;

  function mark() { intentAt = Date.now(); }

  /* capture phase: recorded before any page handler runs */
  document.addEventListener('submit', mark, true);
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter') return;
    var t = e.target;
    if (t && t.closest && (t.closest('form') || t.closest('[data-login-form]'))) mark();
  }, true);
  document.addEventListener('click', function (e) {
    var t = e.target && e.target.closest ? e.target.closest('button, input[type="submit"], [role="button"]') : null;
    if (!t) return;
    var label = (t.textContent || t.value || '') + ' ' + (t.id || '');
    if (t.type === 'submit' || /log\s*in|sign\s*in|login|continue/i.test(label)) mark();
  }, true);

  var original = sb.auth.signInWithPassword.bind(sb.auth);

  sb.auth.signInWithPassword = function (credentials) {
    if (Date.now() - intentAt > INTENT_WINDOW_MS) {
      try {
        console.warn('[J&Co] Sign-in refused: no explicit submit. Page: ' +
          location.pathname + ' — a reactive trigger (input/change/blur/effect/autofill) attempted it.');
      } catch (e) {}
      return Promise.resolve({
        data: { user: null, session: null },
        error: { name: 'ExplicitSubmitRequired', status: 400,
                 message: 'Click the Log In button to sign in.' }
      });
    }
    if (inFlight) {
      return Promise.resolve({
        data: { user: null, session: null },
        error: { name: 'SignInInProgress', status: 429, message: 'Sign-in already in progress.' }
      });
    }
    intentAt = 0;                    /* one explicit action authorises one call */
    inFlight = true;
    return original(credentials).then(function (r) {
      setTimeout(function () { inFlight = false; }, 500);
      return r;
    }, function (err) {
      setTimeout(function () { inFlight = false; }, 500);
      throw err;
    });
  };
})();
