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
   MODULE AUTO-LOADER (Increment 12) — zero-HTML-edit deployment.
   crm-activity.js is already present on every staff page and the client
   portal, so it now injects each page's enterprise modules automatically.
   To integrate a future module: add one line to MODULES below, upload this
   file — done. No page markup ever changes again.
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined' || window.__jcoLoader) return;
  window.__jcoLoader = true;

  var path = (location.pathname.split('/').pop() || 'index.html').toLowerCase();
  var isPortal = path === 'my-account.html';
  var isStaff  = path.indexOf('crm') === 0;   /* crm.html + every crm-*.html */

  /* modules register on DOMContentLoaded; injected scripts may load after it
     fired — make late registrations run immediately */
  var origAdd = document.addEventListener.bind(document);
  document.addEventListener = function (type, fn, opts) {
    if (type === 'DOMContentLoaded' && document.readyState !== 'loading') {
      try { fn(); } catch (e) {}
      return;
    }
    return origAdd(type, fn, opts);
  };

  var MODULES = [];
  if (isStaff) {
    MODULES.push('crm-nav.js');                                   /* unified nav + attention bell */
    MODULES.push('crm-attachments.js');                           /* universal documents panel   */
    if (path === 'crm-orders.html') MODULES.push('crm-rm.js', 'crm-tracking.js');
    if (path === 'crm-command-center.html') MODULES.push('crm-ai-kpis.js');
  }
  if (isPortal) {
    MODULES.push('portal-documents.js', 'portal-tracking.js', 'client-ai-agent.js');
  }

  MODULES.forEach(function (src) {
    if (document.querySelector('script[src="' + src + '"]')) return;  /* respect manual tags */
    var s = document.createElement('script');
    s.src = src; s.defer = true;
    document.head.appendChild(s);
  });
})();
