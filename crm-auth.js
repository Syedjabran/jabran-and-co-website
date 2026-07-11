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
