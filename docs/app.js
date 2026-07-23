const root = document.documentElement;
const body = document.body;
const header = document.querySelector('.site-header');
const navToggle = document.querySelector('.nav-toggle');
const languageSwitch = document.querySelector('.language-switch');
const year = document.querySelector('#year');

const storage = {
  get() {
    try { return localStorage.getItem('321doit-site-lang'); } catch { return null; }
  },
  set(value) {
    try { localStorage.setItem('321doit-site-lang', value); } catch {}
  }
};

function setLanguage(lang) {
  const next = lang === 'en' ? 'en' : 'zh';
  body.classList.toggle('lang-en', next === 'en');
  body.classList.toggle('lang-zh', next !== 'en');
  root.lang = next === 'en' ? 'en' : 'zh-CN';
  storage.set(next);
  languageSwitch?.setAttribute('aria-label', next === 'en' ? '切换到中文' : 'Switch to English');
}

setLanguage(storage.get() || 'zh');

languageSwitch?.addEventListener('click', () => {
  setLanguage(body.classList.contains('lang-en') ? 'zh' : 'en');
});

navToggle?.addEventListener('click', () => {
  const open = header.classList.toggle('nav-open');
  navToggle.setAttribute('aria-expanded', String(open));
});

document.querySelectorAll('.nav-panel a').forEach((link) => {
  link.addEventListener('click', () => {
    header.classList.remove('nav-open');
    navToggle?.setAttribute('aria-expanded', 'false');
  });
});

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });

document.querySelectorAll('.reveal').forEach((el) => observer.observe(el));

const tilt = document.querySelector('[data-tilt]');
if (tilt && matchMedia('(pointer: fine)').matches) {
  tilt.addEventListener('mousemove', (event) => {
    const rect = tilt.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    tilt.style.setProperty('--ry', `${x * 7}deg`);
    tilt.style.setProperty('--rx', `${y * -7}deg`);
  });

  tilt.addEventListener('mouseleave', () => {
    tilt.style.setProperty('--rx', '0deg');
    tilt.style.setProperty('--ry', '0deg');
  });
}

if (year) year.textContent = String(new Date().getFullYear());
