/* ============================================================================
   JABRAN & CO. CRM — crm-forms.js · CUSTOM FIELDS RUNTIME (Form Builder)
   Include AFTER supabase-client.js on module pages:
     <script src="crm-forms.js"></script>
   Each modal that supports custom fields carries one marker div:
     <div class="jco-custom" data-module="prospects" data-idfield="p-id"></div>
   The runtime watches modals open, renders the Owner-defined fields for that
   module (type, options, validation, conditional visibility, role scope),
   loads saved values for the open record, and saves independently — no
   changes to any existing save handler.
============================================================================ */
(function () {
  var defsCache = {};   // module -> definitions
  var scopeCache = null;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }

  async function roleScopes() {
    if (scopeCache) return scopeCache;
    var s = { staff:true, client_visible:true, internal_only:true,
              finance_only:false, management_only:false, owner_only:false };
    try { var r = await sb.from('crm_invoices').select('id',{head:true,count:'exact'}); s.finance_only=!r.error; } catch(e){}
    try { var r2 = await sb.from('crm_order_ebitda').select('order_id').limit(1); s.management_only=!r2.error; } catch(e){}
    try { var r3 = await sb.rpc('crm_has_role',{roles:['owner']}); s.owner_only=r3.data===true; } catch(e){}
    scopeCache = s; return s;
  }

  async function defsFor(module) {
    if (defsCache[module]) return defsCache[module];
    try {
      var res = await sb.from('crm_field_config').select('*')
        .eq('module', module).eq('is_custom', true).eq('is_active', true)
        .order('display_order', { ascending:true, nullsFirst:false });
      defsCache[module] = res.data || [];
    } catch (e) { defsCache[module] = []; }
    return defsCache[module];
  }

  function inputHtml(f) {
    var base = 'data-jcf="' + esc(f.field_id) + '"';
    var ph = f.placeholder ? ' placeholder="'+esc(f.placeholder)+'"' : '';
    switch (f.field_type) {
      case 'textarea': return '<textarea '+base+ph+' style="min-height:56px;"></textarea>';
      case 'number':   return '<input type="number" step="any" '+base+ph+
                         (f.min_value!=null?' min="'+f.min_value+'"':'')+
                         (f.max_value!=null?' max="'+f.max_value+'"':'')+'>';
      case 'date':     return '<input type="date" '+base+'>';
      case 'checkbox': return '<label style="display:flex; gap:8px; align-items:center; text-transform:none; letter-spacing:0; font-size:13px; color:var(--cream); cursor:pointer;">'+
                         '<input type="checkbox" '+base+' style="width:auto;"> Yes</label>';
      case 'select':
        var opts = Array.isArray(f.options) ? f.options : [];
        return '<select '+base+'><option value="">—</option>'+
          opts.map(function(o){ return '<option value="'+esc(o)+'">'+esc(o)+'</option>'; }).join('')+'</select>';
      default:         return '<input type="text" '+base+ph+'>';
    }
  }

  function applyConditions(box, defs) {
    defs.forEach(function (f) {
      if (!f.visible_if_field) return;
      var row = box.querySelector('[data-jcfrow="'+f.field_id+'"]');
      var dep = box.querySelector('[data-jcf="'+f.visible_if_field+'"]');
      if (!row || !dep) return;
      var check = function () {
        var v = dep.type==='checkbox' ? (dep.checked?'true':'false') : dep.value;
        row.style.display = (String(v) === String(f.visible_if_value)) ? '' : 'none';
      };
      dep.addEventListener('change', check);
      dep.addEventListener('input', check);
      check();
    });
  }

  async function render(box) {
    var module = box.dataset.module;
    var idInput = document.getElementById(box.dataset.idfield);
    var recordId = idInput ? idInput.value.trim() : '';
    var defs = await defsFor(module);
    var scopes = await roleScopes();
    var visible = defs.filter(function (f) {
      return f.visible !== false && scopes[f.visibility_scope] !== false;
    });
    if (!visible.length) { box.innerHTML=''; return; }

    box.innerHTML =
      '<div style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; letter-spacing:0.2em; text-transform:uppercase; color:var(--gold); margin:22px 0 12px; border-bottom:1px solid var(--line); padding-bottom:6px;">Custom Fields</div>'+
      '<div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:14px 16px;">'+
      visible.map(function (f) {
        return '<div data-jcfrow="'+esc(f.field_id)+'">'+
          '<label style="display:block; font-size:11px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted); margin:0 0 5px;"'+
          (f.tooltip?' title="'+esc(f.tooltip)+'"':'')+'>'+esc(f.label||f.field_id)+(f.mandatory?' *':'')+'</label>'+
          inputHtml(f)+'</div>';
      }).join('')+'</div>'+
      '<div style="margin-top:12px;">'+
      '<button type="button" class="crm-btn ghost sm jco-custom-save" style="background:transparent; border:1px solid var(--line); color:var(--gold-light); padding:6px 12px; font-size:10px; letter-spacing:0.08em; text-transform:uppercase; cursor:pointer; border-radius:2px;">Save Custom Fields</button>'+
      '<span class="jco-custom-status" style="font-size:12px; color:var(--gold-light); margin-left:8px;"></span></div>';

    // read-only styling
    visible.forEach(function (f) {
      if (f.readonly) {
        var el = box.querySelector('[data-jcf="'+f.field_id+'"]');
        if (el) { el.readOnly = true; el.disabled = f.field_type==='select'||f.field_type==='checkbox'; el.style.opacity='0.6'; }
      }
    });
    applyConditions(box, visible);

    // load stored values
    if (recordId) {
      try {
        var vr = await sb.from('crm_custom_values').select('field_key,value')
          .eq('module', module).eq('record_id', recordId);
        (vr.data||[]).forEach(function (row) {
          var el = box.querySelector('[data-jcf="'+row.field_key+'"]');
          if (!el) return;
          if (el.type==='checkbox') el.checked = row.value==='true';
          else el.value = row.value==null?'':row.value;
          el.dispatchEvent(new Event('change'));
        });
      } catch (e) {}
    }

    box.querySelector('.jco-custom-save').addEventListener('click', async function () {
      var st = box.querySelector('.jco-custom-status');
      var rid = idInput ? idInput.value.trim() : '';
      if (!rid) { st.textContent='Save the record first, then save custom fields.'; return; }
      var rows = [], invalid = null;
      visible.forEach(function (f) {
        var el = box.querySelector('[data-jcf="'+f.field_id+'"]');
        if (!el) return;
        var v = el.type==='checkbox' ? (el.checked?'true':'false') : el.value.trim();
        if (f.mandatory && !v) invalid = invalid || (f.label+' is required.');
        if (v && f.validation_regex) {
          try { if (!(new RegExp(f.validation_regex)).test(v)) invalid = invalid || (f.label+' is not in the required format.'); } catch(e){}
        }
        if (v && f.field_type==='number') {
          var n = Number(v);
          if (f.min_value!=null && n < Number(f.min_value)) invalid = invalid || (f.label+' is below the minimum.');
          if (f.max_value!=null && n > Number(f.max_value)) invalid = invalid || (f.label+' is above the maximum.');
        }
        rows.push({ module:module, record_id:rid, field_key:f.field_id, value:v||null });
      });
      if (invalid) { st.textContent = invalid; return; }
      st.textContent='Saving…';
      var res = await sb.from('crm_custom_values').upsert(rows, { onConflict:'module,record_id,field_key' });
      st.textContent = res.error ? ('Error: '+res.error.message) : 'Custom fields saved.';
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    if (typeof sb === 'undefined') return;
    var boxes = document.querySelectorAll('.jco-custom');
    if (!boxes.length) return;
    boxes.forEach(function (box) {
      var modal = box.closest('.crm-modal-bg');
      if (!modal) return;
      var mo = new MutationObserver(function () {
        if (modal.style.display && modal.style.display !== 'none') render(box);
      });
      mo.observe(modal, { attributes:true, attributeFilter:['style'] });
    });
  });
})();
