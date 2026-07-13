/* ============================================================================
   JABRAN & CO. — portal-tracking.js · CLIENT ORDER MILESTONE TRACKER
   Requires: migration 020 · supabase-client.js
   Include on my-account.html (after portal-documents.js):
       <script src="portal-tracking.js"></script>
   Adds a "View Milestone Plan" control to every order card in the portal.
   Data comes exclusively from crm_client_tracking() — the server returns
   only client-visible milestones and safe fields; the page filters nothing.
   The existing 8-stage journey strip is untouched; this adds the detail.
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined') return;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }

  function timeline(data){
    var ms=data.milestones||[];
    if(!ms.length) return '<p style="font-size:13px; color:var(--muted,#9C9690);">The detailed plan for this order is being prepared.</p>';
    var prog=Math.round(Number(data.progress||0));
    var head='<div style="display:flex; align-items:center; gap:10px; margin-bottom:14px; flex-wrap:wrap;">'+
      '<div style="flex:1; min-width:120px; height:7px; background:var(--bg-deep,#08111C); border:1px solid rgba(198,165,90,0.25); border-radius:2px; overflow:hidden;">'+
        '<div style="width:'+prog+'%; height:100%; background:linear-gradient(90deg,#C6A55A,#E4C98A);"></div></div>'+
      '<span style="font-family:\'IBM Plex Mono\',monospace; font-size:12px; color:var(--gold-light,#E4C98A);">'+prog+'% complete</span>'+
      (data.expected_completion?'<span style="font-family:\'IBM Plex Mono\',monospace; font-size:11px; color:var(--muted,#9C9690);">Expected completion '+esc(data.expected_completion)+'</span>':'')+
      '</div>'+
      (data.is_delayed?'<p style="font-size:12px; color:#e08a4a; margin:0 0 12px;">Part of this order is running behind the original plan — your Relationship Manager is on it and the dates above reflect the latest position.</p>':'');
    var body=ms.map(function(m){
      var done=m.status==='completed'||m.status==='skipped';
      var active=m.status==='in_progress';
      var dot=done
        ? '<span style="display:inline-block; width:11px; height:11px; border-radius:50%; background:#C6A55A; flex-shrink:0;"></span>'
        : active
        ? '<span style="display:inline-block; width:11px; height:11px; border-radius:50%; border:2px solid #E4C98A; flex-shrink:0;"></span>'
        : '<span style="display:inline-block; width:11px; height:11px; border-radius:50%; border:1px solid rgba(198,165,90,0.35); flex-shrink:0;"></span>';
      return '<div style="display:flex; gap:12px; padding:6px 0;">'+
        '<div style="display:flex; flex-direction:column; align-items:center;">'+dot+
          '<span style="flex:1; width:1px; background:rgba(198,165,90,0.2); margin-top:3px;"></span></div>'+
        '<div style="padding-bottom:8px; min-width:0;">'+
          '<div style="font-size:13px; color:'+(done?'var(--muted,#9C9690)':(active?'var(--gold-light,#E4C98A)':'var(--cream,#F5F3EF)'))+';">'+esc(m.label)+
            (active?' <span style="font-family:\'IBM Plex Mono\',monospace; font-size:9px; letter-spacing:0.08em; color:#E4C98A;">CURRENT</span>':'')+'</div>'+
          '<div style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; color:var(--muted,#9C9690);">'+
            esc(done&&m.completed_at?('Completed '+String(m.completed_at).slice(0,10)):(m.due?('Planned '+m.due):''))+'</div>'+
          (m.update?'<div style="font-size:12px; color:var(--cream,#F5F3EF); background:rgba(198,165,90,0.06); border-left:2px solid #C6A55A; padding:6px 10px; margin-top:5px;">'+esc(m.update)+'</div>':'')+
        '</div></div>';
    }).join('');
    return head+'<div>'+body+'</div>';
  }

  async function enhance(){
    if (typeof sb === 'undefined') return;
    document.querySelectorAll('[id^="ma-ord-tl-"]').forEach(function(tl){
      var card=tl.closest('.ma-card'); if(!card || card._jptDone) return;
      card._jptDone=true;
      var oid=tl.id.replace('ma-ord-tl-','');
      var box=document.createElement('div');
      box.innerHTML='<button type="button" class="ma-btn sm" style="margin-top:12px;">View Milestone Plan</button>'+
                    '<div class="jpt-body" style="display:none; margin-top:12px; border-top:1px solid rgba(198,165,90,0.18); padding-top:12px;"></div>';
      tl.parentNode.insertBefore(box, tl);
      var btn=box.querySelector('button'), bd=box.querySelector('.jpt-body'), loaded=false;
      btn.addEventListener('click', async function(){
        if(bd.style.display==='none'){
          bd.style.display='block'; btn.textContent='Hide Milestone Plan';
          if(!loaded){
            bd.innerHTML='<p style="font-size:12px; color:var(--muted,#9C9690);">Loading…</p>';
            var r=await sb.rpc('crm_client_tracking',{p_order_id:oid});
            bd.innerHTML=r.error
              ? '<p style="font-size:12px; color:var(--muted,#9C9690);">The milestone plan is not available yet.</p>'
              : timeline(r.data||{});
            loaded=true;
          }
        } else { bd.style.display='none'; btn.textContent='View Milestone Plan'; }
      });
    });
  }

  document.addEventListener('DOMContentLoaded', function(){
    var list=document.getElementById('ma-orders-list');
    if(list) new MutationObserver(function(){ enhance(); }).observe(list,{childList:true,subtree:true});
    enhance(); setTimeout(enhance,2000);
  });
})();
