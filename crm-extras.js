/* ============================================================================
   JABRAN & CO. CRM — crm-extras.js · SUPPORTING DOCUMENTS + KEY CONTACT
   Include AFTER supabase-client.js (and crm-forms.js if present) on:
     crm.html, crm-opportunities.html, crm-quotations.html,
     crm-orders.html, crm-finance.html
       <script src="crm-extras.js"></script>

   Zero per-page markup required. The runtime discovers module forms two ways:
     1. The existing Form-Builder marker  <div class="jco-custom" data-module="…">
     2. A built-in map of known form ids (payments, expenses, shipments,
        cost sheets, supplier offers) — with the record-id field auto-detected
        as the form's first hidden input.
   An optional manual marker also works:
        <div class="jco-extras" data-module="cost_sheets"></div>

   For each open modal it renders, above the save-button row:
     · KEY CONTACT — a person selector from the central crm_contacts register,
       filtered by the form's organization or vendor when one is chosen.
       Saved to <table>.key_contact_id with its own button (existing save
       handlers untouched).
     · SUPPORTING DOCUMENTS — upload bank receipts, invoices, GDs, proofs to
       the PRIVATE crm-private bucket (attachments/<module>/<record-id>/…),
       listed with signed-URL View and Remove. Requires migration 014.
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined') return;

  var MODULE_TABLE = {
    prospects:'crm_prospects', organizations:'crm_organizations',
    enquiries:'crm_enquiries', opportunities:'crm_opportunities',
    vendors:'crm_vendors', quotations:'crm_quotations',
    cost_sheets:'crm_cost_sheets', supplier_offers:'crm_supplier_offers',
    orders:'crm_orders', projects:'crm_projects', shipments:'crm_shipments',
    customs:'crm_customs_records', invoices:'crm_invoices',
    payments:'crm_payments', expenses:'crm_expenses'
  };
  /* modules that received key_contact_id in migration 014 */
  var HAS_CONTACT = { opportunities:1, cost_sheets:1, supplier_offers:1,
                      orders:1, invoices:1, payments:1, shipments:1 };
  /* fallback map for forms without a .jco-custom marker: formId -> module */
  var FORM_MAP = { 'pay-form':'payments', 'exp-form':'expenses',
                   'shipment-form':'shipments', 'project-form':'projects',
                   'cs-form':'cost_sheets', 'cost-form':'cost_sheets',
                   'costsheet-form':'cost_sheets', 'offer-form':'supplier_offers',
                   'so-form':'supplier_offers' };

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }
  function el(html){ var t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstChild; }

  function moduleFor(form){
    var m=form.querySelector('.jco-custom'); if(m&&m.dataset.module) return m.dataset.module;
    var x=form.querySelector('.jco-extras'); if(x&&x.dataset.module) return x.dataset.module;
    return FORM_MAP[form.id]||null;
  }
  function idInput(form){
    var m=form.querySelector('.jco-custom'); // marker declares the id field
    if(m&&m.dataset.idfield){ var d=document.getElementById(m.dataset.idfield); if(d) return d; }
    return form.querySelector('input[type="hidden"]');
  }
  function scopeSelect(form, needle){
    var sels=form.querySelectorAll('select');
    for(var i=0;i<sels.length;i++){ if((sels[i].id||'').indexOf(needle)>-1) return sels[i]; }
    return null;
  }

  /* -------------------------------------------------------------- contacts */
  async function loadContacts(orgId, vendorId){
    try{
      var q=sb.from('crm_contacts').select('id,full_name,first_name,last_name,designation,phone,email')
        .order('created_at',{ascending:false}).limit(200);
      if(vendorId) q=q.eq('vendor_id',vendorId);
      else if(orgId) q=q.eq('organization_id',orgId);
      var r=await q; return r.data||[];
    }catch(e){ return []; }
  }
  function contactName(c){
    return c.full_name || [c.first_name,c.last_name].filter(Boolean).join(' ') || c.email || 'Unnamed contact';
  }

  /* ------------------------------------------------------------ the widget */
  async function render(form){
    var module=moduleFor(form); if(!module) return;
    var table=MODULE_TABLE[module]; if(!table) return;
    var rid=(idInput(form)||{}).value||'';
    rid=String(rid).trim();

    var host=form.querySelector('.jco-extras-host');
    if(!host){
      host=el('<div class="jco-extras-host" style="margin-top:18px; border-top:1px solid rgba(198,165,90,0.22); padding-top:14px;"></div>');
      /* insert before the save-button row (last flex/button block in the form) */
      var rows=form.querySelectorAll('div');
      var anchor=null;
      for(var i=rows.length-1;i>=0;i--){
        if(rows[i].querySelector&&rows[i].querySelector('button[type="submit"]')){ anchor=rows[i]; break; }
      }
      if(anchor) form.insertBefore(host,anchor); else form.appendChild(host);
    }
    host.innerHTML='';

    /* ---- KEY CONTACT ---- */
    if(HAS_CONTACT[module]){
      var orgSel=scopeSelect(form,'organization_id');
      var vdSel=scopeSelect(form,'vendor_id');
      var block=el(
        '<div style="margin-bottom:16px;">'+
        '<div style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; letter-spacing:0.2em; text-transform:uppercase; color:var(--gold,#C6A55A); margin-bottom:8px;">Key Contact — query point for this record</div>'+
        '<div style="display:flex; gap:8px; flex-wrap:wrap; align-items:center;">'+
        '<select class="jx-contact" style="min-width:240px; padding:8px 10px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px;"><option value="">— select key contact —</option></select>'+
        '<button type="button" class="jx-contact-save" style="background:transparent; border:1px solid rgba(198,165,90,0.4); color:var(--gold-light,#E4C98A); padding:7px 12px; font-size:10px; letter-spacing:0.08em; text-transform:uppercase; cursor:pointer; border-radius:2px;">Save Contact</button>'+
        '<span class="jx-contact-status" style="font-size:12px; color:var(--gold-light,#E4C98A);"></span>'+
        '</div><div class="jx-contact-card" style="font-size:12px; color:var(--muted,#9C9690); margin-top:6px;"></div></div>');
      host.appendChild(block);

      var sel=block.querySelector('.jx-contact'),
          card=block.querySelector('.jx-contact-card'),
          st=block.querySelector('.jx-contact-status');

      async function fill(){
        var contacts=await loadContacts(orgSel&&orgSel.value, vdSel&&vdSel.value);
        var cur=sel.value;
        sel.innerHTML='<option value="">— select key contact —</option>'+
          contacts.map(function(c){ return '<option value="'+c.id+'">'+esc(contactName(c))+(c.designation?' · '+esc(c.designation):'')+'</option>'; }).join('');
        sel.value=cur;
        sel._contacts=contacts;
      }
      function showCard(){
        var c=(sel._contacts||[]).find(function(x){return x.id===sel.value;});
        card.textContent=c?[contactName(c),c.designation,c.phone,c.email].filter(Boolean).join(' · '):'';
      }
      sel.addEventListener('change',showCard);
      if(orgSel) orgSel.addEventListener('change',fill);
      if(vdSel) vdSel.addEventListener('change',fill);
      await fill();

      if(rid){
        try{
          var cr=await sb.from(table).select('key_contact_id').eq('id',rid).maybeSingle();
          if(cr.data&&cr.data.key_contact_id){
            if(![].some.call(sel.options,function(o){return o.value===cr.data.key_contact_id;})){
              var one=await sb.from('crm_contacts').select('id,full_name,first_name,last_name,designation,phone,email').eq('id',cr.data.key_contact_id).maybeSingle();
              if(one.data){ sel.appendChild(el('<option value="'+one.data.id+'">'+esc(contactName(one.data))+'</option>')); sel._contacts=(sel._contacts||[]).concat([one.data]); }
            }
            sel.value=cr.data.key_contact_id; showCard();
          }
        }catch(e){}
      }
      block.querySelector('.jx-contact-save').addEventListener('click', async function(){
        var nowId=(idInput(form)||{}).value||'';
        if(!String(nowId).trim()){ st.textContent='Save the record first, then set the contact.'; return; }
        st.textContent='Saving…';
        var r=await sb.from(table).update({key_contact_id: sel.value||null}).eq('id',String(nowId).trim());
        st.textContent=r.error?('Error: '+r.error.message):'Contact saved.';
      });
    }

    /* ---- SUPPORTING DOCUMENTS ----
       Superseded by crm-attachments.js (Increment 2). When that module is
       loaded it sets window.JCO_ATTACH_V2 and renders the enterprise panel
       (categories, visibility, versioning) in this exact spot instead. */
    if (window.JCO_ATTACH_V2) { if (window.jcoAttachRender) window.jcoAttachRender(form, module, host); return; }
    var attach=el(
      '<div>'+
      '<div style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; letter-spacing:0.2em; text-transform:uppercase; color:var(--gold,#C6A55A); margin-bottom:8px;">Supporting Documents — receipts, invoices, bank proofs, GDs</div>'+
      '<div class="jx-files" style="margin-bottom:10px;"></div>'+
      '<div style="display:flex; gap:8px; flex-wrap:wrap; align-items:center;">'+
      '<input type="file" class="jx-file" style="font-size:12px; color:var(--muted,#9C9690); max-width:260px;">'+
      '<input type="text" class="jx-label" placeholder="Label e.g. Bank transfer 15 May" style="padding:8px 10px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:12px; min-width:200px;">'+
      '<button type="button" class="jx-upload" style="background:transparent; border:1px solid rgba(198,165,90,0.4); color:var(--gold-light,#E4C98A); padding:7px 12px; font-size:10px; letter-spacing:0.08em; text-transform:uppercase; cursor:pointer; border-radius:2px;">Upload</button>'+
      '<span class="jx-att-status" style="font-size:12px; color:var(--gold-light,#E4C98A);"></span>'+
      '</div></div>');
    host.appendChild(attach);

    var list=attach.querySelector('.jx-files'),
        astat=attach.querySelector('.jx-att-status');

    async function refresh(){
      var nowId=(idInput(form)||{}).value||''; nowId=String(nowId).trim();
      if(!nowId){ list.innerHTML='<span style="font-size:12px; color:var(--muted,#9C9690);">Save the record first to attach documents.</span>'; return; }
      var r=await sb.from('crm_attachments').select('*').eq('module',module).eq('record_id',nowId).order('created_at',{ascending:false});
      var rows=r.data||[];
      list.innerHTML=rows.length?rows.map(function(a){
        return '<div style="display:flex; gap:10px; align-items:center; font-size:12px; padding:5px 0; border-bottom:1px solid rgba(198,165,90,0.1);" data-att="'+a.id+'">'+
          '<span style="flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis;">'+esc(a.label||a.file_name)+'</span>'+
          '<span style="font-family:\'IBM Plex Mono\',monospace; color:var(--muted,#9C9690);">'+esc((a.created_at||'').slice(0,10))+'</span>'+
          '<button type="button" data-view="'+a.id+'" style="background:none; border:1px solid rgba(198,165,90,0.3); color:var(--gold-light,#E4C98A); font-size:10px; padding:3px 8px; cursor:pointer; border-radius:2px;">View</button>'+
          '<button type="button" data-del="'+a.id+'" style="background:none; border:1px solid rgba(229,115,104,0.5); color:#e57368; font-size:10px; padding:3px 8px; cursor:pointer; border-radius:2px;">✕</button>'+
          '</div>';
      }).join(''):'<span style="font-size:12px; color:var(--muted,#9C9690);">No documents attached yet.</span>';

      list.querySelectorAll('[data-view]').forEach(function(b){
        b.addEventListener('click', async function(){
          var a=rows.find(function(x){return x.id===b.dataset.view;}); if(!a) return;
          var s=await sb.storage.from('crm-private').createSignedUrl(a.file_path,120);
          if(s.data&&s.data.signedUrl){ window.open(s.data.signedUrl,'_blank');
            if(window.jcoLogActivity) window.jcoLogActivity('view','attachment',a.id,a.file_name);
          } else astat.textContent='Could not open file.';
        });
      });
      list.querySelectorAll('[data-del]').forEach(function(b){
        b.addEventListener('click', async function(){
          var a=rows.find(function(x){return x.id===b.dataset.del;}); if(!a) return;
          if(!confirm('Remove "'+(a.label||a.file_name)+'"?')) return;
          await sb.storage.from('crm-private').remove([a.file_path]);
          await sb.from('crm_attachments').delete().eq('id',a.id);
          refresh();
        });
      });
    }
    await refresh();

    attach.querySelector('.jx-upload').addEventListener('click', async function(){
      var nowId=(idInput(form)||{}).value||''; nowId=String(nowId).trim();
      if(!nowId){ astat.textContent='Save the record first.'; return; }
      var f=attach.querySelector('.jx-file').files[0];
      if(!f){ astat.textContent='Choose a file.'; return; }
      if(f.size>15*1024*1024){ astat.textContent='Max 15 MB per file.'; return; }
      astat.textContent='Uploading…';
      var safe=f.name.replace(/[^A-Za-z0-9._-]+/g,'_').slice(-80);
      var path='attachments/'+module+'/'+nowId+'/'+Date.now()+'_'+safe;
      var up=await sb.storage.from('crm-private').upload(path,f,{contentType:f.type||'application/octet-stream'});
      if(up.error){ astat.textContent='Upload error: '+up.error.message; return; }
      var ins=await sb.from('crm_attachments').insert({
        module:module, record_id:nowId, file_path:path, file_name:f.name,
        label:attach.querySelector('.jx-label').value.trim()||null,
        content_type:f.type||null, size_bytes:f.size
      });
      if(ins.error){ astat.textContent='Error: '+ins.error.message; return; }
      astat.textContent='Attached.';
      attach.querySelector('.jx-file').value=''; attach.querySelector('.jx-label').value='';
      refresh();
    });
  }

  /* ------------------------------------------------ modal-open observation */
  function watch(){
    if(typeof sb==='undefined') return;
    document.querySelectorAll('.crm-modal-bg').forEach(function(m){
      if(m._jxWatched) return; m._jxWatched=true;
      new MutationObserver(function(){
        var visible=m.style.display&&m.style.display!=='none';
        if(!visible) return;
        var form=m.querySelector('form'); if(!form) return;
        /* delay so the page's own open handler populates the hidden id first */
        setTimeout(function(){ render(form).catch(function(){}); },350);
      }).observe(m,{attributes:true,attributeFilter:['style','class']});
    });
  }
  document.addEventListener('DOMContentLoaded', function(){ watch(); setTimeout(watch,1500); });
})();


