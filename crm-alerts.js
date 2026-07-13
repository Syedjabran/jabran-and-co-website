/* ============================================================================
   JABRAN & CO. CRM — crm-alerts.js
   FINANCIAL INTELLIGENCE · INCREMENT 7 — embeddable alert bell
   Add ONE line to any CRM page, after crm-auth.js:
     <script src="crm-alerts.js"></script>
   Renders a bottom-left bell with the live alert count for management users
   only (silent for everyone else and on pages without a session). Clicking
   opens crm-alerts.html. Dismissed alerts are excluded from the count.
   ============================================================================ */
document.addEventListener('DOMContentLoaded', function () {
  if (typeof sb === 'undefined') return;

  async function init() {
    try {
      var sess = await sb.auth.getSession();
      if (!sess.data || !sess.data.session) return;
      var role = await sb.rpc('crm_has_role', { roles: ['owner','super_admin','ceo','finance_manager'] });
      if (role.error || role.data !== true) return;

      var results = await Promise.all([
        sb.rpc('crm_alerts_now'),
        sb.from('crm_alert_dismissals').select('alert_key')
      ]);
      var alerts = results[0].data || [];
      var dismissed = {};
      (results[1].data || []).forEach(function (r) { dismissed[r.alert_key] = true; });
      var live = alerts.filter(function (a) { return !dismissed[a.alert_key]; });
      if (!live.length) return;
      var critical = live.filter(function (a) { return a.severity === 'critical'; }).length;

      var css = document.createElement('style');
      css.textContent =
        '#jco-alert-bell{position:fixed;left:20px;bottom:20px;z-index:95;display:flex;align-items:center;gap:8px;' +
        'background:#08111C;border:1px solid ' + (critical ? '#e57368' : 'rgba(198,165,90,0.45)') + ';' +
        'color:#E4C98A;padding:9px 14px;cursor:pointer;font-family:"IBM Plex Mono",monospace;font-size:11px;' +
        'letter-spacing:0.08em;border-radius:2px;box-shadow:0 4px 18px rgba(0,0,0,0.5);}' +
        '#jco-alert-bell:hover{border-color:#C6A55A;}' +
        '#jco-alert-bell .n{background:' + (critical ? '#e57368' : '#C6A55A') + ';color:#0a0a0b;' +
        'padding:1px 7px;border-radius:2px;font-weight:500;}';
      document.head.appendChild(css);

      var bell = document.createElement('div');
      bell.id = 'jco-alert-bell';
      bell.setAttribute('role', 'button');
      bell.setAttribute('aria-label', live.length + ' active alerts');
      bell.innerHTML = 'ALERTS <span class="n">' + live.length + '</span>' +
        (critical ? ' <span style="color:#e57368;">' + critical + ' critical</span>' : '');
      bell.addEventListener('click', function () { window.location.href = 'crm-alerts.html'; });
      document.body.appendChild(bell);
    } catch (e) { /* silent — the bell must never break a page */ }
  }

  init();
});
