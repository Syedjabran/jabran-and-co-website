// Jabran & Co — Premium interaction layer
// Native browser scrolling everywhere (fast and consistent on every mouse,
// trackpad, and touchscreen). GSAP + ScrollTrigger load dynamically for the
// reveal animations, with safe fallbacks if anything fails to load.
// NOTE: The previous Lenis smooth-wheel layer was removed deliberately —
// it hijacked the mouse wheel and made scrolling feel extremely slow on
// standard mice. Do not reintroduce wheel/scroll interception.

(function () {
  var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var isFinePointer = window.matchMedia('(hover: hover) and (pointer: fine)').matches;

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  // ---------- Fallback: original IntersectionObserver reveal (always runs first, upgraded later if GSAP loads) ----------
  function basicReveal() {
    var selectors = ['.section-head', '.service-card', '.teaser-card', '.manifest-row', '.contact-card', '.about-figure', '.flow-step', '.checklist'];
    var targets = document.querySelectorAll(selectors.join(','));
    if (!('IntersectionObserver' in window) || targets.length === 0) {
      targets.forEach(function (el) { el.classList.add('reveal', 'is-visible'); });
      return;
    }
    targets.forEach(function (el) { el.classList.add('reveal'); });
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -40px 0px' });
    targets.forEach(function (el) { observer.observe(el); });
  }

  document.addEventListener('DOMContentLoaded', basicReveal);

  // ---------- Page loader fade-out (loader itself is CSS-driven, this just cleans up the DOM node) ----------
  window.addEventListener('load', function () {
    var loader = document.getElementById('jc-loader');
    if (loader) {
      setTimeout(function () { loader.remove(); }, 1600);
    }
  });

  if (reducedMotion) return; // Stop here — no GSAP upgrade, no custom cursor.

  // ---------- Load GSAP + ScrollTrigger, then upgrade the reveals (native scroll stays untouched) ----------
  loadScript('https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js')
    .then(function () { return loadScript('https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/ScrollTrigger.min.js'); })
    .then(function () {
      if (!window.gsap) return;
      gsap.registerPlugin(ScrollTrigger);

      // Upgrade reveal: re-animate anything not yet visible using GSAP for smoother easing.
      // ScrollTrigger listens to the browser's own scroll — no wheel interception.
      document.querySelectorAll('.reveal').forEach(function (el) {
        gsap.fromTo(el, { opacity: 0, y: 18 }, {
          opacity: 1, y: 0, duration: 0.9, ease: 'power3.out',
          scrollTrigger: { trigger: el, start: 'top 88%', once: true }
        });
        el.classList.add('is-visible'); // prevents the CSS fallback transition from double-firing
      });
    })
    .catch(function () { /* GSAP failed to load — basicReveal() fallback already covers this */ });

  // ---------- Custom cursor (desktop only, real pointer only) ----------
  if (!isFinePointer) return;

  var ring = document.createElement('div');
  var dot = document.createElement('div');
  ring.className = 'jc-cursor-ring';
  dot.className = 'jc-cursor-dot';
  document.body.appendChild(ring);
  document.body.appendChild(dot);
  document.documentElement.classList.add('jc-custom-cursor');

  var mouseX = 0, mouseY = 0, ringX = 0, ringY = 0;
  window.addEventListener('mousemove', function (e) {
    mouseX = e.clientX; mouseY = e.clientY;
    dot.style.transform = 'translate(' + mouseX + 'px,' + mouseY + 'px)';
  });

  function ringLoop() {
    ringX += (mouseX - ringX) * 0.18;
    ringY += (mouseY - ringY) * 0.18;
    ring.style.transform = 'translate(' + ringX + 'px,' + ringY + 'px)';
    requestAnimationFrame(ringLoop);
  }
  ringLoop();

  document.addEventListener('mouseover', function (e) {
    if (e.target.closest('a, button, .btn, input, textarea, select')) {
      ring.classList.add('jc-cursor-active');
    }
  });
  document.addEventListener('mouseout', function (e) {
    if (e.target.closest('a, button, .btn, input, textarea, select')) {
      ring.classList.remove('jc-cursor-active');
    }
  });
})();
