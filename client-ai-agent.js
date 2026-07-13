/* ============================================================================
   JABRAN & CO. — client-ai-agent.js · J&CO CLIENT SERVICE AGENT (portal)
   Requires: migration 023 · ai-client-agent Edge Function · supabase-client.js
   Include on my-account.html (after portal-tracking.js):
       <script src="client-ai-agent.js"></script>
   Renders a Client Service Agent launcher inside the logged-in portal only.
   Every request carries the client's own Supabase JWT — the Edge Function
   validates it and grounds every answer in ai_client_snapshot(), the
   client's authorised data and nothing else. Polls for staff replies
   during human takeover, same as the public widget.
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined' || window.__jcoClientAgent) return;
  window.__jcoClientAgent = true;

  var FN = 'https://dvsaqjvcxqlzgpbvexnu.supabase.co/functions/v1/ai-client-agent';
  var open=false, busy=false, humanMode=false, lastCount=0, pollTimer=null, built=false;
  var root, panel, msgs, input, launcher;

  var QUICK = [
    ['Order status', 'What is the current status of my orders?'],
    ['Invoices due', 'Do I have any invoices due or outstanding?'],
    ['My documents', 'What documents have been shared with me recently?'],
    ['Callback',     'Please arrange a callback from my Relationship Manager.']
  ];

  async function token(){
    try{ var r=await sb.auth.getSession(); return r.data&&r.data.session?r.data.session.access_token:null; }
    catch(e){ return null; }
  }
  async function api(payload){
    var t=await token(); if(!t) throw new Error('no session');
    var r=await fetch(FN,{ method:'POST',
      headers:{ 'content-type':'application/json', 'authorization':'Bearer '+t },
      body:JSON.stringify(payload) });
    return r.json();
  }

  function build(){
    if(built) return; built=true;
    root=document.createElement('div');
    root.innerHTML=
    '<style>'+
    '.jca-launch{position:fixed;right:20px;bottom:20px;z-index:9990;height:48px;border-radius:24px;background:#0F6B5C;color:#F5F3EF;border:1px solid rgba(198,165,90,0.4);cursor:pointer;font:12px Inter,sans-serif;letter-spacing:0.06em;padding:0 18px;box-shadow:0 6px 24px rgba(0,0,0,0.45);}'+
    '.jca-panel{position:fixed;right:16px;bottom:80px;z-index:9991;width:min(370px,calc(100vw - 32px));height:min(540px,calc(100vh - 110px));background:#0B0F14;border:1px solid rgba(198,165,90,0.35);border-radius:8px;display:none;flex-direction:column;overflow:hidden;box-shadow:0 14px 44px rgba(0,0,0,0.6);font-family:Inter,system-ui,sans-serif;}'+
    '.jca-head{background:#08111C;border-bottom:1px solid rgba(198,165,90,0.25);padding:13px 16px 10px;position:relative;}'+
    '.jca-head .n{font-family:"Playfair Display",serif;font-size:15px;color:#F5F3EF;}'+
    '.jca-head .d{font-size:10px;color:#9C9690;margin-top:2px;}'+
    '.jca-head .r{font-family:"IBM Plex Mono",monospace;font-size:9px;letter-spacing:0.08em;color:#C6A55A;margin-top:4px;}'+
    '.jca-x{position:absolute;top:8px;right:12px;background:none;border:none;color:#9C9690;font-size:18px;cursor:pointer;}'+
    '.jca-quick{display:flex;gap:6px;flex-wrap:wrap;padding:10px 12px 0;}'+
    '.jca-quick button{background:none;border:1px solid rgba(198,165,90,0.35);color:#E4C98A;font-size:10px;letter-spacing:0.05em;padding:5px 10px;border-radius:12px;cursor:pointer;}'+
    '.jca-msgs{flex:1;overflow-y:auto;padding:12px;display:flex;flex-direction:column;gap:9px;}'+
    '.jca-m{max-width:86%;padding:9px 12px;border-radius:6px;font-size:13px;line-height:1.55;white-space:pre-wrap;word-wrap:break-word;}'+
    '.jca-m.a{background:#111820;border:1px solid rgba(198,165,90,0.2);color:#F5F3EF;align-self:flex-start;}'+
    '.jca-m.v{background:rgba(15,107,92,0.18);border:1px solid #0F6B5C;color:#F5F3EF;align-self:flex-end;}'+
    '.jca-m.s{background:none;border:none;color:#9C9690;font-size:11px;align-self:center;text-align:center;}'+
    '.jca-in{display:flex;gap:8px;padding:11px;border-top:1px solid rgba(198,165,90,0.25);background:#08111C;}'+
    '.jca-in textarea{flex:1;resize:none;background:#111820;border:1px solid rgba(198,165,90,0.25);color:#F5F3EF;border-radius:4px;padding:9px 11px;font:13px Inter,sans-serif;height:40px;}'+
    '.jca-in button{background:#C6A55A;color:#0B0F14;border:none;border-radius:4px;padding:0 15px;font-size:11px;letter-spacing:0.08em;text-transform:uppercase;cursor:pointer;font-weight:600;}'+
    '</style>'+
    '<button class="jca-launch">✦ Client Service Agent</button>'+
    '<div class="jca-panel" role="dialog" aria-label="Client Service Agent">'+
      '<div class="jca-head"><button class="jca-x" aria-label="Close">×</button>'+
        '<div class="n">J&amp;Co Client Service Agent</div>'+
        '<div class="d">AI assistant · answers from your account data only · no passwords or card details please</div>'+
        '<div class="r"></div></div>'+
      '<div class="jca-quick"></div>'+
      '<div class="jca-msgs" aria-live="polite"></div>'+
      '<div class="jca-in"><textarea rows="1" placeholder="Ask about your orders, invoices, documents…" aria-label="Your message"></textarea><button type="button">Send</button></div>'+
    '</div>';
    document.body.appendChild(root);
    launcher=root.querySelector('.jca-launch'); panel=root.querySelector('.jca-panel');
    msgs=root.querySelector('.jca-msgs'); input=root.querySelector('.jca-in textarea');
    var quick=root.querySelector('.jca-quick');
    QUICK.forEach(function(q){
      var b=document.createElement('button'); b.type='button'; b.textContent=q[0];
      b.addEventListener('click', function(){ input.value=q[1]; send(); });
      quick.appendChild(b);
    });
    launcher.addEventListener('click', toggle);
    root.querySelector('.jca-x').addEventListener('click', toggle);
    root.querySelector('.jca-in button').addEventListener('click', send);
    input.addEventListener('keydown', function(e){
      if(e.key==='Enter'&&!e.shiftKey){ e.preventDefault(); send(); } });
  }

  function add(kind,text){
    var m=document.createElement('div'); m.className='jca-m '+kind; m.textContent=text;
    msgs.appendChild(m); msgs.scrollTop=msgs.scrollHeight; return m;
  }

  function toggle(){
    open=!open; panel.style.display=open?'flex':'none';
    launcher.style.display=open?'none':'block';
    if(open){
      if(!msgs.childElementCount) resume();
      if(!pollTimer) pollTimer=setInterval(poll, 9000);
      setTimeout(function(){ input.focus(); },100);
    } else if(pollTimer){ clearInterval(pollTimer); pollTimer=null; }
  }

  async function resume(){
    add('s','Loading your conversation…');
    try{
      var r=await api({action:'history'});
      msgs.innerHTML='';
      if(r.error){ add('s','The assistant is unavailable — WhatsApp +92 336 4864345.'); return; }
      root.querySelector('.jca-head .r').textContent='Ref '+(r.reference||'');
      (r.messages||[]).forEach(function(m){
        add(m.sender_type==='client'?'v':'a', m.content||'');
      });
      lastCount=(r.messages||[]).length;
      if(r.status==='human_active') humanMode=true;
      if(!lastCount) add('a','Hello — I\'m the J&Co Client Service Agent. I can check your order status and milestones, invoices, shared documents, or arrange contact with your Relationship Manager. What would you like to know?');
    }catch(e){ msgs.innerHTML=''; add('s','Please log in to use the Client Service Agent.'); }
  }

  async function poll(){
    if(!open||busy) return;
    try{
      var r=await api({action:'history'});
      if(r.error) return;
      if(r.status==='human_active'&&!humanMode){ humanMode=true; add('s','A member of the Jabran & Co. team has joined this conversation.'); }
      if(r.status==='ai_active'&&humanMode) humanMode=false;
      var m=r.messages||[];
      if(m.length>lastCount){
        m.slice(lastCount).forEach(function(x){ if(x.sender_type!=='client') add('a', x.content||''); });
        lastCount=m.length;
      } else if(m.length){ lastCount=m.length; }
    }catch(e){}
  }

  async function send(){
    var text=input.value.trim(); if(!text||busy) return;
    busy=true; input.value=''; add('v', text); lastCount+=1;
    var tip=add('s', humanMode?'Sent to the team.':'…');
    try{
      var r=await api({action:'message', content:text});
      tip.remove();
      if(r.reply){ add('a', r.reply); lastCount+=1; }
      if(r.human&&!r.reply) add('s','Your Relationship Manager will reply here.');
      if(r.reference) root.querySelector('.jca-head .r').textContent='Ref '+r.reference;
    }catch(e){ tip.remove(); add('s','Connection problem — please try again.'); }
    busy=false;
  }

  /* only inside the logged-in portal — and never beside the public widget */
  async function boot(){
    if(typeof sb==='undefined') return;
    var app=document.getElementById('ma-app');
    var s=await sb.auth.getSession();
    if(app && app.style.display!=='none' && s.data && s.data.session){ build(); return; }
    setTimeout(boot, 2500);
  }
  document.addEventListener('DOMContentLoaded', function(){ setTimeout(boot,1200); });
})();
