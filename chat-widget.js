/* ============================================================================
   JABRAN & CO. — chat-widget.js · ADVISORY AGENT (v2, Increment 7)
   Replaces the previous widget. Include on public pages before </body>:
       <script src="chat-widget.js" defer></script>
   No SDK, no dependencies — one async fetch to the ai-agent Edge Function.
   Features: conversation persistence + resume (reference number shown),
   config-driven behaviour with a server-side kill switch, context-aware
   proactive openers with frequency caps and dismissal persistence,
   reduced-motion respect, analytics events, AI disclosure line.
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined' || window.__jcoWidget) return;
  window.__jcoWidget = true;

  var FN = 'https://dvsaqjvcxqlzgpbvexnu.supabase.co/functions/v1/ai-agent';
  var LS_CONV = 'jco_ai_conv', LS_PRO = 'jco_ai_proactive';
  var cfg = null, conv = null, open = false, busy = false, humanMode = false;
  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  var PROACTIVE = {
    'global-trade-sourcing': 'Are you currently looking for a supplier, comparing quotations, or trying to resolve a sourcing problem?',
    'production-plant-audit': 'Are you investigating production loss, quality variation, downtime, or workforce inefficiency?',
    'custom-clearance': 'Is your shipment being planned, already in transit, or currently facing a customs issue?',
    'training-academy': 'Are you planning training for leadership, sales, operations, AI adoption, or business development?',
    'architecture-interiors': 'Are you planning a new build, a fit-out, or renovating an existing space?',
    'advisory': 'Would it help to talk through the business challenge you are working on?'
  };

  function api(payload){
    return fetch(FN, { method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify(payload) })
      .then(function(r){ return r.json(); });
  }
  function track(ev){
    try{ if(window.gtag) gtag('event', ev, {event_category:'ai_agent'}); }catch(e){}
    try{ if(window.fbq) fbq('trackCustom', ev); }catch(e){}
  }
  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }

  /* ------------------------------------------------------------------ UI */
  var root, panel, msgs, input, launcher, bubble;
  function build(){
    root=document.createElement('div');
    root.innerHTML=
    '<style>'+
    '.jcw-launch{position:fixed;right:20px;bottom:20px;z-index:9990;width:56px;height:56px;border-radius:50%;background:#C6A55A;color:#0B0F14;border:none;cursor:pointer;font-size:22px;box-shadow:0 6px 24px rgba(0,0,0,0.45);display:flex;align-items:center;justify-content:center;}'+
    (reduceMotion?'':'.jcw-launch{transition:transform .2s;}.jcw-launch:hover{transform:scale(1.06);}')+
    '.jcw-bubble{position:fixed;right:88px;bottom:30px;z-index:9990;max-width:270px;background:#111820;border:1px solid rgba(198,165,90,0.4);color:#F5F3EF;font:13px/1.5 Inter,system-ui,sans-serif;padding:12px 14px;border-radius:6px;box-shadow:0 6px 24px rgba(0,0,0,0.45);display:none;}'+
    '.jcw-bubble .x{position:absolute;top:4px;right:8px;color:#9C9690;cursor:pointer;font-size:14px;background:none;border:none;}'+
    '.jcw-panel{position:fixed;right:16px;bottom:88px;z-index:9991;width:min(370px,calc(100vw - 32px));height:min(560px,calc(100vh - 120px));background:#0B0F14;border:1px solid rgba(198,165,90,0.35);border-radius:8px;display:none;flex-direction:column;overflow:hidden;box-shadow:0 14px 44px rgba(0,0,0,0.6);font-family:Inter,system-ui,sans-serif;}'+
    '.jcw-head{background:#08111C;border-bottom:1px solid rgba(198,165,90,0.25);padding:14px 16px 10px;}'+
    '.jcw-head .n{font-family:"Playfair Display",serif;font-size:16px;color:#F5F3EF;}'+
    '.jcw-head .d{font-size:10px;color:#9C9690;margin-top:3px;line-height:1.45;}'+
    '.jcw-head .r{font-family:"IBM Plex Mono",monospace;font-size:9px;letter-spacing:0.08em;color:#C6A55A;margin-top:5px;}'+
    '.jcw-msgs{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:10px;}'+
    '.jcw-m{max-width:86%;padding:9px 12px;border-radius:6px;font-size:13px;line-height:1.55;white-space:pre-wrap;word-wrap:break-word;}'+
    '.jcw-m.a{background:#111820;border:1px solid rgba(198,165,90,0.2);color:#F5F3EF;align-self:flex-start;}'+
    '.jcw-m.v{background:rgba(198,165,90,0.14);border:1px solid rgba(198,165,90,0.3);color:#F5F3EF;align-self:flex-end;}'+
    '.jcw-m.s{background:none;border:none;color:#9C9690;font-size:11px;align-self:center;text-align:center;}'+
    '.jcw-in{display:flex;gap:8px;padding:12px;border-top:1px solid rgba(198,165,90,0.25);background:#08111C;}'+
    '.jcw-in textarea{flex:1;resize:none;background:#111820;border:1px solid rgba(198,165,90,0.25);color:#F5F3EF;border-radius:4px;padding:9px 11px;font:13px Inter,sans-serif;height:42px;}'+
    '.jcw-in button{background:#C6A55A;color:#0B0F14;border:none;border-radius:4px;padding:0 16px;font-size:11px;letter-spacing:0.08em;text-transform:uppercase;cursor:pointer;font-weight:600;}'+
    '.jcw-in button:disabled{opacity:0.5;cursor:default;}'+
    '.jcw-x{position:absolute;top:10px;right:12px;background:none;border:none;color:#9C9690;font-size:18px;cursor:pointer;}'+
    '</style>'+
    '<button class="jcw-launch" aria-label="Chat with the Jabran & Co. Advisory Agent">✦</button>'+
    '<div class="jcw-bubble" role="status"><button class="x" aria-label="Dismiss">×</button><span class="t"></span></div>'+
    '<div class="jcw-panel" role="dialog" aria-label="Jabran and Co Advisory Agent">'+
      '<button class="jcw-x" aria-label="Close chat">×</button>'+
      '<div class="jcw-head"><div class="n"></div><div class="d"></div><div class="r"></div></div>'+
      '<div class="jcw-msgs" aria-live="polite"></div>'+
      '<div class="jcw-in"><textarea rows="1" placeholder="Type your message…" aria-label="Your message"></textarea><button type="button">Send</button></div>'+
    '</div>';
    document.body.appendChild(root);
    launcher=root.querySelector('.jcw-launch'); bubble=root.querySelector('.jcw-bubble');
    panel=root.querySelector('.jcw-panel'); msgs=root.querySelector('.jcw-msgs');
    input=root.querySelector('.jcw-in textarea');
    root.querySelector('.jcw-head .n').textContent=cfg.agent_name;
    root.querySelector('.jcw-head .d').textContent=cfg.disclosure;

    launcher.addEventListener('click', toggle);
    root.querySelector('.jcw-x').addEventListener('click', toggle);
    root.querySelector('.jcw-in button').addEventListener('click', send);
    input.addEventListener('keydown', function(e){
      if(e.key==='Enter'&&!e.shiftKey){ e.preventDefault(); send(); }
    });
    bubble.querySelector('.x').addEventListener('click', function(){
      bubble.style.display='none';
      try{ localStorage.setItem(LS_PRO, JSON.stringify({dismissed:true, at:Date.now()})); }catch(e){}
    });
    bubble.addEventListener('click', function(e){
      if(e.target.classList.contains('x')) return;
      bubble.style.display='none'; if(!open) toggle();
    });
  }

  function add(kind, text){
    var m=document.createElement('div');
    m.className='jcw-m '+kind; m.textContent=text;
    msgs.appendChild(m); msgs.scrollTop=msgs.scrollHeight;
    return m;
  }

  function toggle(){
    open=!open;
    panel.style.display=open?'flex':'none';
    if(open){
      bubble.style.display='none';
      track('chat_opened');
      if(!conv) start(); else if(!msgs.childElementCount) resume();
      setTimeout(function(){ input.focus(); },100);
    } else {
      launcher.focus();
    }
  }

  /* --------------------------------------------------------- conversation */
  function saveConv(){ try{ localStorage.setItem(LS_CONV, JSON.stringify(conv)); }catch(e){} }
  function loadConv(){ try{ conv=JSON.parse(localStorage.getItem(LS_CONV)||'null'); }catch(e){ conv=null; } }

  async function start(){
    add('s','Connecting…');
    var u=new URLSearchParams(location.search);
    var r=await api({ action:'start',
      session_id:(Date.now().toString(36)+Math.random().toString(36).slice(2,8)),
      url:location.href, landing:location.pathname,
      utm_source:u.get('utm_source'), utm_medium:u.get('utm_medium'), utm_campaign:u.get('utm_campaign') });
    msgs.innerHTML='';
    if(!r.conversation_id){ add('s','The assistant is unavailable right now — reach us on WhatsApp +92 336 4864345.'); return; }
    conv={ id:r.conversation_id, token:r.visitor_token, ref:r.reference }; saveConv();
    root.querySelector('.jcw-head .r').textContent='Ref '+conv.ref;
    add('a', cfg.greeting);
  }

  async function resume(){
    add('s','Restoring your conversation…');
    var r=await api({ action:'history', conversation_id:conv.id, visitor_token:conv.token });
    msgs.innerHTML='';
    if(r.error){ conv=null; try{localStorage.removeItem(LS_CONV);}catch(e){} return start(); }
    root.querySelector('.jcw-head .r').textContent='Ref '+(r.reference||conv.ref);
    (r.messages||[]).forEach(function(m){
      add(m.sender_type==='assistant'?'a':(m.sender_type==='staff'?'a':'v'), m.content||'');
    });
    if(r.status==='human_active') humanMode=true;
    if(!r.messages||!r.messages.length) add('a', cfg.greeting);
  }

  async function send(){
    var text=input.value.trim();
    if(!text||busy||!conv) return;
    busy=true; input.value='';
    add('v', text);
    var tip=add('s', humanMode?'Sent to the team.':'…');
    track('chat_message_sent');
    try{
      var r=await api({ action:'message', conversation_id:conv.id, visitor_token:conv.token,
                        content:text, page:document.title+' — '+location.pathname });
      tip.remove();
      if(r.human && !r.reply){ humanMode=true; add('s','A member of the team will reply here — keep this tab open or note your reference '+(conv.ref||'')+'.'); }
      if(r.reply) add('a', r.reply);
      if(r.qualified) track('qualified_lead_created');
      if(r.handoff){ track('human_takeover_requested'); }
      if(r.error==='closed') add('s','This conversation is closed — refresh the page to start a new one.');
    }catch(e){
      tip.remove();
      add('s','Connection problem — please try again, or WhatsApp +92 336 4864345.');
    }
    busy=false;
  }

  /* ------------------------------------------------------------ proactive */
  function proactiveKey(){
    var p=location.pathname.toLowerCase();
    if(p.indexOf('global-trade')>-1||p.indexOf('trading')>-1) return 'global-trade-sourcing';
    if(p.indexOf('plant-audit')>-1||p.indexOf('factory')>-1) return 'production-plant-audit';
    if(p.indexOf('clearance')>-1||p.indexOf('customs')>-1) return 'custom-clearance';
    if(p.indexOf('training')>-1) return 'training-academy';
    if(p.indexOf('architecture')>-1||p.indexOf('construction')>-1||p.indexOf('interior')>-1) return 'architecture-interiors';
    if(p.indexOf('advisory')>-1) return 'advisory';
    return null;
  }
  function armProactive(){
    if(!cfg.proactive||open) return;
    var key=proactiveKey(); if(!key) return;
    var st=null; try{ st=JSON.parse(localStorage.getItem(LS_PRO)||'null'); }catch(e){}
    if(st){
      if(st.dismissed) return;
      if(st.at && (Date.now()-st.at) < cfg.proactive.cap_hours*3600000) return;
    }
    var fired=false;
    function fire(){
      if(fired||open) return;
      var ae=document.activeElement;
      if(ae&&(ae.tagName==='INPUT'||ae.tagName==='TEXTAREA'||ae.tagName==='SELECT')) return; // never interrupt a form
      fired=true;
      bubble.querySelector('.t').textContent=PROACTIVE[key];
      bubble.style.display='block';
      try{ localStorage.setItem(LS_PRO, JSON.stringify({at:Date.now()})); }catch(e){}
      track('proactive_chat_shown');
      setTimeout(function(){ bubble.style.display='none'; }, 25000);
    }
    setTimeout(fire, cfg.proactive.seconds*1000);
    var onScroll=function(){
      var h=document.documentElement;
      var pct=(h.scrollTop+h.clientHeight)/h.scrollHeight*100;
      if(pct>=cfg.proactive.scroll_pct){ fire(); window.removeEventListener('scroll', onScroll); }
    };
    window.addEventListener('scroll', onScroll, {passive:true});
  }

  /* ----------------------------------------------------------------- boot */
  function boot(){
    api({action:'config'}).then(function(c){
      if(!c||!c.enabled) return;         // server-side kill switch
      cfg=c; loadConv(); build();
      if(conv&&conv.ref) root.querySelector('.jcw-head .r').textContent='Ref '+conv.ref;
      armProactive();
    }).catch(function(){});
  }
  if(document.readyState==='complete') setTimeout(boot,800);
  else window.addEventListener('load', function(){ setTimeout(boot,800); });
})();
