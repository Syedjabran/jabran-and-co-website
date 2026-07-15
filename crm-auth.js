/* ============================================================================
   JABRAN & CO. CRM — crm-auth.js · SESSION SECURITY + FIELD CONFIG ENGINE
   Include on every CRM/portal page AFTER supabase-client.js:
     <script src="crm-auth.js"></script>
   Zero changes required to the pages' own login handlers — this file enhances
   them via auth-state events and DOM injection.

   Provides:
   • Remember Me (default OFF → session ends when the browser closes)
   • Forgot Password (Supabase reset email, returns to the same page)
   • Idle timeout with automatic logout (configurable in crm_settings)
   • Failed-login counter with temporary lockout (client-side, in addition to
     Supabase Auth's built-in server-side rate limiting)
   • Login/logout history recorded to crm_login_history
   • "Log out everywhere" (revokes ALL sessions on all devices)
   • Last-login display on the logout control
   • Field Configuration engine: applies crm_field_config rows to any form
============================================================================ */
document.addEventListener('DOMContentLoaded', function () {
  if (typeof sb === 'undefined') return;

  var REMEMBER_KEY = 'jco_crm_remember';
  var ALIVE_KEY    = 'jco_crm_session_alive';
  var FAIL_KEY     = 'jco_crm_failed_logins';
  var policy = { idle_timeout_minutes: 30, remember_me_days: 30 };

  function $(id){ return document.getElementById(id); }
  var loginForm = $('crm-login-form') || $('ma-login-form') || $('qv-login-form');
  var emailInput = $('crm-email') || $('ma-email') || $('qv-email');
  var logoutEl = $('crm-logout') || $('ma-logout');

  /* ------------------------------------------------------------------
     1 · SESSION VALIDITY GATE
     A persisted token + no Remember-Me + a fresh browser session means
     the previous "forever login" behaviour. Kill it before the page's
     own boot logic can auto-enter the CRM.
  ------------------------------------------------------------------ */
  (async function enforceSessionPolicy(){
    try {
      var { data } = await sb.auth.getSession();
      if (data && data.session) {
        var remembered = localStorage.getItem(REMEMBER_KEY) === '1';
        var alive = sessionStorage.getItem(ALIVE_KEY) === '1';
        if (!remembered && !alive) {
          await sb.auth.signOut();
          location.reload();
          return;
        }
        sessionStorage.setItem(ALIVE_KEY, '1');
        startIdleTimer();
        loadPolicy();
        decorateLogout();
      }
    } catch (e) { /* fail open to the login screen, never into the CRM */ }
  })();

  async function loadPolicy(){
    try {
      var { data } = await sb.rpc('crm_session_policy');
      if (data && data.idle_timeout_minutes) policy = data;
    } catch (e) {}
  }

  /* ------------------------------------------------------------------
     2 · LOGIN FORM ENHANCEMENTS (Remember Me + Forgot Password + lockout)
  ------------------------------------------------------------------ */
  if (loginForm && !$('jco-remember')) {
    var extras = document.createElement('div');
    extras.style.cssText = 'display:flex; justify-content:space-between; align-items:center; margin:2px 0 14px;';
    extras.innerHTML =
      '<label style="display:flex; align-items:center; gap:7px; font-size:12px; color:var(--muted); cursor:pointer; letter-spacing:0.02em;">' +
      '<input type="checkbox" id="jco-remember" style="width:auto; margin:0;"> Remember me</label>' +
      '<a href="#" id="jco-forgot" style="font-size:12px; color:var(--gold-light); text-decoration:none; letter-spacing:0.02em;">Forgot password?</a>';
    var submitBtn = loginForm.querySelector('button[type="submit"]');
    if (submitBtn) loginForm.insertBefore(extras, submitBtn);

    $('jco-forgot').addEventListener('click', async function (e) {
      e.preventDefault();
      var email = emailInput ? emailInput.value.trim() : '';
      var statusEl = $('crm-login-status') || $('ma-login-status') || $('qv-login-status');
      if (!email) { if (statusEl){ statusEl.textContent='Enter your email address first, then tap Forgot password.'; statusEl.style.color='var(--gold-light)'; } return; }
      var { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
      if (statusEl) {
        statusEl.textContent = error ? ('Could not send reset email: ' + error.message)
                                     : 'Password reset email sent. Check your inbox.';
        statusEl.style.color = error ? '#e57368' : 'var(--gold-light)';
      }
    });

    /* Failed-login lockout: runs alongside the page's own submit handler. */
    loginForm.addEventListener('submit', function (e) {
      var st = JSON.parse(localStorage.getItem(FAIL_KEY) || '{"n":0,"until":0}');
      if (st.until && Date.now() < st.until) {
        e.preventDefault(); e.stopImmediatePropagation();
        var mins = Math.ceil((st.until - Date.now()) / 60000);
        var statusEl = $('crm-login-status') || $('ma-login-status') || $('qv-login-status');
        if (statusEl){ statusEl.textContent = 'Too many failed attempts. Try again in ' + mins + ' minute(s).'; statusEl.style.color='#e57368'; }
        return;
      }
      setTimeout(async function () {
        var { data } = await sb.auth.getSession();
        if (!data || !data.session) {
          st.n = (st.n || 0) + 1;
          if (st.n >= 5) { st.until = Date.now() + 5 * 60000; st.n = 0; }
          localStorage.setItem(FAIL_KEY, JSON.stringify(st));
        }
      }, 1500);
    }, true);
  }

  /* ------------------------------------------------------------------
     3 · AUTH EVENTS — remember-me persistence + history logging
  ------------------------------------------------------------------ */
  sb.auth.onAuthStateChange(function (event) {
    if (event === 'SIGNED_IN') {
      var rem = $('jco-remember');
      if (rem) {
        if (rem.checked) localStorage.setItem(REMEMBER_KEY, '1');
        else localStorage.removeItem(REMEMBER_KEY);
      }
      sessionStorage.setItem(ALIVE_KEY, '1');
      localStorage.removeItem(FAIL_KEY);
      sb.rpc('crm_log_login_event', { p_event: 'login', p_user_agent: navigator.userAgent }).then(function(){},function(){});
      loadPolicy(); startIdleTimer(); decorateLogout();
    }
    if (event === 'SIGNED_OUT') {
      sessionStorage.removeItem(ALIVE_KEY);
      localStorage.removeItem(REMEMBER_KEY);
      stopIdleTimer();
    }
  });

  /* ------------------------------------------------------------------
     4 · IDLE TIMEOUT → automatic logout
  ------------------------------------------------------------------ */
  var idleTimer = null;
  function startIdleTimer(){
    stopIdleTimer();
    var ms = Math.max(5, policy.idle_timeout_minutes || 30) * 60000;
    idleTimer = setTimeout(async function () {
      try { await sb.rpc('crm_log_login_event', { p_event: 'timeout', p_user_agent: navigator.userAgent }); } catch(e){}
      await sb.auth.signOut();
      location.reload();
    }, ms);
  }
  function stopIdleTimer(){ if (idleTimer) { clearTimeout(idleTimer); idleTimer = null; } }
  ['click','keydown','scroll','touchstart'].forEach(function (ev) {
    document.addEventListener(ev, function(){ if (idleTimer) startIdleTimer(); }, { passive: true });
  });

  /* ------------------------------------------------------------------
     5 · LOGOUT DECORATION — history, last-login, logout everywhere
  ------------------------------------------------------------------ */
  async function decorateLogout(){
    if (!logoutEl) return;
    logoutEl.addEventListener('click', function () {
      sb.rpc('crm_log_login_event', { p_event: 'logout', p_user_agent: navigator.userAgent }).then(function(){},function(){});
    });
    if (!$('jco-logout-all')) {
      var all = document.createElement('div');
      all.id = 'jco-logout-all';
      all.textContent = 'Log Out Everywhere';
      all.style.cssText = 'position:fixed; top:48px; right:24px; z-index:90; font-size:10px; color:var(--muted); cursor:pointer; text-transform:uppercase; letter-spacing:0.08em;';
      all.title = 'Sign out of every device and browser';
      all.addEventListener('click', async function () {
        if (!confirm('Sign out of ALL devices and browsers?')) return;
        try { await sb.rpc('crm_log_login_event', { p_event: 'logout_all', p_user_agent: navigator.userAgent }); } catch(e){}
        await sb.auth.signOut({ scope: 'global' });
        location.reload();
      });
      document.body.appendChild(all);
    }
    try {
      var { data } = await sb.from('crm_login_history')
        .select('created_at').eq('event','login')
        .order('created_at', { ascending:false }).range(1,1);
      if (data && data[0]) {
        logoutEl.title = 'Last login: ' + new Date(data[0].created_at).toLocaleString();
      }
    } catch (e) {}
  }

  /* ------------------------------------------------------------------
     6 · FIELD CONFIGURATION ENGINE
     Any page can call: window.jcoApplyFieldConfig('prospects')
     after opening a form. Applies visible/hidden, mandatory, read-only,
     placeholder, tooltip, default value, and role-scope from
     crm_field_config — Owner edits rows, zero code changes.
  ------------------------------------------------------------------ */
  window.jcoApplyFieldConfig = async function (moduleName) {
    try {
      var { data: cfg } = await sb.from('crm_field_config').select('*').eq('module', moduleName);
      if (!cfg || !cfg.length) return;
      var roleScopes = { staff: true, client_visible: true };
      var probes = {
        finance_only:    sb.from('crm_invoices').select('id', { head:true, count:'exact' }),
        management_only: sb.from('crm_order_ebitda').select('order_id').limit(1),
        owner_only:      sb.from('crm_field_config').select('id', { head:true, count:'exact' })
      };
      // internal_only is true for any staff member reaching a staff page
      roleScopes.internal_only = true;
      for (var scope in probes) {
        try { var r = await probes[scope]; roleScopes[scope] = !r.error; }
        catch (e) { roleScopes[scope] = false; }
      }
      cfg.forEach(function (f) {
        if (f.is_custom) return;             // custom fields render via crm-forms.js
        var el = document.getElementById(f.field_id);
        if (!el) return;
        if (f.is_active === false) { (el.closest('div')||el).style.display='none'; el.required=false; return; }
        if (f.label) {                        // Owner-renamed built-in label
          var wrapEl = el.closest('div') || el;
          var lbEl = wrapEl.querySelector('label');
          if (lbEl) lbEl.textContent = f.label;
        }
        var wrap = el.closest('div') || el;
        var allowed = roleScopes[f.visibility_scope] !== false;
        if (!f.visible || !allowed) { wrap.style.display = 'none'; el.required = false; return; }
        wrap.style.display = '';
        el.required = !!f.mandatory;
        el.readOnly = !!f.readonly;
        if (f.readonly) el.style.opacity = '0.6';
        if (f.placeholder) el.placeholder = f.placeholder;
        if (f.tooltip) { el.title = f.tooltip; var lb = wrap.querySelector('label'); if (lb) lb.title = f.tooltip; }
        if (f.default_value && !el.value) el.value = f.default_value;
        if (f.mandatory) {
          var lab = wrap.querySelector('label');
          if (lab && lab.textContent.indexOf('*') === -1) lab.textContent += ' *';
        }
      });
    } catch (e) { /* configuration must never break data entry */ }
  };
});




/* ============================================================================
   ADDITIONS (Financial Intelligence phase) — appended to crm-auth.js because
   EVERY CRM page, including crm.html, loads this file. Three features:
   1) Recovery-link catcher: password-reset emails that land on any CRM page
      are forwarded to reset-password.html with their token intact.
   2) Nav-sync: injects the new module links into any management sidebar that
      lacks them (guarded — safe alongside the copy in crm-activity.js).
   3) Session watermark: every session EXCEPT owner/super_admin gets a faint
      traceable overlay (name · date) across CRM pages. Deterrence and
      traceability — see the honest note in chat: no website can technically
      BLOCK screenshots; this makes any leak attributable instead.
============================================================================ */

/* 1 · recovery-link catcher */
(function () {
  try {
    var h = location.hash || '';
    if (h.indexOf('type=recovery') > -1 &&
        (location.pathname.split('/').pop() || '') !== 'reset-password.html') {
      location.replace('reset-password.html' + h);
    }
  } catch (e) {}
})();

/* 2 · nav-sync (identical logic to crm-activity.js; double-load guarded) */
(function () {
  if (window.__jcoNavSync) return;
  window.__jcoNavSync = true;
  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    var STAFF_LINKS = [
      { href: 'crm-daily-entry.html',   label: 'Daily Expenses' },
      { href: 'crm-ai-accountant.html', label: 'AI Accountant' }
    ];
    var ADMIN_LINKS = [
      { href: 'crm-financial-settings.html', label: 'Financial Settings' },
      { href: 'crm-employee-costs.html',     label: 'Employee Costs' },
      { href: 'crm-organization.html',       label: 'Organization' },
      { href: 'crm-project-costing.html',    label: 'Project Costing' },
      { href: 'crm-finance-reports.html',    label: 'Financial Reports' },
      { href: 'crm-alerts.html',             label: 'Alerts' }
    ];
    function inject() {
      var side = document.querySelector('.crm-side');
      if (!side) return;
      var existing = {};
      side.querySelectorAll('a').forEach(function (a) {
        existing[(a.getAttribute('href') || '').split('#')[0]] = true;
      });
      var here = (location.pathname.split('/').pop() || '');
      function place(items, anchorHref) {
        var pending = items.filter(function (i) { return !existing[i.href] && i.href !== here; });
        if (!pending.length) return;
        var anchor = side.querySelector('a[href="' + anchorHref + '"]');
        pending.forEach(function (i) {
          var a = document.createElement('a');
          a.className = 'crm-nav-item'; a.href = i.href; a.textContent = i.label;
          if (anchor && anchor.parentNode) { anchor.parentNode.insertBefore(a, anchor.nextSibling); anchor = a; }
          else { side.appendChild(a); }
          existing[i.href] = true;
        });
      }
      sb.rpc('crm_is_staff').then(function (r) {
        if (!r || r.data !== true) return;
        place(STAFF_LINKS, 'crm-finance.html');
        sb.rpc('crm_has_role', { roles: ['owner','super_admin','ceo','finance_manager'] })
          .then(function (r2) { if (r2 && r2.data === true) place(ADMIN_LINKS, 'crm-business-rules.html'); }, function () {});
      }, function () {});
    }
    try { inject(); } catch (e) {}
    try {
      var tries = 0;
      var t = setInterval(function () {
        tries++;
        var side = document.querySelector('.crm-side');
        if (side && side.offsetParent !== null) { try { inject(); } catch (e) {} }
        if (tries > 20) clearInterval(t);
      }, 1500);
    } catch (e) {}
  });
})();

