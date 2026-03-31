/* ============================================
   Speechy Landing Page — Cinematic Interactions
   ============================================ */

(function () {
  'use strict';

  // ── Animated SVG Waveform (Hero Background) ─────────────────────
  function initWaveform() {
    var svg = document.getElementById('waveform-svg');
    if (!svg) return;

    var ns = 'http://www.w3.org/2000/svg';

    // Wave configurations
    var waves = [
      { color: '#007AFF', opacity: 0.25, speed: 0.0008, amplitude: 60, frequency: 0.003, yOffset: 0.55, strokeWidth: 2 },
      { color: '#AF52DE', opacity: 0.18, speed: 0.0012, amplitude: 45, frequency: 0.004, yOffset: 0.50, strokeWidth: 1.8 },
      { color: '#58A6FF', opacity: 0.12, speed: 0.0018, amplitude: 30, frequency: 0.005, yOffset: 0.60, strokeWidth: 1.5 },
      { color: '#ffffff', opacity: 0.04, speed: 0.0006, amplitude: 70, frequency: 0.002, yOffset: 0.48, strokeWidth: 2.5 },
      { color: '#007AFF', opacity: 0.10, speed: 0.001, amplitude: 35, frequency: 0.006, yOffset: 0.65, strokeWidth: 1.2 },
      { color: '#AF52DE', opacity: 0.08, speed: 0.0015, amplitude: 25, frequency: 0.007, yOffset: 0.58, strokeWidth: 1 },
    ];

    // Create path elements for each wave
    var paths = [];
    waves.forEach(function (w) {
      var path = document.createElementNS(ns, 'path');
      path.setAttribute('fill', 'none');
      path.setAttribute('stroke', w.color);
      path.setAttribute('stroke-opacity', w.opacity);
      path.setAttribute('stroke-width', w.strokeWidth);
      path.setAttribute('stroke-linecap', 'round');
      svg.appendChild(path);
      paths.push(path);
    });

    // Also create filled semi-transparent versions for the first two waves
    var fills = [];
    for (var fi = 0; fi < 2; fi++) {
      var fillPath = document.createElementNS(ns, 'path');
      fillPath.setAttribute('fill', waves[fi].color);
      fillPath.setAttribute('fill-opacity', waves[fi].opacity * 0.15);
      fillPath.setAttribute('stroke', 'none');
      svg.insertBefore(fillPath, svg.firstChild);
      fills.push({ path: fillPath, waveIndex: fi });
    }

    function animateWaves(time) {
      var rect = svg.getBoundingClientRect();
      var w = rect.width || 1200;
      var h = rect.height || 500;

      svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);

      var step = 4; // pixels between points

      waves.forEach(function (wave, idx) {
        var points = [];
        for (var x = 0; x <= w; x += step) {
          var normalizedX = x / w;
          var y = h * wave.yOffset
            + Math.sin(x * wave.frequency + time * wave.speed) * wave.amplitude
            + Math.sin(x * wave.frequency * 0.5 + time * wave.speed * 1.3) * wave.amplitude * 0.4
            + Math.sin(x * wave.frequency * 2 + time * wave.speed * 0.7) * wave.amplitude * 0.15;
          points.push(x + ',' + y.toFixed(1));
        }

        var d = 'M' + points.join(' L');
        paths[idx].setAttribute('d', d);

        // Fill paths for first two waves
        fills.forEach(function (f) {
          if (f.waveIndex === idx) {
            f.path.setAttribute('d', d + ' L' + w + ',' + h + ' L0,' + h + ' Z');
          }
        });
      });

      requestAnimationFrame(animateWaves);
    }

    requestAnimationFrame(animateWaves);
  }

  // ── Floating Particles ──────────────────────────────────────────
  function initParticles() {
    var canvas = document.getElementById('particles-canvas');
    if (!canvas) return;

    var ctx = canvas.getContext('2d');
    var particles = [];
    var particleCount = 40;

    function resize() {
      canvas.width = canvas.offsetWidth;
      canvas.height = canvas.offsetHeight;
    }

    resize();
    window.addEventListener('resize', resize);

    // Create particles
    for (var i = 0; i < particleCount; i++) {
      particles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        size: Math.random() * 1.5 + 0.5,
        speedX: (Math.random() - 0.5) * 0.15,
        speedY: -Math.random() * 0.3 - 0.05,
        opacity: Math.random() * 0.25 + 0.05,
      });
    }

    function animateParticles() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      particles.forEach(function (p) {
        p.x += p.speedX;
        p.y += p.speedY;

        // Wrap around
        if (p.y < -10) {
          p.y = canvas.height + 10;
          p.x = Math.random() * canvas.width;
        }
        if (p.x < -10) p.x = canvas.width + 10;
        if (p.x > canvas.width + 10) p.x = -10;

        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(255, 255, 255, ' + p.opacity + ')';
        ctx.fill();
      });

      requestAnimationFrame(animateParticles);
    }

    animateParticles();
  }

  // ── Scroll-triggered fade-in animations ─────────────────────────
  function initScrollAnimations() {
    var elements = document.querySelectorAll('.fade-in');
    if (!elements.length) return;

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          // Support data-delay for staggered animations
          var delay = entry.target.getAttribute('data-delay');
          if (delay) {
            setTimeout(function () {
              entry.target.classList.add('visible');
            }, parseInt(delay, 10));
          } else {
            entry.target.classList.add('visible');
          }
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

  // ── Smooth scroll for anchor links ──────────────────────────────
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

        // Close mobile menu if open
        var mobileMenu = document.getElementById('nav-mobile-menu');
        var toggle = document.getElementById('nav-toggle');
        if (mobileMenu && mobileMenu.classList.contains('open')) {
          mobileMenu.classList.remove('open');
          toggle.classList.remove('active');
        }
      });
    });
  }

  // ── Navbar scroll effect ────────────────────────────────────────
  function initNavbarScroll() {
    var navbar = document.getElementById('navbar');
    if (!navbar) return;

    function checkScroll() {
      if (window.scrollY > 30) {
        navbar.classList.add('scrolled');
      } else {
        navbar.classList.remove('scrolled');
      }
    }

    checkScroll();
    window.addEventListener('scroll', checkScroll, { passive: true });
  }

  // ── Mobile navigation toggle ────────────────────────────────────
  function initMobileNav() {
    var toggle = document.getElementById('nav-toggle');
    var menu = document.getElementById('nav-mobile-menu');
    if (!toggle || !menu) return;

    toggle.addEventListener('click', function () {
      toggle.classList.toggle('active');
      menu.classList.toggle('open');
    });
  }

  // ── Active nav link highlighting ────────────────────────────────
  function initNavHighlight() {
    var sections = document.querySelectorAll('section[id]');
    var navLinks = document.querySelectorAll('.nav-links a');
    if (!sections.length || !navLinks.length) return;

    window.addEventListener('scroll', function () {
      var scrollY = window.pageYOffset;
      var navHeight = document.querySelector('.navbar').offsetHeight;

      sections.forEach(function (section) {
        var top = section.offsetTop - navHeight - 100;
        var bottom = top + section.offsetHeight;
        var id = section.getAttribute('id');

        if (scrollY >= top && scrollY < bottom) {
          navLinks.forEach(function (link) {
            link.style.color = '';
            if (link.getAttribute('href') === '#' + id) {
              link.style.color = '#007AFF';
            }
          });
        }
      });
    }, { passive: true });
  }

  // ── CAPTCHA ─────────────────────────────────────────────────────
  var captchaAnswer = 0;

  function generateCaptcha() {
    var ops = [
      function () { var a = rand(2, 15), b = rand(1, 10); return { q: a + ' + ' + b, a: a + b }; },
      function () { var a = rand(10, 25), b = rand(1, a - 1); return { q: a + ' \u2212 ' + b, a: a - b }; },
      function () { var a = rand(2, 9), b = rand(2, 6); return { q: a + ' \u00d7 ' + b, a: a * b }; },
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

  // ── Email signup form ───────────────────────────────────────────
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

  // ── Language picker dropdown ─────────────────────────────────────
  function initLangPicker() {
    var btn = document.getElementById('lang-picker-btn');
    var dropdown = document.getElementById('lang-dropdown');
    if (!btn || !dropdown) return;

    function open() {
      dropdown.classList.add('open');
      btn.setAttribute('aria-expanded', 'true');
    }

    function close() {
      dropdown.classList.remove('open');
      btn.setAttribute('aria-expanded', 'false');
    }

    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      if (dropdown.classList.contains('open')) { close(); } else { open(); }
    });

    // Close when clicking outside
    document.addEventListener('click', function (e) {
      if (!btn.contains(e.target) && !dropdown.contains(e.target)) {
        close();
      }
    });

    // Close on Escape
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') close();
    });

    // Close when a language is selected
    dropdown.addEventListener('click', function (e) {
      var target = e.target.closest('.lb-btn');
      if (target) { close(); }
    });
  }

  // ── Initialize everything on DOM ready ──────────────────────────
  document.addEventListener('DOMContentLoaded', function () {
    initWaveform();
    initParticles();
    initScrollAnimations();
    initSmoothScroll();
    initNavbarScroll();
    initMobileNav();
    initNavHighlight();
    initSignupForm();
    initLangPicker();
  });
})();
