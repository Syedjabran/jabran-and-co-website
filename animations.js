// Subtle, professional scroll-reveal for Jabran & Co
document.addEventListener('DOMContentLoaded', function () {
  var selectors = [
    '.section-head',
    '.service-card',
    '.teaser-card',
    '.manifest-row',
    '.contact-card',
    '.about-figure',
    '.flow-step',
    '.checklist'
  ];
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
});
