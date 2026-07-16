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
   JABRAN & CO. CRM — crm-auth.js · SHARED LAYER v2
   Loaded by all 23 CRM pages, so every fix here is one fix for the ecosystem.

   Contains, in order:
     1  recovery-link catcher      (password-reset emails landing anywhere)
     2  staff gate                 (strict client lockout — RLS is still the
                                    real boundary; this is the polite escort)
     3  responsive overrides       (portrait tablet + mobile usability)
     4  account menu               (ONE authoritative renderer — Issue 2 fix)
     5  nav-sync                   (module links, role-gated)

   PERFORMANCE (Issue 3): every block below reads jco.context() — ONE cached
   RPC — instead of firing its own crm_is_staff / crm_has_role / crm_staff_names
   round-trips. Measured in code: 13–19 auth requests per page load -> 1.
   The watermark lives in supabase-client.js (it also covers the portal); it is
   deliberately NOT duplicated here.
============================================================================ */

/* ---------------------------------------------------------------------------
   1 · RECOVERY-LINK CATCHER
--------------------------------------------------------------------------- */
(function () {
  try {
    var h = location.hash || '';
    if (h.indexOf('type=recovery') > -1 &&
        (location.pathname.split('/').pop() || '') !== 'reset-password.html') {
      location.replace('reset-password.html' + h);
    }
  } catch (e) {}
})();

/* ---------------------------------------------------------------------------
   2 · STAFF GATE — strict client lockout
   Clients are signed out of any crm-*.html page before a dashboard renders.
   Fail-closed: an explicit false ejects; a failed lookup retries once, then
   ejects. RLS already returns them nothing; this removes the cosmetic entry.
--------------------------------------------------------------------------- */
(function () {
  if (window.__jcoStaffGate) return;
  window.__jcoStaffGate = true;
  var page = (location.pathname.split('/').pop() || '').toLowerCase();
  if (page.indexOf('crm') !== 0) return;

  function eject() {
    try { sb.auth.signOut(); } catch (e) {}
    try { alert('This area is for Jabran & Co. staff only. Taking you to the Client Portal.'); } catch (e) {}
    location.replace('my-account.html');
  }

  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    async function enforce(attempt) {
      try {
        var s = await sb.auth.getSession();
        if (!s || !s.data || !s.data.session) return;      /* login screen handles it */
        var ctx = await jco.context();
        if (ctx && ctx.is_staff === true) return;          /* staff — carry on */
        if (!ctx && attempt < 1) { setTimeout(function () { enforce(attempt + 1); }, 1500); return; }
        eject();
      } catch (e) {
        if (attempt < 1) setTimeout(function () { enforce(attempt + 1); }, 1500);
        else eject();
      }
    }
    enforce(0);
    try { sb.auth.onAuthStateChange(function (ev) { if (ev === 'SIGNED_IN') enforce(0); }); } catch (e) {}
  });
})();

/* ---------------------------------------------------------------------------
   3 · RESPONSIVE OVERRIDES — portrait tablet + mobile, every CRM page
--------------------------------------------------------------------------- */
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
      '    -webkit-overflow-scrolling: touch; padding: 8px 6px !important;' +
      '    border-right: 0 !important; border-bottom: 1px solid rgba(198,165,90,0.22) !important; }' +
      '  .crm-side .crm-brand, .crm-nav-label { display: none !important; }' +
      '  .crm-nav-item { white-space: nowrap !important; border-left: 0 !important;' +
      '    border-bottom: 2px solid transparent !important; padding: 10px 14px !important; font-size: 13px !important; }' +
      '  .crm-nav-item.active { border-bottom-color: #C6A55A !important; background: transparent !important; }' +
      '  .crm-main { width: 100% !important; max-width: 100% !important; margin: 0 !important;' +
      '    padding: 18px 14px 80px !important; }' +
      '  .crm-topline { flex-direction: column !important; align-items: flex-start !important; gap: 10px !important; }' +
      '  .crm-topline h1, h1 { font-size: 22px !important; }' +
      '  .crm-grid2, .crm-grid3, .og-grid, .an-charts { grid-template-columns: 1fr !important; }' +
      '  .crm-kpis { grid-template-columns: repeat(2, 1fr) !important; }' +
      '  .crm-table { display: block !important; overflow-x: auto !important; -webkit-overflow-scrolling: touch; }' +
      '  .crm-table th, .crm-table td { white-space: nowrap !important; }' +
      '  .crm-modal { max-width: 96vw !important; padding: 20px 16px !important; }' +
      '  .crm-modal-bg { padding: 16px 8px !important; }' +
      '  input, select, textarea { font-size: 16px !important; }' +
      '  .crm-btn { padding: 12px 18px !important; }' +
      '  .aa-chat { min-height: 240px !important; max-height: 46vh !important; }' +
      '  .aa-msg { max-width: 94% !important; }' +
      '  .aa-input { flex-direction: column !important; }' +
      '  .aa-input input, .aa-input textarea { width: 100% !important; }' +
      '  .aa-kv { grid-template-columns: 110px 1fr !important; }' +
      '  .fs-tabs, .de-tabs, .pc-tabs, .fr-tabs, .og-tabs, .an-tabs { overflow-x: auto !important; }' +
      '  .de-appr, .fr-brow, .pc-wrow { grid-template-columns: 1fr !important; display: grid !important; }' +
      '}';
    document.head.appendChild(css);
  } catch (e) {}
})();

