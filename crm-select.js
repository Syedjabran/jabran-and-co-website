/* ============================================================================
   JABRAN & CO. CRM — crm-select.js · SEARCHABLE SELECT
   BUILD 2026-07-16.7

   WHY THIS SHAPE
     The CRM contains 108 <select> elements; 23 are filled at runtime, so their
     length is unknown until data arrives. Patching 108 places would guarantee
     108 inconsistencies. This is one enhancer, loaded once from crm-auth.js,
     applied automatically.

   THE CRITICAL CONSTRAINT — and the reason this is not a rewrite:
     Every page reads values with document.getElementById(id).value and listens
     for 'change'. So the NATIVE <select> stays in the DOM and stays the single
     source of truth. This only hides it visually and drives it: on choose we
     set select.value and dispatch a real bubbling 'change'. Existing code,
     validation, saved values and payloads cannot tell the difference.

   BEHAVIOUR
     · 10 or fewer options  -> untouched. Native select, native mobile picker.
     · More than 10         -> a search panel opens instead.
     · Re-evaluated automatically when options are injected later (fillSelect
       replaces innerHTML), so a select that grows past 10 upgrades itself.
     · Search: case-insensitive, trims, partial match anywhere, matches the
       option text AND its optgroup label (so "customs" finds the whole H group).
     · Keyboard: type to filter, ↑/↓ to move, Enter to choose, Escape to close,
       focus returns to the trigger. Tab order preserved.
     · Touch: 44px rows, full-width sheet under 640px.
     · Empty state: "No matching records found" + a clear control.
     · Nothing is fetched or re-rendered until the panel is opened, so a 349-row
       list costs nothing on page load.
   ============================================================================ */
