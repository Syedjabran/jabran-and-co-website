/* ============================================================================
   JABRAN & CO. CRM — crm-activity.js · EXTENDED AUDIT (view/print/download/export)
   Include AFTER supabase-client.js on staff pages, the client portal, and
   the quotation document:
     <script src="crm-activity.js"></script>

   Automatic:
   • Every browser print (Ctrl+P or the Print button) is logged with the page
     and, when set, the current document context.
   Manual, from any page:
   • window.jcoLogActivity('view'|'print'|'download'|'export', entity, id, detail)
   • window.jcoSetActivityContext(entity, id, detail)  — e.g. the quotation
     currently open, so prints attribute to the exact document.
   Logging is fire-and-forget: it can never block or break the page.
============================================================================ */
(function () {
  var ctx = { entity: null, id: null, detail: null };

  window.jcoSetActivityContext = function (entity, id, detail) {
    ctx = { entity: entity || null, id: id || null, detail: detail || null };
  };

  window.jcoLogActivity = function (event, entity, id, detail) {
    try {
      if (typeof sb === 'undefined') return;
      sb.rpc('crm_log_activity', {
        p_event: event,
        p_entity: entity || null,
        p_entity_id: id || null,
        p_detail: detail || null,
        p_user_agent: navigator.userAgent
      }).then(function(){}, function(){});
    } catch (e) { /* never interfere with the page */ }
  };

  window.addEventListener('beforeprint', function () {
    var page = location.pathname.split('/').pop() || 'page';
    window.jcoLogActivity('print', ctx.entity || 'page', ctx.id,
      ctx.detail || page);
  });
})();




/* ============================================================================
   NAV-SYNC ADDITION (Financial Intelligence phase)
   Appended so that uploading this ONE file adds the new module links to the
   sidebar of every CRM page that loads crm-activity.js — no page editing.
   • Links styled by the existing .crm-nav-item class.
   • Skips any link a page already has (the new pages ship with full menus).
   • Daily Expenses + AI Accountant appear for all staff; the management
     modules appear only for owner / super_admin / ceo / finance_manager —
     and every page enforces its own access regardless of what the menu shows.
   • Wrapped so it can never break a page.
============================================================================ */
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

      function makeLink(item) {
        var a = document.createElement('a');
        a.className = 'crm-nav-item';
        a.href = item.href;
        a.textContent = item.label;
        return a;
      }
      function place(items, anchorHref) {
        var pending = items.filter(function (i) {
          return !existing[i.href] && i.href !== here;
        });
        if (!pending.length) return;
        var anchor = side.querySelector('a[href="' + anchorHref + '"]');
        pending.forEach(function (i) {
          var a = makeLink(i);
          if (anchor && anchor.parentNode) {
            anchor.parentNode.insertBefore(a, anchor.nextSibling);
            anchor = a;
          } else {
            side.appendChild(a);
          }
          existing[i.href] = true;
        });
      }

      sb.rpc('crm_is_staff').then(function (r) {
        if (!r || r.data !== true) return;
        place(STAFF_LINKS, 'crm-finance.html');
        sb.rpc('crm_has_role', { roles: ['owner', 'super_admin', 'ceo', 'finance_manager'] })
          .then(function (r2) {
            if (r2 && r2.data === true) place(ADMIN_LINKS, 'crm-business-rules.html');
          }, function () {});
      }, function () {});
    }

    try { inject(); } catch (e) { /* the menu must never break a page */ }

    // Sidebars rendered after login (dashboard shows login first): re-check
    // briefly once a session exists, then stop.
    try {
      var tries = 0;
      var t = setInterval(function () {
        tries++;
        var side = document.querySelector('.crm-side');
        var visible = side && side.offsetParent !== null;
        if (visible) { try { inject(); } catch (e) {} }
        if (tries > 20) clearInterval(t);
      }, 1500);
    } catch (e) {}
  });
})();
