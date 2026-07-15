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
