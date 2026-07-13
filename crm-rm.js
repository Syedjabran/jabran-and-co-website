/* ============================================================================
   JABRAN & CO. CRM — crm-rm.js · RELATIONSHIP MANAGER PANEL
   Requires: migration 019 · supabase-client.js
   Include on crm-orders.html (after crm-extras.js / crm-attachments.js):
       <script src="crm-rm.js"></script>
   Injects a Relationship Manager section into the order modal: current RM,
   full assignment history, and an Assign / Reassign flow — eligible staff
   with live workload badges, over-threshold warning, mandatory reason,
   handover notes — via the crm_reassign_rm() RPC. Orders without an RM
   show a hold warning (the database blocks progression regardless).
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined') return;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }
  function el(h){ var d=document.createElement('div'); d.innerHTML=h.trim(); return d.firstChild; }

  var roster=null, names={};
  async function loadRoster(){
    var r=await sb.rpc('crm_eligible_rms');
    roster=r.data||[];
    roster.forEach(function(x){ names[x.user_id]=x.full_name; });
    return roster;
  }
  async function nameOf(uid){
    if(!uid) return null;
    if(names[uid]) return names[uid];
    if(!roster) await loadRoster();
    return names[uid]||'Staff member';
  }

  async function render(form){
    var mk=form.querySelector('.jco-custom');
    if(!mk || mk.dataset.module!=='orders') return;
    var idf=document.getElementById(mk.dataset.idfield||'or-id');
    var rid=idf?String(idf.value||'').trim():'';

    var host=form.querySelector('.jrm-host');
    if(!host){
      host=el('<div class="jrm-host" style="margin-top:18px; border-top:1px solid rgba(198,165,90,0.22); padding-top:14px;"></div>');
      var anchor=form.querySelector('.jco-extras-host');
      if(anchor) form.insertBefore(host, anchor); else form.appendChild(host);
    }
    host.innerHTML='<div style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; letter-spacing:0.2em; text-transform:uppercase; color:var(--gold,#C6A55A); margin-bottom:8px;">Relationship Manager — accountable client owner</div>'+
      '<div class="jrm-body" style="font-size:13px; color:var(--muted,#9C9690);">Loading…</div>';
    var body=host.querySelector('.jrm-body');

    if(!rid){ body.textContent='Save the order first, then assign the Relationship Manager.'; return; }

    if(!roster) try{ await loadRoster(); }catch(e){ roster=[]; }

    var o=await sb.from('crm_orders').select('id,relationship_manager_id,rm_exempt,status').eq('id',rid).maybeSingle();
    if(!o.data){ body.textContent='Could not load the order.'; return; }
    var cur=o.data.relationship_manager_id;
    var curName=cur?await nameOf(cur):null;

    var hist=await sb.from('crm_record_assignments').select('*')
      .eq('entity_type','orders').eq('entity_id',rid)
      .eq('assignment_type','relationship_manager')
      .order('effective_from',{ascending:false}).limit(10);

    var histHtml=(hist.data||[]).map(function(a){
      return '<div style="font-size:12px; padding:4px 0; border-bottom:1px solid rgba(198,165,90,0.08);">'+
        '<span style="color:var(--cream,#F5F3EF);">'+esc(names[a.user_id]||'Staff member')+'</span>'+
        '<span style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; color:var(--muted,#9C9690);"> · '+
        esc((a.effective_from||'').slice(0,10))+(a.effective_to?' → '+esc((a.effective_to||'').slice(0,10)):' → current')+
        (a.assignment_reason?' · '+esc(a.assignment_reason):'')+'</span>'+
        (a.handover_notes?'<div style="font-size:11px; color:var(--muted,#9C9690); padding-left:10px;">Handover: '+esc(a.handover_notes)+'</div>':'')+
        '</div>';
    }).join('');

    body.innerHTML=
      (cur
        ? '<div style="margin-bottom:10px;"><span style="color:var(--gold-light,#E4C98A); font-size:14px;">'+esc(curName)+'</span>'+
          ' <span style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; color:#5cc9b4; border:1px solid var(--emerald,#0F6B5C); padding:2px 7px; border-radius:2px; margin-left:6px;">ASSIGNED</span></div>'
        : '<div style="margin-bottom:10px; color:#e08a4a;">⚠ No Relationship Manager assigned — this order cannot progress until one is set'+(o.data.rm_exempt?' (Owner exception active)':'')+'.</div>')+
      '<button type="button" class="jrm-open" style="background:transparent; border:1px solid rgba(198,165,90,0.4); color:var(--gold-light,#E4C98A); padding:7px 12px; font-size:10px; letter-spacing:0.08em; text-transform:uppercase; cursor:pointer; border-radius:2px;">'+(cur?'Reassign':'Assign Relationship Manager')+'</button>'+
      '<div class="jrm-form" style="display:none; margin-top:12px; border:1px solid rgba(198,165,90,0.22); padding:14px; background:var(--bg-deep,#08111C);">'+
        '<label style="display:block; font-size:11px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted,#9C9690); margin-bottom:5px;">New Relationship Manager *</label>'+
        '<select class="jrm-who" style="width:100%; padding:9px 10px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; margin-bottom:4px;">'+
          '<option value="">— select —</option>'+
          roster.map(function(x){ return '<option value="'+x.user_id+'">'+esc(x.full_name)+' · '+x.active_orders+' active'+(x.over_threshold?' ⚠':'')+'</option>'; }).join('')+
        '</select>'+
        '<div class="jrm-warn" style="font-size:11px; color:#e08a4a; margin-bottom:8px;"></div>'+
        '<label style="display:block; font-size:11px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted,#9C9690); margin-bottom:5px;">Reason *</label>'+
        '<input class="jrm-reason" placeholder="e.g. New order intake / workload balancing" style="width:100%; padding:9px 10px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; margin-bottom:10px;">'+
        '<label style="display:block; font-size:11px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted,#9C9690); margin-bottom:5px;">Handover notes (open tasks, pending client items)</label>'+
        '<textarea class="jrm-hand" style="width:100%; min-height:60px; padding:9px 10px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; margin-bottom:10px; resize:vertical;"></textarea>'+
        '<button type="button" class="jrm-save" style="background:var(--gold,#C6A55A); color:#0a0a0b; border:none; padding:9px 18px; font-size:11px; letter-spacing:0.08em; text-transform:uppercase; cursor:pointer; border-radius:2px;">Confirm Assignment</button>'+
        '<span class="jrm-status" style="font-size:12px; color:var(--gold-light,#E4C98A); margin-left:10px;"></span>'+
      '</div>'+
      (histHtml?'<div style="margin-top:14px;"><div style="font-family:\'IBM Plex Mono\',monospace; font-size:9px; letter-spacing:0.16em; text-transform:uppercase; color:var(--muted,#9C9690); margin-bottom:4px;">Assignment history</div>'+histHtml+'</div>':'');

    var panel=body.querySelector('.jrm-form'), who=body.querySelector('.jrm-who'),
        warn=body.querySelector('.jrm-warn'), st=body.querySelector('.jrm-status');
    body.querySelector('.jrm-open').addEventListener('click', function(){
      panel.style.display=panel.style.display==='none'?'block':'none';
    });
    who.addEventListener('change', function(){
      var x=roster.find(function(r){return r.user_id===who.value;});
      warn.textContent=(x&&x.over_threshold)?'This person already carries '+x.active_orders+' active orders — above the configured threshold. The Owner may still confirm with a reason.':'';
    });
    body.querySelector('.jrm-save').addEventListener('click', async function(){
      if(!who.value){ st.textContent='Select the new RM.'; return; }
      var reason=body.querySelector('.jrm-reason').value.trim();
      if(!reason){ st.textContent='A reason is required.'; return; }
      st.textContent='Saving…';
      var r=await sb.rpc('crm_reassign_rm',{
        p_order_id:rid, p_new_rm:who.value, p_reason:reason,
        p_handover:body.querySelector('.jrm-hand').value.trim()||null
      });
      if(r.error){ st.textContent='Error: '+r.error.message; return; }
      st.textContent='Assigned.';
      render(form);
    });
  }

  function watch(){
    if(typeof sb==='undefined') return;
    document.querySelectorAll('.crm-modal-bg').forEach(function(m){
      if(m._jrmWatched) return; m._jrmWatched=true;
      new MutationObserver(function(){
        var visible=m.style.display&&m.style.display!=='none';
        if(!visible) return;
        var form=m.querySelector('form#order-form'); if(!form) return;
        setTimeout(function(){ render(form).catch(function(){}); },450);
      }).observe(m,{attributes:true,attributeFilter:['style','class']});
    });
  }
  document.addEventListener('DOMContentLoaded', function(){ watch(); setTimeout(watch,1500); });
})();