(function () {
  if (window.__jcoSelect) return;
  window.__jcoSelect = true;

  var THRESHOLD = 10;                 /* window.JCO_SELECT_THRESHOLD to override */
  var MOBILE = 640;

  function threshold() {
    return Number(window.JCO_SELECT_THRESHOLD || THRESHOLD);
  }

  /* ---------------- styles ---------------- */
  try {
    var css = document.createElement('style');
    css.id = 'jco-select-css';
    css.textContent = [
      '.jco-sel-trigger{display:flex;align-items:center;justify-content:space-between;gap:8px;',
      '  width:100%;min-height:40px;background:#0B0F14;border:1px solid rgba(198,165,90,0.22);',
      '  color:#F5F3EF;padding:8px 11px;font-size:13px;border-radius:2px;cursor:pointer;',
      '  font-family:Inter,sans-serif;text-align:left;}',
      '.jco-sel-trigger:hover{border-color:#C6A55A;}',
      '.jco-sel-trigger:focus-visible{outline:2px solid #E4C98A;outline-offset:1px;}',
      '.jco-sel-trigger[disabled]{opacity:0.5;cursor:not-allowed;}',
      '.jco-sel-trigger .v{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}',
      '.jco-sel-trigger .v.ph{color:#9C9690;}',
      '.jco-sel-trigger .c{color:#9C9690;font-size:9px;flex-shrink:0;}',
      '.jco-sel-bg{position:fixed;inset:0;z-index:2147483200;background:rgba(4,7,10,0.55);',
      '  display:flex;align-items:flex-start;justify-content:center;padding:60px 16px 16px;}',
      '.jco-sel-panel{width:100%;max-width:460px;background:#0B0F14;border:1px solid rgba(198,165,90,0.35);',
      '  border-radius:4px;box-shadow:0 18px 50px rgba(0,0,0,0.65);display:flex;flex-direction:column;',
      '  max-height:min(70vh,560px);overflow:hidden;}',
      '.jco-sel-head{padding:12px;border-bottom:1px solid rgba(198,165,90,0.22);background:#08111C;',
      '  display:flex;gap:8px;align-items:center;}',
      '.jco-sel-head input{flex:1;background:#0B0F14;border:1px solid rgba(198,165,90,0.22);color:#F5F3EF;',
      '  padding:10px 12px;font-size:16px;border-radius:2px;font-family:Inter,sans-serif;}',
      '.jco-sel-head input:focus{outline:none;border-color:#C6A55A;}',
      '.jco-sel-clear{background:transparent;border:1px solid rgba(198,165,90,0.28);color:#E4C98A;',
      '  padding:9px 11px;font-size:11px;border-radius:2px;cursor:pointer;min-height:40px;}',
      '.jco-sel-list{overflow-y:auto;-webkit-overflow-scrolling:touch;padding:6px 0;}',
      '.jco-sel-group{font-family:"IBM Plex Mono",monospace;font-size:9px;letter-spacing:0.18em;',
      '  text-transform:uppercase;color:#C6A55A;padding:10px 14px 4px;position:sticky;top:0;background:#0B0F14;}',
      '.jco-sel-opt{display:block;width:100%;text-align:left;background:transparent;border:0;',
      '  color:#F5F3EF;font-family:Inter,sans-serif;font-size:13px;padding:11px 14px;min-height:44px;',
      '  cursor:pointer;line-height:1.4;}',
      '.jco-sel-opt:hover,.jco-sel-opt.on{background:rgba(198,165,90,0.10);}',
      '.jco-sel-opt.sel{color:#E4C98A;}',
      '.jco-sel-opt mark{background:rgba(198,165,90,0.30);color:inherit;border-radius:1px;}',
      '.jco-sel-empty{padding:22px 14px;text-align:center;color:#9C9690;font-size:13px;}',
      '.jco-sel-foot{padding:8px 12px;border-top:1px solid rgba(198,165,90,0.18);background:#08111C;',
      '  font-family:"IBM Plex Mono",monospace;font-size:9px;color:#9C9690;letter-spacing:0.08em;}',
      '@media (max-width:' + MOBILE + 'px){',
      '  .jco-sel-bg{padding:0;align-items:flex-end;}',
      '  .jco-sel-panel{max-width:100%;max-height:82vh;border-radius:4px 4px 0 0;}',
      '}'
    ].join('\n');
    document.head.appendChild(css);
  } catch (e) {}

  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
  function norm(s) { return String(s || '').trim().toLowerCase(); }

  function realOptions(sel) {
    /* a leading blank/placeholder option does not count towards the threshold */
    return Array.prototype.filter.call(sel.options, function (o) { return o.value !== ''; });
  }

  function collect(sel) {
    var out = [], group = null;
    Array.prototype.forEach.call(sel.children, function (node) {
      if (node.tagName === 'OPTGROUP') {
        group = node.label;
        Array.prototype.forEach.call(node.children, function (o) {
          out.push({ value: o.value, text: o.textContent, group: group, disabled: o.disabled });
        });
      } else if (node.tagName === 'OPTION') {
        out.push({ value: node.value, text: node.textContent, group: null, disabled: node.disabled });
      }
    });
    return out;
  }

  function highlight(text, q) {
    if (!q) return esc(text);
    var i = norm(text).indexOf(q);
    if (i < 0) return esc(text);
    return esc(text.slice(0, i)) + '<mark>' + esc(text.slice(i, i + q.length)) + '</mark>' + esc(text.slice(i + q.length));
  }

  /* ---------------- the panel ---------------- */
  function open(sel, trigger) {
    var opts = collect(sel);
    var bg = document.createElement('div');
    bg.className = 'jco-sel-bg';
    bg.innerHTML =
      '<div class="jco-sel-panel" role="dialog" aria-modal="true">' +
        '<div class="jco-sel-head">' +
          '<input type="text" inputmode="search" autocomplete="off" placeholder="Search…" aria-label="Search options">' +
          '<button type="button" class="jco-sel-clear">Clear</button>' +
        '</div>' +
        '<div class="jco-sel-list" role="listbox"></div>' +
        '<div class="jco-sel-foot"></div>' +
      '</div>';
    document.body.appendChild(bg);

    var input = bg.querySelector('input');
    var list = bg.querySelector('.jco-sel-list');
    var foot = bg.querySelector('.jco-sel-foot');
    var cursor = -1, shown = [];

    function render() {
      var q = norm(input.value);
      shown = opts.filter(function (o) {
        if (o.disabled) return false;
        if (!q) return true;
        /* match the option text OR its group label, so "customs" finds the group */
        return norm(o.text).indexOf(q) > -1 || norm(o.group).indexOf(q) > -1;
      });
      if (!shown.length) {
        list.innerHTML = '<div class="jco-sel-empty">No matching records found</div>';
        foot.textContent = '0 of ' + opts.length;
        return;
      }
      var html = '', lastG = null;
      shown.forEach(function (o, i) {
        if (o.group && o.group !== lastG) {
          html += '<div class="jco-sel-group">' + esc(o.group) + '</div>';
          lastG = o.group;
        }
        html += '<button type="button" class="jco-sel-opt' + (o.value === sel.value ? ' sel' : '') +
                '" role="option" data-i="' + i + '">' + highlight(o.text, q) + '</button>';
      });
      list.innerHTML = html;
      foot.textContent = shown.length + ' of ' + opts.length + (q ? ' matching' : '') +
                         '  ·  ↑↓ move · Enter select · Esc close';
      cursor = -1;
    }

    function choose(o) {
      sel.value = o.value;
      /* real, bubbling events: every existing listener in the CRM still fires */
      sel.dispatchEvent(new Event('input', { bubbles: true }));
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      paint(sel, trigger);
      close();
    }
    function close() {
      bg.remove();
      document.removeEventListener('keydown', onKey, true);
      trigger.focus();
    }
    function move(d) {
      var btns = list.querySelectorAll('.jco-sel-opt');
      if (!btns.length) return;
      cursor = Math.max(0, Math.min(btns.length - 1, cursor + d));
      Array.prototype.forEach.call(btns, function (b) { b.classList.remove('on'); });
      btns[cursor].classList.add('on');
      btns[cursor].scrollIntoView({ block: 'nearest' });
    }
    function onKey(e) {
      if (e.key === 'Escape') { e.preventDefault(); close(); }
      else if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
      else if (e.key === 'Enter') {
        e.preventDefault();
        var btns = list.querySelectorAll('.jco-sel-opt');
        var pick = cursor >= 0 ? btns[cursor] : btns[0];
        if (pick) choose(shown[Number(pick.dataset.i)]);
      }
    }

    input.addEventListener('input', render);
    bg.querySelector('.jco-sel-clear').addEventListener('click', function () {
      input.value = ''; render(); input.focus();
    });
    list.addEventListener('click', function (e) {
      var b = e.target.closest('.jco-sel-opt');
      if (b) choose(shown[Number(b.dataset.i)]);
    });
    bg.addEventListener('click', function (e) { if (e.target === bg) close(); });
    document.addEventListener('keydown', onKey, true);

    render();
    /* do not autofocus on touch: it throws the keyboard up over the list */
    if (window.matchMedia('(hover:hover)').matches) input.focus();
  }

  /* ---------------- trigger paint ---------------- */
  function paint(sel, trigger) {
    var o = sel.options[sel.selectedIndex];
    var txt = o ? o.textContent : '';
    var placeholder = !sel.value;
    trigger.innerHTML = '<span class="v' + (placeholder ? ' ph' : '') + '">' +
      esc(txt || 'Select…') + '</span><span class="c">▾</span>';
    trigger.disabled = sel.disabled;
  }

  /* ---------------- enhance / revert ---------------- */
  function enhance(sel) {
    if (sel.multiple) return;                       /* native multi-select left alone */
    if (sel.dataset.jcoNoSearch === 'true') return; /* explicit opt-out */
    var big = realOptions(sel).length > threshold();

    if (!big) {
      if (sel.__jcoTrigger) {                       /* shrank back below the line */
        sel.__jcoTrigger.remove();
        sel.__jcoTrigger = null;
        sel.style.display = sel.__jcoDisplay || '';
      }
      return;
    }
    if (sel.__jcoTrigger) { paint(sel, sel.__jcoTrigger); return; }

    var trigger = document.createElement('button');
    trigger.type = 'button';
    trigger.className = 'jco-sel-trigger';
    trigger.setAttribute('aria-haspopup', 'listbox');
    if (sel.id) trigger.setAttribute('aria-label', 'Search and select: ' + sel.id.replace(/[-_]/g, ' '));
    trigger.addEventListener('click', function (e) { e.preventDefault(); open(sel, trigger); });

    sel.__jcoDisplay = sel.style.display;
    sel.style.display = 'none';                     /* native select stays in the DOM */
    sel.__jcoTrigger = trigger;
    sel.insertAdjacentElement('afterend', trigger);
    paint(sel, trigger);

    /* if page code sets .value programmatically and fires change, repaint */
    sel.addEventListener('change', function () { paint(sel, trigger); });
  }

  function scan(root) {
    try {
      (root || document).querySelectorAll('select').forEach(enhance);
    } catch (e) {}
  }

  document.addEventListener('DOMContentLoaded', function () {
    scan(document);
    /* fillSelect() replaces innerHTML long after load; watch for that and for
       modals injected on open. Debounced so a 349-option build costs one pass. */
    var pending = null;
    try {
      new MutationObserver(function (muts) {
        var touched = false;
        muts.forEach(function (m) {
          if (m.target && m.target.tagName === 'SELECT') touched = true;
          else if (m.addedNodes && m.addedNodes.length) touched = true;
        });
        if (!touched) return;
        clearTimeout(pending);
        pending = setTimeout(function () { scan(document); }, 120);
      }).observe(document.body, { childList: true, subtree: true });
    } catch (e) {}
  });

  window.jcoSelect = { scan: scan, enhance: enhance };
})();