/* 3 · session watermark for every non-owner session */
(function () {
  if (window.__jcoWatermark) return;
  window.__jcoWatermark = true;
  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    async function apply() {
      try {
        var s = await sb.auth.getSession();
        if (!s.data || !s.data.session) return;
        var r = await sb.rpc('crm_has_role', { roles: ['owner', 'super_admin'] });
        if (r && r.data === true) return;                    /* owner sees clean screens */
        var who = (s.data.session.user.email || 'user');
        var stamp = who + ' \u00b7 ' + new Date().toISOString().slice(0, 10);
        var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="420" height="220">' +
          '<text x="0" y="120" font-family="monospace" font-size="15" fill="rgba(198,165,90,0.09)" ' +
          'transform="rotate(-28 210 110)">' + stamp.replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</text></svg>';
        var wm = document.createElement('div');
        wm.id = 'jco-wm';
        wm.style.cssText = 'position:fixed;inset:0;z-index:2147482000;pointer-events:none;' +
          'background-image:url("data:image/svg+xml;utf8,' + encodeURIComponent(svg) + '");' +
          'background-repeat:repeat;';
        document.body.appendChild(wm);
        /* if someone deletes the overlay via devtools, it comes back */
        new MutationObserver(function () {
          if (!document.getElementById('jco-wm')) document.body.appendChild(wm);
        }).observe(document.body, { childList: true });
      } catch (e) {}
    }
    apply();
    sb.auth.onAuthStateChange(function () { if (!document.getElementById('jco-wm')) apply(); });
  });
})();