/* ---------------------------------------------------------------------------
   4 · ACCOUNT MENU — ONE authoritative renderer  (Issue 2 root-cause fix)

   ROOT CAUSE of the duplicate "Syed Jabran" buttons: build() was reachable
   from three paths (direct call, onAuthStateChange, and a setInterval poll),
   and its `built = true` flag was set AFTER `await sb.auth.getSession()`.
   Two entrants (DOMContentLoaded + INITIAL_SESSION, which fire together) both
   passed the `if (built) return` check while awaiting, then both inserted a
   #jco-topbar — duplicate IDs, two identical buttons, only the first wired to
   the menu. Not a CSS or breakpoint problem: an async double-init race.

   FIX (idempotent init, no hiding, no cleanup timers):
     · the single host element is CLAIMED SYNCHRONOUSLY, before any await —
       a second entrant sees it and returns;
     · the DOM itself is the initialisation marker (one #jco-topbar, ever);
     · if no session is found the host is released so a later login can build;
     · document-level listeners are registered exactly once, at module scope;
     · the setInterval poll is deleted entirely.
--------------------------------------------------------------------------- */
(function () {
  if (window.__jcoAccountMenu) return;
  window.__jcoAccountMenu = true;

  var page = (location.pathname.split('/').pop() || '').toLowerCase();
  if (page.indexOf('crm') !== 0) return;

  var MQ = '(max-width: 920px), (orientation: portrait) and (max-width: 1100px)';

  try {
    var css = document.createElement('style');
    css.id = 'jco-account-css';
    css.textContent = [
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
      '}',
      '@media (max-width: 380px) { .jco-acct-name { display: none; } }'
    ].join('\n');
    document.head.appendChild(css);
  } catch (e) {}

  var ROLE_LABEL = {
    owner: 'Owner', super_admin: 'Super Admin', ceo: 'CEO',
    finance_manager: 'Finance Manager', hr_manager: 'HR Manager',
    operations_manager: 'Operations Manager', business_development: 'Business Development',
    consultancy_manager: 'Consultancy Manager', trade_sourcing_manager: 'Trade Sourcing Manager',
    customs_manager: 'Customs Manager', account_manager: 'Account Manager',
    project_manager: 'Project Manager', document_controller: 'Document Controller',
    read_only_auditor: 'Read-Only Auditor'
  };
  var ROLE_ORDER = ['owner','super_admin','ceo','finance_manager','hr_manager','operations_manager',
                    'business_development','consultancy_manager','trade_sourcing_manager',
                    'customs_manager','account_manager','project_manager','document_controller','read_only_auditor'];

  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
  function initials(name) {
    var p = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!p.length) return 'JC';
    return ((p[0][0] || '') + (p.length > 1 ? (p[p.length - 1][0] || '') : '')).toUpperCase();
  }
  function roleLabelFrom(roles) {
    for (var i = 0; i < ROLE_ORDER.length; i++) {
      if (roles && roles.indexOf(ROLE_ORDER[i]) > -1) return ROLE_LABEL[ROLE_ORDER[i]];
    }
    return 'Staff';
  }
  function hideLegacy() {
    try {
      var rx = /^\s*(log|sign)\s*out(\s*(everywhere|from all devices|of all devices))?\s*$/i;
      var nodes = document.querySelectorAll('#crm-logout, #crm-logout-all, .crm-side a, .crm-side span, header a, header span, body > div');
      Array.prototype.forEach.call(nodes, function (el) {
        if (el.closest('#jco-topbar') || el.closest('#jco-confirm-bg')) return;
        if (el.children.length) return;
        if (rx.test(el.textContent || '')) el.classList.add('jco-legacy-logout');
      });
    } catch (e) {}
  }

  /* ---- listeners registered ONCE, at module scope (no per-build duplicates) */
  var menuEl = null, btnEl = null, lastFocus = null;
  function closeMenu(restore) {
    if (!menuEl) return;
    menuEl.hidden = true;
    if (btnEl) btnEl.setAttribute('aria-expanded', 'false');
    if (restore) (lastFocus && lastFocus.focus ? lastFocus : btnEl).focus();
  }
  document.addEventListener('click', function (e) {
    if (menuEl && !menuEl.hidden && !e.target.closest('#jco-account')) closeMenu(false);
  });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    var cbg = document.getElementById('jco-confirm-bg');
    if (cbg && cbg.classList.contains('open')) { cbg.classList.remove('open'); if (btnEl) btnEl.focus(); return; }
    if (menuEl && !menuEl.hidden) { e.preventDefault(); closeMenu(true); }
  });

  /* ---- THE single-host claim: synchronous, before any await ---- */
  function claimHost() {
    if (document.getElementById('jco-topbar')) return null;   /* already owned */
    var host = document.createElement('div');
    host.id = 'jco-topbar';
    document.body.insertBefore(host, document.body.firstElementChild);
    return host;
  }

  async function initAccountMenu() {
    if (typeof sb === 'undefined' || !document.body) return;
    var host = claimHost();
    if (!host) return;                     /* another entrant owns it — never append a second */

    var ctx = null;
    try { ctx = await jco.context(); } catch (e) {}
    if (!ctx) { host.remove(); return; }   /* signed out: release so a later login can build */

    var name = ctx.display_name || (ctx.email || 'Account').split('@')[0];
    var role = roleLabelFrom(ctx.roles || []);
    hideLegacy();

    host.innerHTML =
      '<div id="jco-account">' +
        '<button id="jco-acct-btn" type="button" aria-haspopup="menu" aria-expanded="false" aria-controls="jco-acct-menu">' +
          '<span class="jco-avatar" aria-hidden="true">' + esc(initials(name)) + '</span>' +
          '<span class="jco-acct-name">' + esc(name) + '</span>' +
          '<span class="jco-caret" aria-hidden="true">&#9662;</span>' +
        '</button>' +
        '<div id="jco-acct-menu" role="menu" aria-label="Account and security" hidden>' +
          '<div class="jco-m-head">' +
            '<div class="jco-m-name">' + esc(name) + '</div>' +
            '<div class="jco-m-email">' + esc(ctx.email || '') + '</div>' +
            '<div class="jco-m-role">' + esc(role) + '</div>' +
          '</div>' +
          '<div class="jco-m-sec">Session &amp; Security</div>' +
          '<button class="jco-m-item" role="menuitem" id="jco-signout" type="button">Sign out from this device</button>' +
          '<div class="jco-m-div"></div>' +
          '<button class="jco-m-item danger" role="menuitem" id="jco-signout-all" type="button">Sign out from all devices</button>' +
          '<div class="jco-m-note">Ends every active session, including phones and other browsers.</div>' +
        '</div>' +
      '</div>';

    btnEl = document.getElementById('jco-acct-btn');
    menuEl = document.getElementById('jco-acct-menu');

    btnEl.addEventListener('click', function (e) {
      e.stopPropagation();
      if (menuEl.hidden) {
        lastFocus = document.activeElement;
        menuEl.hidden = false;
        btnEl.setAttribute('aria-expanded', 'true');
        var first = menuEl.querySelector('.jco-m-item');
        if (first) first.focus();
      } else closeMenu(true);
    });

    document.getElementById('jco-signout').addEventListener('click', async function () {
      closeMenu(false);
      try { jco.clearContext(); } catch (e) {}
      try { await sb.auth.signOut({ scope: 'local' }); }
      catch (e) { try { await sb.auth.signOut(); } catch (e2) {} }
      location.replace('crm.html');
    });

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
      btnEl.focus();
    }
    document.getElementById('jco-signout-all').addEventListener('click', function () {
      closeMenu(false); cbg.classList.add('open'); goBtn.focus();
    });
    document.getElementById('jco-cancel').addEventListener('click', closeConfirm);
    cbg.addEventListener('click', function (e) { if (e.target === cbg) closeConfirm(); });

    goBtn.addEventListener('click', async function () {
      if (goBtn.disabled) return;
      goBtn.disabled = true; goBtn.textContent = 'Ending sessions…';
      cmsg.className = 'jco-cmsg'; cmsg.textContent = 'Revoking every active session…';
      try {
        await sb.from('crm_audit_logs').insert({
          action: 'sign_out_all_devices', entity: 'auth.users', entity_id: ctx.user_id,
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
      try { jco.clearContext(); } catch (e) {}
      cmsg.textContent = 'All sessions ended. Redirecting…';
      setTimeout(function () { location.replace('crm.html'); }, 700);
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    initAccountMenu();
    try {
      sb.auth.onAuthStateChange(function (ev) {
        if (ev === 'SIGNED_IN') initAccountMenu();     /* host claim makes this idempotent */
        if (ev === 'SIGNED_OUT') {
          var h = document.getElementById('jco-topbar');
          if (h) h.remove();
          menuEl = null; btnEl = null;
        }
      });
    } catch (e) {}
  });
  /* bfcache: Back/Forward restores the page with the host already present, so
     claimHost() returns null and nothing is appended. Nothing to clean up. */
})();

/* ---------------------------------------------------------------------------
   5 · NAV-SYNC — module links, role-gated, from the cached context
--------------------------------------------------------------------------- */
(function () {
  if (window.__jcoNavSync) return;
  window.__jcoNavSync = true;

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

  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    var done = false;

    async function inject() {
      if (done) return;
      var side = document.querySelector('.crm-side');
      if (!side) return;
      var ctx = await jco.context();
      if (!ctx || ctx.is_staff !== true) return;
      done = true;

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
          else side.appendChild(a);
          existing[i.href] = true;
        });
      }

      place(STAFF_LINKS, 'crm-finance.html');
      /* sits directly beneath Quotations & Costing, where it belongs */
      place([{ href: 'crm-outsourced-offers.html', label: 'Outsourced Service Offers' }],
            'crm-quotations.html');
      /* Pharma branch — added only now that a real page exists behind it. */
      sb.rpc('pharma_can', { p_permission: 'pharma.view' })
        .then(function (rp) {
          if (rp && rp.data === true) {
            place([{ href: 'crm-pharma-master.html', label: 'Pharma Master Data' }],
                  'crm-outsourced-offers.html');
          }
        }, function () {});
      var roles = ctx.roles || [];
      var isMgmt = ['owner','super_admin','ceo','finance_manager'].some(function (r) { return roles.indexOf(r) > -1; });
      if (isMgmt) place(ADMIN_LINKS, 'crm-business-rules.html');
      if (ctx.analytics && ctx.analytics.indexOf('analytics.view') > -1) {
        place([{ href: 'crm-analytics.html', label: 'AI Analytics' }], 'crm-ai-accountant.html');
      }
    }

    inject();
    try { sb.auth.onAuthStateChange(function (ev) { if (ev === 'SIGNED_IN') inject(); }); } catch (e) {}
  });
})();


/* ---------------------------------------------------------------------------
   7 · SEARCHABLE SELECTS — loaded here because every CRM page includes this
   file. crm-select.js enhances any <select> with more than 10 real options and
   leaves smaller ones completely alone. The native <select> remains the source
   of truth, so existing .value reads and change listeners are unaffected.
--------------------------------------------------------------------------- */
(function () {
  try {
    if (window.__jcoSelect) return;
    var s = document.createElement('script');
    s.src = 'crm-select.js?v=1';
    s.defer = true;
    document.head.appendChild(s);
  } catch (e) {}
})();
