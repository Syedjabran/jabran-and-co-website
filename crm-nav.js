/* ============================================================================
   JABRAN & CO. CRM — crm-nav.js · ECOSYSTEM UNIFICATION LAYER (Increment 10)
   Include on EVERY staff CRM page, after supabase-client.js / crm-auth.js:
       <script src="crm-nav.js"></script>
   Does two things, with zero per-page markup:

   1. NAV COMPLETION — inspects the page's existing sidebar and adds any
      missing module links (Conversations, RM Dashboard, and — for
      governance roles only — the Administration group incl. the AI Control
      Center). Links already present are never duplicated. The whole
      ecosystem is reachable from every page; no separate URL to remember.

   2. LIVE ATTENTION BELL — a bell beside the Log Out control on every CRM
      page showing unread notifications + conversations needing a human.
      The dropdown lists the latest notifications and one-tap routes into
      Conversations, the RM Dashboard, or the relevant module. Polls every
      60 seconds; role-safe (RLS decides what each person can count).
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined' || window.__jcoNav) return;
  window.__jcoNav = true;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }

  var CORE = [
    ['crm.html','CRM Dashboard'],
    ['crm-opportunities.html','Opportunities'],
    ['crm-quotations.html','Quotations & Costing'],
    ['crm-orders.html','Orders & Fulfilment'],
    ['crm-finance.html','Finance'],
    ['crm-reports.html','Reports']
  ];
  var ENGAGE = [
    ['crm-conversations.html','Conversations'],
    ['crm-rm-dashboard.html','RM Dashboard']
  ];
  var ADMIN = [
    ['crm-command-center.html','Command Center'],
    ['crm-business-rules.html','Business Rules'],
    ['crm-employees.html','Employees'],
    ['crm-form-builder.html','Form Builder'],
    ['crm-ai-control-center.html','AI Control Center']
  ];

  function here(href){ return location.pathname.replace(/^\//,'')===href; }

  function addLink(side, href, label){
    if (side.querySelector('a[href="'+href+'"]')) return null;      // never duplicate
    if (here(href)) return null;                                     // page marks itself
    var a=document.createElement('a');
    a.className='crm-nav-item'; a.href=href; a.textContent=label;
    a.style.textDecoration='none';
    side.appendChild(a);
    return a;
  }
  function addLabel(side, text){
    var l=document.createElement('div');
    l.className='crm-nav-label'; l.textContent=text;
    side.appendChild(l); return l;
  }

  async function buildNav(){
    var side=document.querySelector('aside.crm-side');
    if(!side) return;

    /* complete the Modules set (some pages predate later modules) */
    CORE.forEach(function(x){ addLink(side, x[0], x[1]); });

    /* Engagement group */
    var needEngage=ENGAGE.some(function(x){ return !side.querySelector('a[href="'+x[0]+'"]') && !here(x[0]); });
    if(needEngage && !side.querySelector('[data-jco-label="engagement"]')){
      addLabel(side,'Engagement').dataset.jcoLabel='engagement';
    }
    ENGAGE.forEach(function(x){ addLink(side, x[0], x[1]); });

    /* Administration group — governance roles only */
    try{
      var r=await sb.rpc('crm_has_role',{roles:['owner','super_admin','ceo']});
      if(r.data===true){
        var needAdmin=ADMIN.some(function(x){ return !side.querySelector('a[href="'+x[0]+'"]') && !here(x[0]); });
        if(needAdmin && !side.querySelector('[data-jco-label="admin"]')){
          addLabel(side,'Administration').dataset.jcoLabel='admin';
        }
        ADMIN.forEach(function(x){ addLink(side, x[0], x[1]); });
      }
    }catch(e){}
  }

  /* ------------------------------------------------------------- the bell */
  var bell, badge, drop, open=false;
  function buildBell(){
    if(document.getElementById('jco-bell')) return;
    var host=document.createElement('div');
    host.innerHTML=
    '<style>'+
    '#jco-bell{position:fixed; top:20px; right:104px; z-index:95; background:none; border:1px solid rgba(198,165,90,0.35); color:#E4C98A; width:34px; height:34px; border-radius:50%; cursor:pointer; font-size:15px; line-height:1;}'+
    '#jco-bell .b{position:absolute; top:-6px; right:-6px; background:#C6A55A; color:#0B0F14; font:600 10px "IBM Plex Mono",monospace; min-width:17px; height:17px; border-radius:9px; display:none; align-items:center; justify-content:center; padding:0 3px;}'+
    '#jco-bell .b.hot{background:#e57368; color:#fff;}'+
    '#jco-drop{position:fixed; top:60px; right:24px; z-index:96; width:min(340px,calc(100vw - 32px)); background:#0B0F14; border:1px solid rgba(198,165,90,0.35); border-radius:6px; box-shadow:0 14px 44px rgba(0,0,0,0.6); display:none; font-family:Inter,sans-serif;}'+
    '#jco-drop .h{padding:12px 14px; border-bottom:1px solid rgba(198,165,90,0.22); display:flex; justify-content:space-between; align-items:center;}'+
    '#jco-drop .h span{font:10px "IBM Plex Mono",monospace; letter-spacing:0.18em; text-transform:uppercase; color:#C6A55A;}'+
    '#jco-drop .h button{background:none; border:none; color:#9C9690; font-size:11px; cursor:pointer;}'+
    '#jco-drop .conv{display:block; padding:10px 14px; border-bottom:1px solid rgba(198,165,90,0.22); font-size:12px; color:#E4C98A; text-decoration:none;}'+
    '#jco-drop .conv.hot{color:#e57368;}'+
    '#jco-drop .list{max-height:300px; overflow-y:auto;}'+
    '#jco-drop .n{padding:9px 14px; border-bottom:1px solid rgba(198,165,90,0.1); cursor:pointer;}'+
    '#jco-drop .n.unread{border-left:2px solid #C6A55A;}'+
    '#jco-drop .n .t{font-size:12px; color:#F5F3EF;}'+
    '#jco-drop .n .d{font-size:11px; color:#9C9690;}'+
    '#jco-drop .empty{padding:16px 14px; font-size:12px; color:#9C9690;}'+
    '@media (max-width:820px){ #jco-bell{top:14px; right:86px;} #jco-drop{top:52px; right:12px;} }'+
    '</style>'+
    '<button id="jco-bell" aria-label="Notifications">🔔<span class="b"></span></button>'+
    '<div id="jco-drop"><div class="h"><span>Notifications</span><button type="button" id="jco-readall">Mark all read</button></div>'+
    '<a class="conv" id="jco-conv-link" href="crm-conversations.html"></a>'+
    '<div class="list" id="jco-nlist"></div></div>';
    document.body.appendChild(host);
    bell=document.getElementById('jco-bell');
    badge=bell.querySelector('.b');
    drop=document.getElementById('jco-drop');
    bell.addEventListener('click', function(){ open=!open; drop.style.display=open?'block':'none'; if(open) refresh(); });
    document.addEventListener('click', function(e){
      if(open && !drop.contains(e.target) && e.target!==bell && !bell.contains(e.target)){
        open=false; drop.style.display='none'; }
    });
    document.getElementById('jco-readall').addEventListener('click', async function(){
      try{ await sb.from('crm_notifications').update({read_at:new Date().toISOString()}).is('read_at',null); }catch(e){}
      refresh();
    });
  }

  async function refresh(){
    if(!bell) return;
    var unread=0, human=0;
    try{
      var n=await sb.from('crm_notifications').select('id',{count:'exact',head:true}).is('read_at',null);
      unread=n.count||0;
    }catch(e){}
    try{
      var h=await sb.from('ai_conversations').select('id',{count:'exact',head:true}).eq('status','human_requested');
      human=h.count||0;
    }catch(e){}
    var total=unread+human;
    badge.style.display=total>0?'flex':'none';
    badge.textContent=total>99?'99+':String(total);
    badge.className='b'+(human>0?' hot':'');
    var cl=document.getElementById('jco-conv-link');
    if(cl){
      cl.textContent=human>0?('⚠ '+human+' conversation'+(human>1?'s':'')+' need a human — open Conversations'):'Open Conversations';
      cl.className='conv'+(human>0?' hot':'');
    }
    if(!open) return;
    try{
      var r=await sb.from('crm_notifications').select('*').order('created_at',{ascending:false}).limit(8);
      var rows=r.data||[];
      document.getElementById('jco-nlist').innerHTML=rows.length?rows.map(function(x){
        return '<div class="n'+(x.read_at?'':' unread')+'" data-link="'+esc(x.link||'')+'" data-id="'+x.id+'">'+
          '<div class="t">'+esc(x.title)+'</div>'+
          (x.body?'<div class="d">'+esc(x.body)+'</div>':'')+'</div>';
      }).join(''):'<div class="empty">No notifications.</div>';
      document.getElementById('jco-nlist').querySelectorAll('.n').forEach(function(el){
        el.addEventListener('click', async function(){
          try{ await sb.from('crm_notifications').update({read_at:new Date().toISOString()}).eq('id',el.dataset.id); }catch(e){}
          if(el.dataset.link) location.href=el.dataset.link;
        });
      });
    }catch(e){}
  }

  async function boot(){
    if(typeof sb==='undefined') return;
    var s=await sb.auth.getSession();
    if(!s.data || !s.data.session){ setTimeout(boot, 4000); return; }
    try{
      var g=await sb.rpc('crm_is_staff');
      if(g.data!==true) return;                       // clients never see any of this
    }catch(e){ return; }
    buildNav();
    buildBell();
    refresh();
    setInterval(refresh, 60000);
  }
  document.addEventListener('DOMContentLoaded', function(){ setTimeout(boot, 900); });
})();
