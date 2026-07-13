/* ============================================================================
   JABRAN & CO. CRM — crm-links.js · CROSS-MODULE RECORD CHAIN
   Include AFTER supabase-client.js on staff module pages:
     <script src="crm-links.js"></script>
   Usage inside any detail modal, after the record id is known:
     window.jcoRenderLinks(document.getElementById('xx-links'), 'order', orderId);
   Renders the full Enquiry → Opportunity → Quotation → Order → Invoice /
   Shipment / Project chain as branded chips linking to the right module.
   Data comes from the staff-gated crm_related_records() database function,
   so clients and suspended accounts get nothing.
============================================================================ */
(function () {
  function esc(s) {
    var d = document.createElement('div');
    d.textContent = s == null ? '' : String(s);
    return d.innerHTML;
  }
  function pretty(s) {
    return s ? String(s).replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); }) : '';
  }

  window.jcoRenderLinks = async function (el, entity, id) {
    if (!el || !id || typeof sb === 'undefined') return;
    el.innerHTML = '';
    try {
      var res = await sb.rpc('crm_related_records', { p_entity: entity, p_id: id });
      var rows = res.data || [];
      if (res.error || rows.length < 2) return; // nothing linked beyond itself

      var wrap = document.createElement('div');
      wrap.style.cssText =
        'border:1px solid var(--line); background:var(--bg-deep); padding:10px 14px;' +
        'margin:0 0 18px; display:flex; flex-wrap:wrap; gap:8px; align-items:center;';
      var lbl = document.createElement('span');
      lbl.textContent = 'RELATED RECORDS';
      lbl.style.cssText =
        "font-family:'IBM Plex Mono',monospace; font-size:9px; letter-spacing:0.22em;" +
        'color:var(--gold); margin-right:4px;';
      wrap.appendChild(lbl);

      rows.forEach(function (r) {
        var isSelf = r.id === id;
        var chip = document.createElement(isSelf ? 'span' : 'a');
        if (!isSelf) {
          var kindL = String(r.kind || '').toLowerCase();
          var docPage = r.page === 'quotation-view.html' ? 'quotation-view.html'
                      : (kindL === 'invoice' ? 'invoice-view.html' : null);
          chip.href = docPage
            ? docPage + '?id=' + r.id
            : r.page + '#' + kindL + '=' + r.id;
          chip.target = docPage ? '_blank' : '_self';
          chip.style.textDecoration = 'none';
          chip.title = 'Open ' + r.kind + (docPage ? ' document' : ' in ' + r.page);
        }
        chip.style.cssText += ';display:inline-block; font-family:"IBM Plex Mono",monospace;' +
          'font-size:10px; letter-spacing:0.04em; padding:4px 10px; border-radius:2px;' +
          'border:1px solid ' + (isSelf ? 'var(--gold)' : 'var(--line)') + ';' +
          'color:' + (isSelf ? 'var(--gold-light)' : 'var(--cream)') + '; white-space:nowrap;';
        chip.innerHTML =
          '<span style="color:var(--gold);">' + esc(r.kind) + '</span> ' +
          esc(r.number || '') +
          (r.status ? ' · <span style="color:var(--muted);">' + esc(pretty(r.status)) + '</span>' : '');
        wrap.appendChild(chip);
      });
      el.appendChild(wrap);
    } catch (e) { /* linking must never break the module */ }
  };
})();
