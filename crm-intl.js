/* ============================================================================
   JABRAN & CO. CRM — crm-intl.js · GLOBAL COUNTRY + PHONE STANDARD
   Include AFTER supabase-client.js on any page with forms:
     <script src="crm-intl.js"></script>

   Auto-enhances, with zero per-form code:
   • Every input whose id ends in "-country" (or name="country") becomes a
     searchable dropdown backed by the central crm_countries table
     (ISO 3166-1). The stored value remains the country name — fully
     compatible with all existing data and reports.
   • Every input whose id/name contains "phone" or "whatsapp" becomes an
     international phone field: flag + calling-code selector, national
     number entry, automatic E.164 normalisation (+92336…), light
     validation. The original input remains the single source of truth,
     so all existing save logic works unchanged.
   Existing values are parsed on modal open (programmatic value changes
   are detected), including numbers already stored without a dial code.
============================================================================ */
(function () {
  var COUNTRIES = null;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }

  async function loadCountries() {
    try {
      var cached = sessionStorage.getItem('jco_countries');
      if (cached) { COUNTRIES = JSON.parse(cached); return; }
    } catch (e) {}
    if (typeof sb === 'undefined') return;
    try {
      var res = await sb.from('crm_countries').select('iso2,name,dial_code,flag,sort_hint')
        .eq('is_active', true).order('sort_hint', { ascending: true, nullsFirst: false }).order('name');
      if (res.data && res.data.length) {
        COUNTRIES = res.data;
        try { sessionStorage.setItem('jco_countries', JSON.stringify(COUNTRIES)); } catch (e) {}
      }
    } catch (e) { /* forms stay as plain inputs — graceful */ }
  }

  /* ---------------- Country dropdown (datalist keeps the input element,
     its id, and its value semantics — nothing else changes) -------------- */
  function enhanceCountry(input) {
    if (input.dataset.jcoIntl) return;
    input.dataset.jcoIntl = '1';
    var dl = document.getElementById('jco-countries-dl');
    if (!dl) {
      dl = document.createElement('datalist');
      dl.id = 'jco-countries-dl';
      dl.innerHTML = COUNTRIES.map(function (c) {
        return '<option value="' + esc(c.name) + '">' + esc(c.flag + ' ' + c.name) + '</option>';
      }).join('');
      document.body.appendChild(dl);
    }
    input.setAttribute('list', 'jco-countries-dl');
    input.setAttribute('autocomplete', 'off');
    if (!input.placeholder || /country/i.test(input.placeholder) === false) {
      input.placeholder = 'Start typing a country…';
    }
    input.addEventListener('blur', function () {
      var v = input.value.trim().toLowerCase();
      if (!v) return;
      var hit = COUNTRIES.find(function (c) { return c.name.toLowerCase() === v; }) ||
                COUNTRIES.find(function (c) { return c.name.toLowerCase().startsWith(v); });
      if (hit) input.value = hit.name;   // normalise to the canonical name
    });
  }

  /* ---------------- International phone (E.164) ------------------------- */
  function digitsOnly(s){ return (s||'').replace(/[^0-9]/g,''); }

  function findByDial(numDigits) {
    var best = null;
    COUNTRIES.forEach(function (c) {
      if (numDigits.indexOf(c.dial_code) === 0) {
        if (!best || c.dial_code.length > best.dial_code.length) best = c;
      }
    });
    return best;
  }

  function enhancePhone(input) {
    if (input.dataset.jcoIntl) return;
    input.dataset.jcoIntl = '1';

    var wrap = document.createElement('div');
    wrap.style.cssText = 'display:flex; gap:6px; align-items:stretch;';
    input.parentNode.insertBefore(wrap, input);

    var sel = document.createElement('select');
    sel.setAttribute('aria-label', 'Country calling code');
    sel.style.cssText =
      'background:var(--bg-alt,#111820); border:1px solid var(--line,rgba(198,165,90,0.22));' +
      "color:var(--cream,#F5F3EF); border-radius:2px; font-family:'IBM Plex Mono',monospace;" +
      'font-size:12px; padding:0 6px; max-width:118px; flex-shrink:0;';
    sel.innerHTML = COUNTRIES.map(function (c) {
      return '<option value="' + c.iso2 + '">' + esc(c.flag) + ' +' + esc(c.dial_code) + '</option>';
    }).join('');
    wrap.appendChild(sel);
    wrap.appendChild(input);
    input.style.flex = '1';
    input.setAttribute('inputmode', 'tel');
    if (!input.placeholder) input.placeholder = '3xx xxxxxxx';

    var defaultIso = 'PK';
    sel.value = defaultIso;
    var lastSeen = null;

    function dialOf(iso) {
      var c = COUNTRIES.find(function (x) { return x.iso2 === iso; });
      return c ? c.dial_code : '92';
    }

    /* Normalise whatever is in the field to +<dial><national> */
    function normalise() {
      var raw = input.value.trim();
      if (!raw) { lastSeen=''; return; }
      var num = digitsOnly(raw);
      if (raw.charAt(0) === '+' || raw.slice(0,2) === '00') {
        if (raw.slice(0,2) === '00') num = num.replace(/^00/,'');
        var hit = findByDial(num);
        if (hit) { sel.value = hit.iso2; input.value = '+' + num; lastSeen = input.value; return; }
      }
      num = num.replace(/^0+/, '');                 // drop trunk zero(s)
      input.value = '+' + dialOf(sel.value) + num;
      lastSeen = input.value;
      // light length validation
      var nat = num.length;
      input.style.borderColor = (nat >= 4 && nat <= 13) ? '' : '#e57368';
    }

    /* Parse an existing / programmatically-set value into the selector */
    function parseExisting() {
      var raw = input.value.trim();
      lastSeen = raw;
      if (!raw) { sel.value = defaultIso; return; }
      var num = digitsOnly(raw);
      if (raw.charAt(0) === '+') {
        var hit = findByDial(num);
        if (hit) sel.value = hit.iso2;
      }
    }

    input.addEventListener('blur', normalise);
    sel.addEventListener('change', function () {
      var num = digitsOnly(input.value);
      // strip a previous dial code if one was applied
      var prev = findByDial(num);
      if (input.value.trim().charAt(0) === '+' && prev) num = num.slice(prev.dial_code.length);
      num = num.replace(/^0+/, '');
      input.value = num ? '+' + dialOf(sel.value) + num : '';
      lastSeen = input.value;
    });

    /* Detect programmatic changes (edit modals call setval directly) */
    setInterval(function () {
      if (document.hidden) return;
      if (input.value !== lastSeen) parseExisting();
    }, 800);
    parseExisting();
  }

  /* ---------------- Auto-discovery ---------------- */
  function enhanceAll() {
    if (!COUNTRIES || !COUNTRIES.length) return;
    var inputs = document.querySelectorAll('input');
    inputs.forEach(function (el) {
      var key = ((el.id || '') + ' ' + (el.name || '')).toLowerCase();
      if (el.type === 'hidden' || el.type === 'password' || el.type === 'email') return;
      if (/(^|[-_ ])country$/.test(key.trim()) || el.name === 'country') enhanceCountry(el);
      else if (key.indexOf('phone') !== -1 || key.indexOf('whatsapp') !== -1) enhancePhone(el);
    });
  }

  document.addEventListener('DOMContentLoaded', async function () {
    await loadCountries();
    enhanceAll();
    // catch late-added forms (dynamically built views)
    var mo = new MutationObserver(function () { enhanceAll(); });
    mo.observe(document.body, { childList: true, subtree: true });
  });
})();
