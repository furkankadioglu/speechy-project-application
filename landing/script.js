/* ============================================
   Speechy Landing Page — Interactions
   ============================================ */

(function () {
  'use strict';

  // ── Scroll-triggered fade-in animations ──────────────────────────
  function initScrollAnimations() {
    var elements = document.querySelectorAll('.fade-in');
    if (!elements.length) return;

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.1,
      rootMargin: '0px 0px -40px 0px'
    });

    elements.forEach(function (el) {
      observer.observe(el);
    });
  }

  // ── Smooth scroll for anchor links ───────────────────────────────
  function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(function (link) {
      link.addEventListener('click', function (e) {
        var targetId = this.getAttribute('href');
        if (targetId === '#') return;
        var target = document.querySelector(targetId);
        if (!target) return;
        e.preventDefault();
        var navHeight = document.querySelector('.navbar').offsetHeight;
        var top = target.getBoundingClientRect().top + window.pageYOffset - navHeight - 16;
        window.scrollTo({ top: top, behavior: 'smooth' });
      });
    });
  }

  // ── Active nav link highlighting ─────────────────────────────────
  function initNavHighlight() {
    var sections = document.querySelectorAll('section[id]');
    var navLinks = document.querySelectorAll('.nav-links a');
    if (!sections.length || !navLinks.length) return;

    window.addEventListener('scroll', function () {
      var scrollY = window.pageYOffset;
      var navHeight = document.querySelector('.navbar').offsetHeight;

      sections.forEach(function (section) {
        var top = section.offsetTop - navHeight - 80;
        var bottom = top + section.offsetHeight;
        var id = section.getAttribute('id');

        if (scrollY >= top && scrollY < bottom) {
          navLinks.forEach(function (link) {
            link.style.color = '';
            if (link.getAttribute('href') === '#' + id) {
              link.style.color = '#a855f7';
            }
          });
        }
      });
    }, { passive: true });
  }

  // ── Animated hero waveform ───────────────────────────────────────
  function initWaveform() {
    var container = document.querySelector('.waveform-bars');
    if (!container) return;

    var svg = container.closest('svg');
    var numBars = 50;
    var barWidth = 4;
    var gap = (400 - numBars * barWidth) / (numBars - 1);

    // Add gradient definition
    var defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
    var grad = document.createElementNS('http://www.w3.org/2000/svg', 'linearGradient');
    grad.setAttribute('id', 'waveGrad');
    grad.setAttribute('x1', '0');
    grad.setAttribute('y1', '0');
    grad.setAttribute('x2', '1');
    grad.setAttribute('y2', '0');

    var stops = [
      { offset: '0%', color: '#4f8cff' },
      { offset: '50%', color: '#a855f7' },
      { offset: '100%', color: '#ec4899' }
    ];

    stops.forEach(function (s) {
      var stop = document.createElementNS('http://www.w3.org/2000/svg', 'stop');
      stop.setAttribute('offset', s.offset);
      stop.setAttribute('stop-color', s.color);
      grad.appendChild(stop);
    });

    defs.appendChild(grad);
    svg.insertBefore(defs, svg.firstChild);

    // Create bars
    var bars = [];
    for (var i = 0; i < numBars; i++) {
      var rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      var x = i * (barWidth + gap);
      rect.setAttribute('x', x);
      rect.setAttribute('width', barWidth);
      rect.setAttribute('rx', '2');
      rect.setAttribute('fill', 'url(#waveGrad)');
      rect.setAttribute('opacity', '0.7');
      container.appendChild(rect);
      bars.push(rect);
    }

    // Animate
    var centerIndex = numBars / 2;
    function animateBars(time) {
      bars.forEach(function (bar, i) {
        var distFromCenter = Math.abs(i - centerIndex) / centerIndex;
        var baseHeight = 8 + (1 - distFromCenter) * 40;
        var wave1 = Math.sin(time * 0.003 + i * 0.3) * 15;
        var wave2 = Math.sin(time * 0.005 + i * 0.15) * 8;
        var wave3 = Math.sin(time * 0.002 + i * 0.5) * 5;
        var h = Math.max(4, baseHeight + wave1 + wave2 + wave3);
        var y = (80 - h) / 2;
        bar.setAttribute('height', h);
        bar.setAttribute('y', y);
      });
      requestAnimationFrame(animateBars);
    }

    requestAnimationFrame(animateBars);
  }

  // ── Navbar background on scroll ──────────────────────────────────
  function initNavbarScroll() {
    var navbar = document.querySelector('.navbar');
    if (!navbar) return;

    window.addEventListener('scroll', function () {
      if (window.scrollY > 50) {
        navbar.style.background = 'rgba(15, 11, 26, 0.95)';
      } else {
        navbar.style.background = 'rgba(15, 11, 26, 0.8)';
      }
    }, { passive: true });
  }

  // ── Card tilt effect on hover ────────────────────────────────────
  function initCardTilt() {
    var cards = document.querySelectorAll('.feature-card, .highlight-card, .privacy-card, .step');

    cards.forEach(function (card) {
      card.addEventListener('mousemove', function (e) {
        var rect = card.getBoundingClientRect();
        var x = e.clientX - rect.left;
        var y = e.clientY - rect.top;
        var centerX = rect.width / 2;
        var centerY = rect.height / 2;
        var rotateX = (y - centerY) / centerY * -3;
        var rotateY = (x - centerX) / centerX * 3;

        card.style.transform = 'translateY(-4px) perspective(600px) rotateX(' + rotateX + 'deg) rotateY(' + rotateY + 'deg)';
      });

      card.addEventListener('mouseleave', function () {
        card.style.transform = '';
      });
    });
  }

  // ── CAPTCHA ────────────────────────────────────────────────────
  var captchaAnswer = 0;

  function generateCaptcha() {
    var ops = [
      function () { var a = rand(2, 15), b = rand(1, 10); return { q: a + ' + ' + b, a: a + b }; },
      function () { var a = rand(10, 25), b = rand(1, a - 1); return { q: a + ' − ' + b, a: a - b }; },
      function () { var a = rand(2, 9), b = rand(2, 6); return { q: a + ' × ' + b, a: a * b }; },
    ];
    var pick = ops[Math.floor(Math.random() * ops.length)]();
    captchaAnswer = pick.a;
    var el = document.getElementById('captcha-question');
    if (el) el.textContent = pick.q + ' =';
    var inp = document.getElementById('captcha-answer');
    if (inp) { inp.value = ''; inp.classList.remove('captcha-error'); }
  }

  function rand(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  // ── Email signup form ──────────────────────────────────────────
  function initSignupForm() {
    var form = document.getElementById('signup-form');
    if (!form) return;

    var API_URL = 'https://speechy.frkn.com.tr';

    var input = document.getElementById('signup-email');
    var btn = document.getElementById('signup-btn');
    var btnText = btn.querySelector('.btn-text');
    var btnSpinner = btn.querySelector('.btn-spinner');
    var message = document.getElementById('signup-message');
    var captchaInput = document.getElementById('captcha-answer');

    // Generate initial captcha
    generateCaptcha();

    form.addEventListener('submit', function (e) {
      e.preventDefault();

      var email = input.value.trim().toLowerCase();
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        showMessage('Please enter a valid email address.', 'error');
        return;
      }

      // Validate captcha
      var userAnswer = parseInt(captchaInput.value, 10);
      if (isNaN(userAnswer) || userAnswer !== captchaAnswer) {
        captchaInput.classList.add('captcha-error');
        showMessage('Wrong answer. Please solve the math problem.', 'error');
        generateCaptcha();
        return;
      }

      // Show loading state
      btn.disabled = true;
      btnText.textContent = 'Sending...';
      btnSpinner.style.display = 'inline-flex';
      message.style.display = 'none';

      fetch(API_URL + '/api/signup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email })
      })
      .then(function (res) { return res.json().then(function (data) { return { ok: res.ok, data: data }; }); })
      .then(function (result) {
        if (result.ok) {
          showMessage('Check your inbox! We sent a verification link to ' + email, 'success');
          input.value = '';
          generateCaptcha();
        } else {
          showMessage(result.data.error || 'Something went wrong. Please try again.', 'error');
          generateCaptcha();
        }
      })
      .catch(function () {
        showMessage('Could not connect to the server. Please try again later.', 'error');
        generateCaptcha();
      })
      .finally(function () {
        btn.disabled = false;
        btnText.textContent = 'Start Free Trial';
        btnSpinner.style.display = 'none';
      });
    });

    function showMessage(text, type) {
      message.textContent = text;
      message.className = 'cta-message ' + type;
      message.style.display = 'block';
    }
  }

  // ── Initialize everything on DOM ready ───────────────────────────
  document.addEventListener('DOMContentLoaded', function () {
    initScrollAnimations();
    initSmoothScroll();
    initNavHighlight();
    initWaveform();
    initNavbarScroll();
    initCardTilt();
    initSignupForm();
  });
})();
