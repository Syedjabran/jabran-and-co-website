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
        /* AI Analytics: shown to anyone the DATABASE grants analytics.view —
           role-based visibility, and the page re-checks the permission itself. */
        sb.rpc('analytics_can', { p_permission: 'analytics.view' })
          .then(function (r3) {
            if (r3 && r3.data === true) {
              place([{ href: 'crm-analytics.html', label: 'AI Analytics' }], 'crm-ai-accountant.html');
            }
          }, function () {});
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
   6 · ACCOUNT MENU — consolidates BOTH logout controls into ONE account
   control, and ends the header collision at its root.

   ROOT CAUSE of the collision: "Log Out" / "Log Out Everywhere" were loose
   text links in a position:fixed top-right box. On desktop the nav is a LEFT
   sidebar so nothing collided; in portrait the sidebar becomes a horizontal
   strip along the SAME top edge, so the nav tabs (Services, Audit Logs,
   Alerts…) ran underneath the fixed box. Fix = remove the loose links, give
   the authenticated user one account control, and give it its own space:
     · desktop  → fixed top-right, clear of the left sidebar
     · portrait → sticky full-width bar ABOVE the nav strip (nothing overlaps,
                  the strip keeps its full scroll length, no tab is hidden)

   Actions:
     · Sign out from this device → sb.auth.signOut({scope:'local'})
     · Sign out from all devices → sb.auth.signOut({scope:'global'}), which
       revokes every refresh token for the user server-side (real revocation,
       not a localStorage wipe, and no service-role key in the browser).
       Confirmed first, audit-logged, success/error feedback shown.

   A11y: aria-haspopup/aria-expanded, role="menu"/"menuitem", Escape closes and
   restores focus, outside-click closes, :focus-visible rings, 44px targets.