/* ============================================================================
   4 · STAFF GATE — STRICT CLIENT LOCKOUT (security fix)
   Every page whose filename starts with "crm" now verifies the session is a
   STAFF account via crm_is_staff() the moment a session exists. Clients are
   signed out and sent to the Client Portal before any dashboard renders.
   Strict policy: only an explicit TRUE passes; an explicit FALSE ejects
   immediately; a failed check is retried once and then ejects. Every page's
   own gate still applies on top — this is the outer wall.
============================================================================ */
(function () {
  if (window.__jcoStaffGate) return;
  window.__jcoStaffGate = true;
  var page = (location.pathname.split('/').pop() || '').toLowerCase();
  if (page.indexOf('crm') !== 0) return;              /* CRM pages only */

  function eject(sb) {
    try { sb.auth.signOut(); } catch (e) {}
    try { alert('This area is for Jabran & Co. staff only. Taking you to the Client Portal.'); } catch (e) {}
    location.replace('my-account.html');
  }

  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    async function enforce(attempt) {
      try {
        var s = await sb.auth.getSession();
        if (!s.data || !s.data.session) return;       /* not logged in → login screen handles it */
        var r = await sb.rpc('crm_is_staff');
        if (r && r.data === true) return;             /* staff — carry on */
        if (r && r.error && attempt < 1) {            /* transient failure → one retry */
          setTimeout(function () { enforce(attempt + 1); }, 1500);
          return;
        }
        eject(sb);                                    /* explicit false, or still failing */
      } catch (e) {
        if (attempt < 1) setTimeout(function () { enforce(attempt + 1); }, 1500);
        else eject(sb);
      }
    }
    enforce(0);
    sb.auth.onAuthStateChange(function (ev) {
      if (ev === 'SIGNED_IN') enforce(0);
    });
  });
})();

