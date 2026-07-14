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
