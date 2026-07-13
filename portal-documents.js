/* ============================================================================
   JABRAN & CO. — portal-documents.js · CLIENT PORTAL DOCUMENTS TAB
   Requires: migration 018 · supabase-client.js
   Include on my-account.html, after the page's own script:
       <script src="portal-documents.js"></script>
   Injects a "Documents" tab into the portal: lists every client-visible
   file for the client's organization (RLS decides — the page never filters),
   with short-lived signed-URL viewing, plus a controlled upload flow into
   attachments/portal/<org-id>/ (server trigger locks visibility & approval).
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined') return;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }
  function el(h){ var d=document.createElement('div'); d.innerHTML=h.trim(); return d.firstChild; }
  function kb(n){ n=n||0; return n>1048576?(n/1048576).toFixed(1)+' MB':Math.max(1,Math.round(n/1024))+' KB'; }

  var CLIENT_CATS=[['other','General'],['correspondence','Correspondence'],
    ['specification','Specification'],['payment_evidence','Payment Evidence'],
    ['purchase_order','Purchase Order'],['compliance_certificate','Compliance Certificate']];
  var ALLOWED=['pdf','png','jpg','jpeg','webp','doc','docx','xls','xlsx','csv','txt','ppt','pptx'];
  var MAX=10*1024*1024;

  var orgId=null, cats={};

  async function init(){
    if (typeof sb==='undefined') return;
    var app=document.getElementById('ma-app');
    var tabs=document.querySelector('.ma-tabs');
    if(!app || !tabs || document.getElementById('mav-docs')) return;

    var s=await sb.auth.getSession();
    if(!s.data || !s.data.session) return;

    /* resolve organization (for the upload path; listing needs no org — RLS scopes it) */
    try{
      var pm=await sb.from('crm_portal_members').select('organization_id')
              .eq('user_id', s.data.session.user.id).limit(1).maybeSingle();
      if(pm.data) orgId=pm.data.organization_id;
    }catch(e){}

    try{
      var c=await sb.from('crm_attachment_categories').select('code,label');
      (c.data||[]).forEach(function(x){ cats[x.code]=x.label; });
    }catch(e){}

    /* tab */
    var tab=el('<span class="ma-tab" data-view="docs">Documents</span>');
    var enqTab=tabs.querySelector('[data-view="enquiry"]');
    tabs.insertBefore(tab, enqTab||null);

    /* section */
    var sec=el(
      '<section id="mav-docs" style="display:none;">'+
      '<div id="pd-list"></div>'+
      '<p class="ma-empty" id="pd-empty" style="display:none;">No documents have been shared with your organization yet.</p>'+
      '<div class="ma-card" style="margin-top:18px;">'+
        '<h3 style="font-size:15px; margin-bottom:6px;">Send us a document</h3>'+
        '<p class="ma-mono" style="margin-bottom:12px; font-size:12px;">PDF, images or office documents · max 10 MB · private to your organization and the Jabran &amp; Co. team. Please do not upload passwords or payment-card details.</p>'+
        '<div style="display:flex; gap:8px; flex-wrap:wrap; align-items:center;">'+
          '<input type="file" id="pd-file" accept=".pdf,.png,.jpg,.jpeg,.webp,.doc,.docx,.xls,.xlsx,.csv,.txt,.ppt,.pptx" style="font-size:13px; color:var(--muted); max-width:240px;">'+
          '<input type="text" id="pd-title" placeholder="Document title" style="padding:9px 10px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:13px; min-width:180px;">'+
          '<select id="pd-cat" style="padding:9px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:13px;">'+
            CLIENT_CATS.map(function(c){return '<option value="'+c[0]+'">'+esc(c[1])+'</option>';}).join('')+
          '</select>'+
          '<button class="ma-btn ghost" id="pd-btn" type="button">Upload</button>'+
        '</div><p class="ma-status" id="pd-status"></p>'+
      '</div></section>');
    var anchor=document.getElementById('mav-enquiry');
    if(anchor) anchor.parentNode.insertBefore(sec, anchor); else app.appendChild(sec);

    /* tab switching — self-contained, plays nicely with the page's own switcher */
    tab.addEventListener('click', function(){
      document.querySelectorAll('.ma-tab').forEach(function(t){ t.classList.remove('active'); });
      tab.classList.add('active');
      document.querySelectorAll('#ma-app section[id^="mav-"]').forEach(function(x){ x.style.display='none'; });
      sec.style.display='';
      refresh();
    });
    tabs.addEventListener('click', function(e){
      var t=e.target.closest('.ma-tab');
      if(t && t!==tab) sec.style.display='none';   /* defensive: hide ours when a native tab is chosen */
    });

    document.getElementById('pd-btn').addEventListener('click', upload);
    refresh();
  }

  async function refresh(){
    var listEl=document.getElementById('pd-list'), empty=document.getElementById('pd-empty');
    if(!listEl) return;
    var r=await sb.from('crm_attachments').select('*')
            .order('created_at',{ascending:false}).limit(200);
    var rows=(r.data||[]).filter(function(a){ return a.is_current_version!==false; });
    empty.style.display=rows.length?'none':'';
    listEl.innerHTML=rows.map(function(a){
      var mine=a.visibility_scope==='client_uploaded';
      var badge=mine
        ? (a.approval_status==='pending'
            ? '<span style="font-size:9px; letter-spacing:0.08em; text-transform:uppercase; border:1px solid #C6A55A; color:#E4C98A; padding:2px 6px; border-radius:2px;">Uploaded by you · under review</span>'
            : '<span style="font-size:9px; letter-spacing:0.08em; text-transform:uppercase; border:1px solid #7fbf7f; color:#7fbf7f; padding:2px 6px; border-radius:2px;">Uploaded by you</span>')
        : '<span style="font-size:9px; letter-spacing:0.08em; text-transform:uppercase; border:1px solid #7fbf7f; color:#7fbf7f; padding:2px 6px; border-radius:2px;">Shared with you</span>';
      return '<div class="ma-card" style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">'+
        '<span style="flex:1; min-width:160px;">'+
          '<span style="display:block; font-size:14px;">'+esc(a.document_title||a.file_name)+'</span>'+
          '<span class="ma-mono" style="font-size:11px; color:var(--muted,#9C9690);">'+
            esc([cats[a.document_category]||a.document_category,(a.created_at||'').slice(0,10),kb(a.size_bytes)].filter(Boolean).join(' · '))+'</span>'+
        '</span>'+badge+
        '<button class="ma-btn sm" type="button" data-view="'+a.id+'" data-path="'+esc(a.file_path)+'">View</button>'+
        '</div>';
    }).join('');
    listEl.querySelectorAll('[data-view]').forEach(function(b){
      b.addEventListener('click', async function(){
        var s=await sb.storage.from('crm-private').createSignedUrl(b.dataset.path,120);
        if(s.data&&s.data.signedUrl){
          try{ sb.from('crm_attachment_events').insert({attachment_id:b.dataset.view,event_type:'signed_link',detail:'portal view'}).then(function(){}); }catch(e){}
          window.open(s.data.signedUrl,'_blank');
        }
      });
    });
  }

  async function upload(){
    var st=document.getElementById('pd-status');
    var f=document.getElementById('pd-file').files[0];
    if(!f){ st.textContent='Choose a file first.'; return; }
    var m=/\.([A-Za-z0-9]+)$/.exec(f.name); var e=m?m[1].toLowerCase():'';
    if(ALLOWED.indexOf(e)===-1){ st.textContent='File type ".'+e+'" is not accepted.'; return; }
    if(f.size>MAX){ st.textContent='Maximum size is 10 MB.'; return; }
    if(!orgId){ st.textContent='Your account is not yet linked to an organization — please contact us on WhatsApp +92 336 4864345.'; return; }
    st.textContent='Uploading…';
    var safe=f.name.replace(/[^A-Za-z0-9._-]+/g,'_').slice(-80);
    var path='attachments/portal/'+orgId+'/'+Date.now()+'_'+safe;
    var up=await sb.storage.from('crm-private').upload(path,f,{contentType:f.type||'application/octet-stream'});
    if(up.error){ st.textContent='Upload error: '+up.error.message; return; }
    var ins=await sb.from('crm_attachments').insert({
      module:'organizations', record_id:orgId, organization_id:orgId,
      file_path:path, file_name:f.name, content_type:f.type||null, size_bytes:f.size,
      document_title:document.getElementById('pd-title').value.trim()||f.name,
      document_category:document.getElementById('pd-cat').value||'other'
    });
    if(ins.error){ st.textContent='Error: '+ins.error.message;
      try{ await sb.storage.from('crm-private').remove([path]); }catch(x){} return; }
    st.textContent='Received — thank you. Our team has been able to see it immediately.';
    document.getElementById('pd-file').value=''; document.getElementById('pd-title').value='';
    refresh();
  }

  document.addEventListener('DOMContentLoaded', function(){ init(); setTimeout(init,1800); });
})();