============================================================================ */
(function () {
  if (window.__jcoAccountMenu) return;
  window.__jcoAccountMenu = true;

  var page = (location.pathname.split('/').pop() || '').toLowerCase();
  if (page.indexOf('crm') !== 0) return;              /* CRM surfaces only */

  var MQ = '(max-width: 920px), (orientation: portrait) and (max-width: 1100px)';

  /* ---- styles ---- */
  try {
    var css = document.createElement('style');
    css.id = 'jco-account-css';
    css.textContent = [
      /* legacy controls: hidden by stylesheet !important so inline display
         changes from page scripts cannot bring them back, and left in the DOM
         so existing page code that references them never throws */
      '#crm-logout, #crm-logout-all, .jco-legacy-logout { display: none !important; }',

      '#jco-topbar { position: fixed; top: 14px; right: 22px; z-index: 130; }',
      '#jco-account { position: relative; }',
      '#jco-acct-btn { display: flex; align-items: center; gap: 9px; min-height: 42px;',
      '  background: #08111C; border: 1px solid rgba(198,165,90,0.28); border-radius: 999px;',
      '  color: #F5F3EF; padding: 6px 14px 6px 6px; cursor: pointer;',
      '  font-family: Inter, sans-serif; font-size: 12px; letter-spacing: 0.04em; }',
      '#jco-acct-btn:hover { border-color: #C6A55A; }',
      '#jco-acct-btn:focus-visible { outline: 2px solid #E4C98A; outline-offset: 2px; }',
      '.jco-avatar { width: 30px; height: 30px; border-radius: 50%; flex-shrink: 0;',
      '  background: linear-gradient(135deg,#C6A55A,#B86A32); color: #0B0F14;',
      '  display: flex; align-items: center; justify-content: center;',
      '  font-family: "Playfair Display", serif; font-size: 12px; font-weight: 600; }',
      '.jco-acct-name { white-space: nowrap; max-width: 160px; overflow: hidden; text-overflow: ellipsis; }',
      '.jco-caret { color: #9C9690; font-size: 9px; }',

      '#jco-acct-menu { position: absolute; right: 0; top: calc(100% + 8px); width: 268px;',
      '  background: #0B0F14; border: 1px solid rgba(198,165,90,0.30); border-radius: 4px;',
      '  box-shadow: 0 16px 44px rgba(0,0,0,0.6); overflow: hidden; }',
      '#jco-acct-menu[hidden] { display: none; }',
      '.jco-m-head { padding: 14px 16px; background: #08111C; border-bottom: 1px solid rgba(198,165,90,0.18); }',
      '.jco-m-name { font-family: "Playfair Display", serif; font-size: 15px; color: #F5F3EF; }',
      '.jco-m-email { font-family: "IBM Plex Mono", monospace; font-size: 10px; color: #9C9690;',
      '  margin-top: 3px; word-break: break-all; }',
      '.jco-m-role { display: inline-block; margin-top: 9px; padding: 2px 8px;',
      '  font-family: "IBM Plex Mono", monospace; font-size: 9px; letter-spacing: 0.16em;',
      '  text-transform: uppercase; color: #E4C98A; border: 1px solid rgba(228,201,138,0.4); border-radius: 2px; }',
      '.jco-m-sec { font-family: "IBM Plex Mono", monospace; font-size: 9px; letter-spacing: 0.20em;',
      '  text-transform: uppercase; color: #C6A55A; padding: 12px 16px 4px; }',
      '.jco-m-item { display: block; width: 100%; min-height: 44px; text-align: left;',
      '  background: transparent; border: 0; color: #F5F3EF; cursor: pointer;',
      '  font-family: Inter, sans-serif; font-size: 13px; padding: 12px 16px; }',
      '.jco-m-item:hover { background: rgba(198,165,90,0.08); }',
      '.jco-m-item:focus-visible { outline: 2px solid #E4C98A; outline-offset: -2px; }',
      '.jco-m-item.danger { color: #e57368; }',
      '.jco-m-item.danger:hover { background: rgba(229,115,104,0.08); }',
      '.jco-m-div { height: 1px; background: rgba(198,165,90,0.18); margin: 6px 0; }',
      '.jco-m-note { font-family: "IBM Plex Mono", monospace; font-size: 9px; color: #9C9690;',
      '  padding: 0 16px 12px; line-height: 1.5; }',

      '#jco-confirm-bg { position: fixed; inset: 0; background: rgba(4,7,10,0.74); z-index: 140;',
      '  display: none; align-items: center; justify-content: center; padding: 20px; }',
      '#jco-confirm-bg.open { display: flex; }',
      '.jco-confirm { width: 100%; max-width: 420px; background: #111820;',
      '  border: 1px solid rgba(198,165,90,0.30); border-radius: 4px; padding: 26px; }',
      '.jco-confirm h2 { font-family: "Playfair Display", serif; font-size: 20px; color: #F5F3EF; margin: 0 0 10px; }',
      '.jco-confirm p { font-size: 13px; color: #9C9690; line-height: 1.6; margin: 0 0 20px; }',
      '.jco-crow { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }',
      '.jco-cbtn { min-height: 44px; padding: 11px 18px; font-size: 12px; letter-spacing: 0.08em;',
      '  text-transform: uppercase; border-radius: 2px; cursor: pointer; font-family: Inter, sans-serif; }',
      '.jco-cbtn:focus-visible { outline: 2px solid #E4C98A; outline-offset: 2px; }',
      '.jco-cbtn.ghost { background: transparent; color: #E4C98A; border: 1px solid rgba(198,165,90,0.35); }',
      '.jco-cbtn.danger { background: #e57368; color: #0B0F14; border: 0; font-weight: 600; }',
      '.jco-cbtn[disabled] { opacity: 0.55; cursor: not-allowed; }',
      '.jco-cmsg { font-family: "IBM Plex Mono", monospace; font-size: 11px; color: #E4C98A;',
      '  margin-top: 12px; text-align: right; min-height: 14px; }',
      '.jco-cmsg.bad { color: #e57368; }',

      '@media ' + MQ + ' {',
      '  #jco-topbar { position: sticky; top: 0; right: auto; width: 100%; display: flex;',
      '    justify-content: flex-end; padding: 8px 12px; background: #08111C;',
      '    border-bottom: 1px solid rgba(198,165,90,0.22); }',
      '  #jco-acct-menu { width: min(300px, calc(100vw - 24px)); }',
      '  .crm-side { padding-top: 8px !important; }',
      '}',
      '@media (max-width: 380px) { .jco-acct-name { display: none; } }'
    ].join('\n');
    document.head.appendChild(css);
  } catch (e) {}

  /* ---- helpers ---- */
  var ROLES = [
    ['owner', 'Owner'], ['super_admin', 'Super Admin'], ['ceo', 'CEO'],
    ['finance_manager', 'Finance Manager'], ['hr_manager', 'HR Manager'],
    ['operations_manager', 'Operations Manager'], ['business_development', 'Business Development']
  ];
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
  function initials(name) {
    var p = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!p.length) return 'JC';
    return ((p[0][0] || '') + (p.length > 1 ? (p[p.length - 1][0] || '') : '')).toUpperCase();
  }
  async function roleLabel() {
    for (var i = 0; i < ROLES.length; i++) {
      try {
        var r = await sb.rpc('crm_has_role', { roles: [ROLES[i][0]] });
        if (r && r.data === true) return ROLES[i][1];
      } catch (e) {}
    }
    return 'Staff';
  }
  async function displayName(uid, email) {
    try {
      var r = await sb.rpc('crm_staff_names');
      var m = (r.data || []).filter(function (x) { return x.user_id === uid; })[0];
      if (m && m.display_name) return m.display_name;
    } catch (e) {}
    return String(email || 'Account').split('@')[0];
  }

  function hideLegacy() {
    try {
      var rx = /^\s*(log|sign)\s*out(\s*(everywhere|from all devices|of all devices))?\s*$/i;
      var nodes = document.querySelectorAll('a, button, span, div, p');
      Array.prototype.forEach.call(nodes, function (el) {
        if (el.id === 'jco-topbar' || el.closest('#jco-topbar') || el.closest('#jco-confirm-bg')) return;
        if (el.children.length) return;                       /* leaf nodes only */
        if (rx.test(el.textContent || '')) el.classList.add('jco-legacy-logout');
      });
    } catch (e) {}
  }

  /* ---- build ---- */
  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    var built = false, lastFocus = null;

    async function build() {
      if (built) return;
      var s;
      try { s = await sb.auth.getSession(); } catch (e) { return; }
      if (!s || !s.data || !s.data.session) return;           /* login screen: nothing to show */
      var user = s.data.session.user;
      var uid = user.id, email = user.email || '';
      built = true;

      hideLegacy();
      var name = await displayName(uid, email);
      var role = await roleLabel();

      var bar = document.createElement('div');
      bar.id = 'jco-topbar';
      bar.innerHTML =
        '<div id="jco-account">' +
          '<button id="jco-acct-btn" type="button" aria-haspopup="menu" aria-expanded="false" aria-controls="jco-acct-menu">' +
            '<span class="jco-avatar" aria-hidden="true">' + esc(initials(name)) + '</span>' +
            '<span class="jco-acct-name">' + esc(name) + '</span>' +
            '<span class="jco-caret" aria-hidden="true">&#9662;</span>' +
          '</button>' +
          '<div id="jco-acct-menu" role="menu" aria-label="Account and security" hidden>' +
            '<div class="jco-m-head">' +
              '<div class="jco-m-name">' + esc(name) + '</div>' +
              '<div class="jco-m-email">' + esc(email) + '</div>' +
              '<div class="jco-m-role">' + esc(role) + '</div>' +
            '</div>' +
            '<div class="jco-m-sec">Session &amp; Security</div>' +
            '<button class="jco-m-item" role="menuitem" id="jco-signout" type="button">Sign out from this device</button>' +
            '<div class="jco-m-div"></div>' +
            '<button class="jco-m-item danger" role="menuitem" id="jco-signout-all" type="button">Sign out from all devices</button>' +
            '<div class="jco-m-note">Ends every active session, including phones and other browsers.</div>' +
          '</div>' +
        '</div>';
      document.body.insertBefore(bar, document.body.firstElementChild);

      var btn = document.getElementById('jco-acct-btn');
      var menu = document.getElementById('jco-acct-menu');

      function openMenu() {
        lastFocus = document.activeElement;
        menu.hidden = false;
        btn.setAttribute('aria-expanded', 'true');
        var first = menu.querySelector('.jco-m-item');
        if (first) first.focus();
      }
      function closeMenu(restore) {
        menu.hidden = true;
        btn.setAttribute('aria-expanded', 'false');
        if (restore) (lastFocus && lastFocus.focus ? lastFocus : btn).focus();
      }
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        if (menu.hidden) openMenu(); else closeMenu(true);
      });
      document.addEventListener('click', function (e) {
        if (!menu.hidden && !e.target.closest('#jco-account')) closeMenu(false);
      });
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && !menu.hidden) { e.preventDefault(); closeMenu(true); }
      });

      /* ---- sign out: this device only ---- */
      document.getElementById('jco-signout').addEventListener('click', async function () {
        closeMenu(false);
        try { await sb.auth.signOut({ scope: 'local' }); }
        catch (e) { try { await sb.auth.signOut(); } catch (e2) {} }
        location.replace('crm.html');                          /* replace() → no back-button return */
      });

      /* ---- sign out: all devices (confirmed + audited) ---- */
      var cbg = document.createElement('div');
      cbg.id = 'jco-confirm-bg';
      cbg.innerHTML =
        '<div class="jco-confirm" role="dialog" aria-modal="true" aria-labelledby="jco-ctitle">' +
          '<h2 id="jco-ctitle">Sign out from all devices?</h2>' +
          '<p>This will end your active sessions on this and every other device. You will need to sign in again.</p>' +
          '<div class="jco-crow">' +
            '<button class="jco-cbtn ghost" id="jco-cancel" type="button">Cancel</button>' +
            '<button class="jco-cbtn danger" id="jco-go" type="button">Sign out everywhere</button>' +
          '</div>' +
          '<div class="jco-cmsg" id="jco-cmsg" role="status"></div>' +
        '</div>';
      document.body.appendChild(cbg);

      var goBtn = document.getElementById('jco-go');
      var cmsg = document.getElementById('jco-cmsg');
      function closeConfirm() {
        cbg.classList.remove('open');
        cmsg.textContent = ''; cmsg.className = 'jco-cmsg';
        goBtn.disabled = false; goBtn.textContent = 'Sign out everywhere';
        btn.focus();
      }
      document.getElementById('jco-signout-all').addEventListener('click', function () {
        closeMenu(false);
        cbg.classList.add('open');
        goBtn.focus();
      });
      document.getElementById('jco-cancel').addEventListener('click', closeConfirm);
      cbg.addEventListener('click', function (e) { if (e.target === cbg) closeConfirm(); });
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && cbg.classList.contains('open')) closeConfirm();
      });

      goBtn.addEventListener('click', async function () {
        if (goBtn.disabled) return;                            /* double-submit guard */
        goBtn.disabled = true; goBtn.textContent = 'Ending sessions…';
        cmsg.className = 'jco-cmsg'; cmsg.textContent = 'Revoking every active session…';

        /* audit while the session is still valid (best-effort: blocked silently
           if crm_audit_logs RLS forbids client inserts) */
        try {
          await sb.from('crm_audit_logs').insert({
            action: 'sign_out_all_devices',
            entity: 'auth.users',
            entity_id: uid,
            after_value: { at: new Date().toISOString(), agent: String(navigator.userAgent).slice(0, 120) }
          });
        } catch (e) {}

        var res;
        try { res = await sb.auth.signOut({ scope: 'global' }); }
        catch (e) { res = { error: { message: String(e && e.message ? e.message : e) } }; }

        if (res && res.error) {
          cmsg.className = 'jco-cmsg bad';
          cmsg.textContent = 'Could not end all sessions: ' + res.error.message;
          goBtn.disabled = false; goBtn.textContent = 'Try again';
          return;
        }
        cmsg.textContent = 'All sessions ended. Redirecting…';
        setTimeout(function () { location.replace('crm.html'); }, 700);
      });
    }

    build();
    try {
      sb.auth.onAuthStateChange(function (ev) {
        if (ev === 'SIGNED_IN' || ev === 'INITIAL_SESSION' || ev === 'TOKEN_REFRESHED') build();
      });
    } catch (e) {}
    /* pages that reveal their shell only after login: re-check briefly */
    var n = 0, t = setInterval(function () { n++; build(); if (n > 8 || built) clearInterval(t); }, 1200);
  });
})();
