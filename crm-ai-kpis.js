/* ============================================================================
   JABRAN & CO. CRM — crm-ai-kpis.js · COMMAND CENTER INTELLIGENCE CARDS
   Requires: migration 024 · supabase-client.js
   Include on crm-command-center.html only:
       <script src="crm-ai-kpis.js"></script>
   Appends two Owner cards to the existing Command Center with zero markup
   changes: (1) AI & Conversation KPIs — funnel, takeover/containment rates,
   token spend; (2) Content & Search Intelligence — what visitors ask,
   where they land, why they escalate. Advisory only: nothing is ever
   auto-published from these signals.
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined') return;
  if (location.pathname.indexOf('crm-command-center') === -1) return;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }

  function card(title, sub){
    var c=document.createElement('div');
    c.style.cssText='border:1px solid rgba(198,165,90,0.22); background:var(--bg-alt,#111820); padding:22px 24px; margin-top:16px;';
    c.innerHTML='<h3 style="font-family:\'Playfair Display\',serif; font-size:16px; margin-bottom:2px;">'+esc(title)+'</h3>'+
      '<p style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; letter-spacing:0.08em; color:var(--muted,#9C9690); margin-bottom:14px;">'+esc(sub)+'</p>'+
      '<div class="body"></div>';
    return c;
  }
  function chip(label, value, hot){
    return '<div style="border:1px solid rgba(198,165,90,0.22); background:var(--bg-deep,#08111C); padding:12px 14px;">'+
      '<div style="font-family:\'Playfair Display\',serif; font-size:20px; color:'+(hot?'#e08a4a':'var(--gold-light,#E4C98A)')+';">'+esc(String(value==null?'—':value))+'</div>'+
      '<div style="font-size:9px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted,#9C9690); margin-top:3px;">'+esc(label)+'</div></div>';
  }
  function listBlock(title, rows, keyA, keyB){
    return '<div style="min-width:200px; flex:1;">'+
      '<div style="font-family:\'IBM Plex Mono\',monospace; font-size:9px; letter-spacing:0.16em; text-transform:uppercase; color:var(--gold,#C6A55A); margin-bottom:6px;">'+esc(title)+'</div>'+
      ((rows&&rows.length)?rows.map(function(r){
        return '<div style="display:flex; gap:8px; font-size:12px; padding:3px 0; border-bottom:1px solid rgba(198,165,90,0.08);">'+
          '<span style="flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; color:var(--cream,#F5F3EF);">'+esc(r[keyA])+'</span>'+
          '<span style="font-family:\'IBM Plex Mono\',monospace; color:var(--gold-light,#E4C98A);">'+esc(String(r[keyB]))+'</span></div>';
      }).join(''):'<div style="font-size:12px; color:var(--muted,#9C9690);">No data yet.</div>')+
      '</div>';
  }

  async function render(){
    var main=document.querySelector('main.crm-main');
    var shell=document.getElementById('crm-shell');
    if(!main || !shell || shell.style.display==='none'){ setTimeout(render, 2500); return; }
    if(document.getElementById('jco-ai-cards')) return;

    var wrap=document.createElement('div'); wrap.id='jco-ai-cards';
    main.appendChild(wrap);

    var intel=null;
    try{
      var r=await sb.rpc('ai_content_intelligence',{p_days:30});
      if(r.error) throw r.error;
      intel=r.data;
    }catch(e){
      wrap.innerHTML='<p style="font-family:\'IBM Plex Mono\',monospace; font-size:11px; color:var(--muted,#9C9690); margin-top:16px;">AI intelligence unavailable — run migration 024 (Owner access required).</p>';
      return;
    }

    /* token spend this month */
    var monthTokens=0;
    try{
      var m0=new Date(); m0.setDate(1); m0.setHours(0,0,0,0);
      var u=await sb.from('ai_usage_log').select('token_usage').gte('created_at',m0.toISOString()).limit(5000);
      (u.data||[]).forEach(function(x){ monthTokens+=x.token_usage||0; });
    }catch(e){}

    var t=intel.totals||{}, ht=intel.human_takeover||{};
    var c1=card('AI & Conversation KPIs','Last 30 days · live from the conversation architecture');
    c1.querySelector('.body').innerHTML=
      '<div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(130px,1fr)); gap:10px;">'+
      chip('Conversations', t.conversations)+
      chip('Website visitors', t.public)+
      chip('Client sessions', t.client)+
      chip('Contact captured', t.with_contact)+
      chip('CRM enquiries created', t.enquiries_created)+
      chip('Human takeover rate', (ht.takeover_rate_pct!=null?ht.takeover_rate_pct+'%':'—'), (ht.takeover_rate_pct||0)>40)+
      chip('AI containment', (intel.containment_rate_pct!=null?intel.containment_rate_pct+'%':'—'))+
      chip('Avg visitor messages', intel.avg_visitor_messages)+
      chip('Tokens this month', monthTokens.toLocaleString())+
      '</div>';
    wrap.appendChild(c1);

    var c2=card('Content & Search Intelligence','Anonymised demand signals — recommendations for FAQs, insights and landing pages. Review before publishing; nothing is automated.');
    c2.querySelector('.body').innerHTML=
      '<div style="display:flex; gap:22px; flex-wrap:wrap;">'+
      listBlock('Service interest', intel.top_service_interest, 'service', 'n')+
      listBlock('Landing pages driving chats', intel.top_landing_pages, 'page', 'n')+
      listBlock('Why visitors escalate', intel.handoff_reasons, 'reason', 'n')+
      '</div>'+
      ((intel.recent_needs&&intel.recent_needs.length)?
        '<div style="margin-top:16px;"><div style="font-family:\'IBM Plex Mono\',monospace; font-size:9px; letter-spacing:0.16em; text-transform:uppercase; color:var(--gold,#C6A55A); margin-bottom:6px;">Recent visitor needs — FAQ & insight candidates</div>'+
        intel.recent_needs.map(function(n){
          return '<div style="font-size:12px; color:var(--cream,#F5F3EF); padding:4px 0 4px 10px; border-left:2px solid rgba(198,165,90,0.35); margin-bottom:4px;">'+esc(n)+'</div>';
        }).join('')+'</div>':'');
    wrap.appendChild(c2);
  }

  document.addEventListener('DOMContentLoaded', function(){
    if(typeof sb==='undefined') return;
    setTimeout(render, 1800);
  });
})();