/* ============================================================================
   5 · RESPONSIVE OVERRIDES — portrait tablet + mobile usability for EVERY
   CRM page (injected here so all ~20 pages get it from one file). Applies
   under 920px wide, and also in portrait up to 1100px so Chrome's
   "Desktop site" mode on tablets is covered too.
============================================================================ */
(function () {
  if (window.__jcoResponsive) return;
  window.__jcoResponsive = true;
  try {
    var css = document.createElement('style');
    css.id = 'jco-responsive';
    css.textContent =
      '@media (max-width: 920px), (orientation: portrait) and (max-width: 1100px) {' +
      '  html, body { overflow-x: hidden !important; }' +
      '  .crm-shell { display: block !important; }' +
      '  .crm-side { position: static !important; width: 100% !important; height: auto !important;' +
      '    display: flex !important; flex-wrap: nowrap !important; overflow-x: auto !important;' +
      '    -webkit-overflow-scrolling: touch; padding: 10px 6px !important;' +
      '    border-right: 0 !important; border-bottom: 1px solid rgba(198,165,90,0.22) !important; }' +
      '  .crm-side .crm-brand, .crm-nav-label { display: none !important; }' +
      '  .crm-nav-item { white-space: nowrap !important; border-left: 0 !important;' +
      '    border-bottom: 2px solid transparent !important; padding: 10px 14px !important; font-size: 13px !important; }' +
      '  .crm-nav-item.active { border-bottom-color: #C6A55A !important; background: transparent !important; }' +
      '  .crm-main { width: 100% !important; max-width: 100% !important; margin: 0 !important;' +
      '    padding: 18px 14px 80px !important; }' +
      '  .crm-topline { flex-direction: column !important; align-items: flex-start !important; gap: 10px !important; }' +
      '  .crm-topline h1, h1 { font-size: 22px !important; }' +
      '  .crm-grid2, .crm-grid3, .og-grid { grid-template-columns: 1fr !important; }' +
      '  .crm-kpis { grid-template-columns: repeat(2, 1fr) !important; }' +
      '  .crm-table { display: block !important; overflow-x: auto !important;' +
      '    -webkit-overflow-scrolling: touch; }' +
      '  .crm-table th, .crm-table td { white-space: nowrap !important; }' +
      '  .crm-modal { max-width: 96vw !important; padding: 20px 16px !important; }' +
      '  .crm-modal-bg { padding: 16px 8px !important; }' +
      '  input, select, textarea { font-size: 16px !important; }' +          /* stops mobile zoom-on-focus */
      '  .crm-btn { padding: 12px 18px !important; }' +
      '  #crm-logout { top: 10px !important; right: 12px !important; font-size: 10px !important; }' +
      '  .aa-chat { min-height: 240px !important; max-height: 46vh !important; }' +
      '  .aa-msg { max-width: 94% !important; }' +
      '  .aa-input { flex-direction: column !important; }' +
      '  .aa-input input, .aa-input textarea { width: 100% !important; }' +
      '  .aa-kv { grid-template-columns: 110px 1fr !important; }' +
      '  .fs-tabs, .de-tabs, .pc-tabs, .fr-tabs, .og-tabs { overflow-x: auto !important; }' +
      '  .de-appr, .fr-brow, .pc-wrow, .ec-al-row { grid-template-columns: 1fr !important; display: grid !important; }' +
      '}';
    document.head.appendChild(css);
  } catch (e) {}
})();

