/* ============================================================================
   JABRAN & CO. — utm-capture.js · ATTRIBUTION CAPTURE (public site only)
   BUILD 2026-07-16.6

   WHY: GA4 knows a visitor arrived by Organic Search. The CRM knows an enquiry
   arrived. Nothing joined them, because the enquiry form never recorded where
   the person came from. This closes that, with no page edits — it is loaded by
   animations.js, which every public page already includes.

   WHAT IT DOES
     1. On the first landing, records FIRST TOUCH (utm_*, referrer, landing
        page, click ids) in localStorage for 90 days. First touch is what
        earned the lead; it survives later Direct returns.
     2. On every visit, records LAST TOUCH in sessionStorage.
     3. Transparently merges both into any insert into crm_enquiries, by
        wrapping sb.from('crm_enquiries').insert. No form markup changes, and
        it works for the contact form, service pages and the chat widget alike.

   HONESTY
     · Nothing is inferred. If a visitor arrives with no referrer and no
       campaign, we store nothing and the database records channel 'Direct' —
       we never guess a source that was not present.
     · No personal data is stored — only campaign parameters that were already
       in the URL the visitor followed.
     · CRM pages never load this file, so staff-entered enquiries are never
       given website attribution.
============================================================================ */
(function () {
  if (typeof window === 'undefined' || window.__jcoUtm) return;
  window.__jcoUtm = true;

  var FIRST_KEY = 'jco_first_touch';
  var LAST_KEY = 'jco_last_touch';
  var TTL_DAYS = 90;

  var UTM_KEYS = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term'];
  var CLICK_KEYS = ['gclid', 'fbclid', 'li_fat_id', 'msclkid', 'ttclid'];

  function read() {
    try {
      var q = new URLSearchParams(location.search);
      var touch = { at: new Date().toISOString(), landing_page: location.pathname };
      var found = false;

      UTM_KEYS.forEach(function (k) {
        var v = q.get(k);
        if (v) { touch[k] = String(v).slice(0, 120); found = true; }
      });
      for (var i = 0; i < CLICK_KEYS.length; i++) {
        var cv = q.get(CLICK_KEYS[i]);
        if (cv) { touch.click_id = String(cv).slice(0, 200); touch.click_type = CLICK_KEYS[i]; found = true; break; }
      }

      var ref = document.referrer || '';
      if (ref && ref.indexOf(location.hostname) === -1) {
        touch.referrer = ref.slice(0, 300);
        found = true;
      }
      /* Nothing to record: a Direct arrival. We store the landing page only,
         and let the database classify it as Direct. We do not invent a source. */
      return { touch: touch, meaningful: found };
    } catch (e) {
      return { touch: null, meaningful: false };
    }
  }

  function saveFirst(touch) {
    try {
      var raw = localStorage.getItem(FIRST_KEY);
      if (raw) {
        var existing = JSON.parse(raw);
        if (existing && existing.at && (Date.now() - Date.parse(existing.at)) < TTL_DAYS * 86400000) {
          return;                       /* first touch already held; never overwrite */
        }
      }
      localStorage.setItem(FIRST_KEY, JSON.stringify(touch));
    } catch (e) {}
  }

  function get(key, store) {
    try {
      var raw = (store || localStorage).getItem(key);
      if (!raw) return null;
      var v = JSON.parse(raw);
      if (key === FIRST_KEY && v && v.at &&
          (Date.now() - Date.parse(v.at)) > TTL_DAYS * 86400000) return null;
      return v;
    } catch (e) { return null; }
  }

  var r = read();
  if (r.touch) {
    if (r.meaningful) saveFirst(r.touch);
    try { sessionStorage.setItem(LAST_KEY, JSON.stringify(r.touch)); } catch (e) {}
  }

  /* ---- what the enquiry insert should carry ---- */
  function attribution() {
    var first = get(FIRST_KEY, localStorage);
    var last = get(LAST_KEY, sessionStorage) || first;
    var src = first || last || {};
    var out = {
      utm_source: src.utm_source || null,
      utm_medium: src.utm_medium || null,
      utm_campaign: src.utm_campaign || null,
      utm_content: src.utm_content || null,
      utm_term: src.utm_term || null,
      referrer: src.referrer || null,
      landing_page: src.landing_page || null,
      click_id: src.click_id || null,
      first_touch: first || null,
      last_touch: last || null
    };
    return out;
  }
  window.jcoAttribution = attribution;

  /* ---- merge into any crm_enquiries insert, with no form changes ---- */
  function wrap() {
    if (typeof sb === 'undefined' || !sb || !sb.from || sb.__jcoUtmWrapped) return false;
    sb.__jcoUtmWrapped = true;
    var origFrom = sb.from.bind(sb);
    sb.from = function (table) {
      var q = origFrom(table);
      if (table === 'crm_enquiries' && q && typeof q.insert === 'function') {
        var origInsert = q.insert.bind(q);
        q.insert = function (payload, opts) {
          try {
            var a = attribution();
            var merge = function (row) {
              if (!row || typeof row !== 'object') return row;
              Object.keys(a).forEach(function (k) {
                if (a[k] !== null && row[k] === undefined) row[k] = a[k];
              });
              return row;
            };
            payload = Array.isArray(payload) ? payload.map(merge) : merge(payload);
            try { console.info('[J&Co] enquiry attribution attached:', a.utm_source || a.referrer || 'direct'); } catch (e) {}
          } catch (e) { /* never block a real enquiry because of analytics */ }
          return origInsert(payload, opts);
        };
      }
      return q;
    };
    return true;
  }

  if (!wrap()) {
    /* supabase-client.js may load after us on some pages */
    var tries = 0;
    var t = setInterval(function () {
      tries++;
      if (wrap() || tries > 20) clearInterval(t);
    }, 250);
  }
})();
