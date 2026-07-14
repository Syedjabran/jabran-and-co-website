/* ============================================================================
   JABRAN & CO. — chat-widget.js · PUBLIC AI ADVISORY WIDGET
   Self-contained floating chat for public pages. Loaded automatically by
   animations.js — no page edits. Never appears on CRM/portal pages.
   Backend: the advisory-agent Edge Function (verified-facts-only, capped).
   Limits mirror the AI Control Center policy: proactive after 45s or 60%
   scroll (max once per 24h per visitor), 6 msgs/min, 40 msgs/conversation,
   2,000 chars/message. All wrapped so it can never break a page.
============================================================================ */
(function () {
  if (window.__jcoChatWidget) return;
  window.__jcoChatWidget = true;

  /* Public pages only */
  var path = (location.pathname.split('/').pop() || '').toLowerCase();
  if (path.indexOf('crm') === 0 || path === 'my-account.html' ||
      path.indexOf('-view.html') > -1) return;

  var FN_URL = 'https://dvsaqjvcxqlzgpbvexnu.supabase.co/functions/v1/advisory-agent';
  var GREETING = "Welcome to Jabran & Co. I\u2019m the firm\u2019s AI Advisory Agent \u2014 I can help identify the right service, answer initial questions, collect your requirements and connect you with a specialist. How can I assist?";
  var DISCLOSURE = "You are chatting with Jabran & Co.\u2019s AI Advisory Agent. Please don\u2019t share passwords or payment-card details.";
  var WHATSAPP = 'https://wa.me/923364864345';
  var PROACTIVE_MS = 45000, PROACTIVE_SCROLL = 0.6, FREQ_CAP_H = 24;
  var MAX_LEN = 2000, MAX_MSGS = 40, PER_MIN = 6;

  var history = [], sendTimes = [], open = false, busy = false;

  function el(tag, css, html) {
    var e = document.createElement(tag);
    if (css) e.style.cssText = css;
    if (html != null) e.innerHTML = html;
    return e;
  }
  function esc(s) {
    var d = document.createElement('div');
    d.textContent = s == null ? '' : String(s);
    return d.innerHTML;
  }

  function build() {
    var pos = { right: 20, bottom: 96 };            /* default sits ABOVE the WhatsApp float */
    try {
      var saved = JSON.parse(localStorage.getItem('jco_chat_pos') || 'null');
      if (saved && saved.right >= 0 && saved.bottom >= 0) pos = saved;
    } catch (e) {}
    var btn = el('div',
      'position:fixed;z-index:2147483000;width:58px;height:58px;border-radius:50%;' +
      'background:#08111C;border:2px solid #C6A55A;display:flex;align-items:center;justify-content:center;' +
      'cursor:grab;box-shadow:0 6px 22px rgba(0,0,0,0.55);user-select:none;touch-action:none;');
    btn.style.right = pos.right + 'px';
    btn.style.bottom = pos.bottom + 'px';
    btn.innerHTML =
      '<img src="favicon.png" alt="Jabran & Co." draggable="false" ' +
      'style="width:64%;height:64%;object-fit:contain;pointer-events:none;" ' +
      'onerror="this.outerHTML=\'<span style=&quot;color:#E4C98A;font-family:\\\'Playfair Display\\\',serif;font-size:19px;font-weight:600;&quot;>J&amp;Co</span>\'">';
    btn.setAttribute('role', 'button');
    btn.setAttribute('aria-label', 'Chat with Jabran & Co. (drag to move)');

    var panel = el('div',
      'position:fixed;right:16px;bottom:164px;z-index:2147483001;width:min(360px,92vw);max-height:min(560px,72vh);' +
      'display:none;flex-direction:column;background:#0B0F14;border:1px solid rgba(198,165,90,0.35);' +
      'border-radius:4px;box-shadow:0 12px 40px rgba(0,0,0,0.6);overflow:hidden;' +
      "font-family:Inter,-apple-system,sans-serif;");

    panel.appendChild(el('div',
      'padding:14px 16px;border-bottom:1px solid rgba(198,165,90,0.22);background:#08111C;',
      '<div style="font-family:\'Playfair Display\',serif;font-size:16px;color:#E4C98A;">Jabran &amp; Co. \u2014 AI Advisory</div>' +
      '<div style="font-size:10px;color:#9C9690;margin-top:3px;line-height:1.5;">' + esc(DISCLOSURE) + '</div>'));

    var log = el('div', 'flex:1;overflow-y:auto;padding:14px;min-height:180px;');
    panel.appendChild(log);

    var bar = el('div', 'display:flex;gap:8px;padding:12px;border-top:1px solid rgba(198,165,90,0.22);background:#08111C;');
    var input = el('textarea',
      'flex:1;background:#111820;border:1px solid rgba(198,165,90,0.22);color:#F5F3EF;padding:9px 11px;' +
      'font-size:13px;border-radius:2px;resize:none;height:40px;font-family:inherit;');
    input.maxLength = MAX_LEN;
    input.placeholder = 'Type your question\u2026';
    var send = el('button',
      'background:#C6A55A;color:#0B0F14;border:none;padding:0 16px;font-size:11px;letter-spacing:0.08em;' +
      'text-transform:uppercase;cursor:pointer;border-radius:2px;font-weight:600;', 'Send');
    bar.appendChild(input); bar.appendChild(send);
    panel.appendChild(bar);

    panel.appendChild(el('div', 'padding:8px 12px;background:#08111C;text-align:center;',
      '<a href="' + WHATSAPP + '" target="_blank" rel="noopener" style="font-size:11px;color:#E4C98A;text-decoration:none;">' +
      'Prefer a human? WhatsApp us \u2192</a>'));

    document.body.appendChild(btn);
    document.body.appendChild(panel);

    function push(role, text) {
      var mine = role === 'user';
      var b = el('div',
        'max-width:85%;margin:0 0 10px ' + (mine ? 'auto' : '0') + ';padding:9px 12px;font-size:13px;line-height:1.55;' +
        'border-radius:3px;color:#F5F3EF;border:1px solid rgba(198,165,90,' + (mine ? '0.4' : '0.18') + ');' +
        'background:' + (mine ? 'rgba(198,165,90,0.12)' : '#111820') + ';');
      b.innerHTML = esc(text);
      log.appendChild(b);
      log.scrollTop = log.scrollHeight;
    }

    function openPanel() {
      if (open) return;
      open = true;
      panel.style.display = 'flex';
      if (!history.length) push('assistant', GREETING);
      try { localStorage.setItem('jco_chat_last_open', String(Date.now())); } catch (e) {}
    }
    function anchorPanel() {
      var r = btn.getBoundingClientRect();
      var right = Math.max(8, window.innerWidth - r.right);
      var bottom = Math.min(window.innerHeight - 80, window.innerHeight - r.top + 12);
      panel.style.right = Math.min(right, window.innerWidth - 60) + 'px';
      panel.style.bottom = Math.max(12, bottom) + 'px';
    }
    function toggle() { if (open) { open = false; panel.style.display = 'none'; } else { anchorPanel(); openPanel(); input.focus(); } }

    /* Drag to float anywhere; a tap (< 8px movement) opens the chat */
    var drag = null;
    btn.addEventListener('pointerdown', function (e) {
      drag = { x: e.clientX, y: e.clientY, r: parseFloat(btn.style.right), b: parseFloat(btn.style.bottom), moved: false };
      btn.setPointerCapture(e.pointerId);
      btn.style.cursor = 'grabbing';
    });
    btn.addEventListener('pointermove', function (e) {
      if (!drag) return;
      var dx = drag.x - e.clientX, dy = drag.y - e.clientY;
      if (Math.abs(dx) > 8 || Math.abs(dy) > 8) drag.moved = true;
      if (!drag.moved) return;
      var right = Math.min(Math.max(drag.r + dx, 6), window.innerWidth - 64);
      var bottom = Math.min(Math.max(drag.b + dy, 6), window.innerHeight - 64);
      btn.style.right = right + 'px';
      btn.style.bottom = bottom + 'px';
      if (open) anchorPanel();
    });
    btn.addEventListener('pointerup', function (e) {
      btn.style.cursor = 'grab';
      var wasDrag = drag && drag.moved;
      if (wasDrag) {
        try {
          localStorage.setItem('jco_chat_pos', JSON.stringify({
            right: parseFloat(btn.style.right), bottom: parseFloat(btn.style.bottom)
          }));
        } catch (e2) {}
      }
      drag = null;
      if (!wasDrag) toggle();
    });
    btn.addEventListener('pointercancel', function () { drag = null; btn.style.cursor = 'grab'; });

    async function submit() {
      var text = (input.value || '').trim();
      if (!text || busy) return;
      var now = Date.now();
      sendTimes = sendTimes.filter(function (t) { return now - t < 60000; });
      if (sendTimes.length >= PER_MIN) { push('assistant', 'One moment please \u2014 a short pause between messages keeps me responsive.'); return; }
      if (history.filter(function (m) { return m.role === 'user'; }).length >= MAX_MSGS) {
        push('assistant', 'We\u2019ve covered a lot \u2014 for anything further, our team would love to continue on WhatsApp: +92 336 4864345.');
        return;
      }
      sendTimes.push(now);
      input.value = '';
      push('user', text);
      history.push({ role: 'user', content: text });
      busy = true; send.disabled = true; send.textContent = '\u2026';
      try {
        var r = await fetch(FN_URL, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ messages: history })
        });
        var d = await r.json();
        var reply = (d && d.reply) || (d && d.error) || 'Please try again, or reach us on WhatsApp: +92 336 4864345.';
        push('assistant', reply);
        if (d && d.reply) history.push({ role: 'assistant', content: d.reply });
      } catch (e) {
        push('assistant', 'Connection hiccup \u2014 please try again, or WhatsApp us: +92 336 4864345.');
      }
      busy = false; send.disabled = false; send.textContent = 'Send';
    }
    send.addEventListener('click', submit);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); }
    });

    /* Proactive open: 45s or 60% scroll, at most once per 24h per visitor */
    var can = true;
    try {
      var last = Number(localStorage.getItem('jco_chat_last_open') || 0);
      can = (Date.now() - last) > FREQ_CAP_H * 3600000;
    } catch (e) {}
    if (can) {
      var done = false;
      function fire() { if (!done) { done = true; anchorPanel(); openPanel(); } }
      setTimeout(fire, PROACTIVE_MS);
      window.addEventListener('scroll', function onS() {
        var h = document.documentElement;
        var depth = (h.scrollTop + window.innerHeight) / Math.max(h.scrollHeight, 1);
        if (depth >= PROACTIVE_SCROLL) { window.removeEventListener('scroll', onS); fire(); }
      }, { passive: true });
    }
  }

  try {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', build);
    } else { build(); }
  } catch (e) { /* the widget must never break a page */ }
})();