/* ============================================================================
   6 · LOGOUT BAR — portrait/mobile only.
   On narrow screens the sidebar becomes a horizontal nav strip along the top,
   which collided with the fixed top-right Log Out controls. Here the logout
   controls are lifted out of the corner into their own full-width sticky bar
   ABOVE the nav strip: nothing overlaps, nothing is hidden, and the nav can
   scroll its full length. Desktop is untouched (bar class is removed there).
============================================================================ */
(function () {
  if (window.__jcoLogoutBar) return;
  window.__jcoLogoutBar = true;

  var MQ = '(max-width: 920px), (orientation: portrait) and (max-width: 1100px)';

  try {
    var css = document.createElement('style');
    css.id = 'jco-logout-bar-css';
    css.textContent =
      '@media ' + MQ + ' {' +
      '  #crm-logout.jco-logout-bar:not([style*="none"]) {' +
      '    position: sticky !important; top: 0 !important; right: auto !important;' +
      '    z-index: 120 !important; width: 100% !important;' +
      '    display: flex !important; justify-content: flex-end !important; align-items: center !important;' +
      '    gap: 18px !important; padding: 9px 14px !important; margin: 0 !important;' +
      '    background: #08111C !important;' +
      '    border-bottom: 1px solid rgba(198,165,90,0.22) !important;' +
      '    font-family: "IBM Plex Mono", monospace !important; font-size: 10px !important;' +
      '    letter-spacing: 0.14em !important; text-transform: uppercase !important;' +
      '    color: #9C9690 !important; text-align: right !important; line-height: 1.4 !important;' +
      '  }' +
      '  #crm-logout.jco-logout-bar > * {' +
      '    display: inline-block !important; margin: 0 !important; padding: 0 !important;' +
      '    white-space: nowrap !important; cursor: pointer !important;' +
      '  }' +
      '  #crm-logout.jco-logout-bar > *:hover { color: #E4C98A !important; }' +
      '  .crm-side { padding-top: 8px !important; }' +
      '}';
    document.head.appendChild(css);
  } catch (e) {}

  document.addEventListener('DOMContentLoaded', function () {
    try {
      var lo = document.getElementById('crm-logout');
      if (!lo) return;
      var narrow = window.matchMedia(MQ);
      function place() {
        if (narrow.matches) {
          /* must sit above the shell in DOM order for the sticky bar to read right */
          if (document.body.firstElementChild !== lo) {
            document.body.insertBefore(lo, document.body.firstElementChild);
          }
          lo.classList.add('jco-logout-bar');
        } else {
          lo.classList.remove('jco-logout-bar');
        }
      }
      place();
      if (narrow.addEventListener) narrow.addEventListener('change', place);
      window.addEventListener('orientationchange', function () { setTimeout(place, 150); });
      window.addEventListener('resize', place);
    } catch (e) {}
  });
})();
