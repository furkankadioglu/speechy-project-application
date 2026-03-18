# Landing Page Redesign — Cinematic Dark Theme

## Date
2026-03-18

## Summary
Complete rewrite of the Speechy landing page (index.html, style.css, script.js) with a cinematic, dark, minimal design inspired by Wispr Flow and Aqua Voice.

## Design System
- **Background**: Deep navy-to-black gradient (#0a0a14 -> #0d0f1a -> #111328)
- **Primary accent**: Blue #007AFF
- **Secondary accent**: Purple #AF52DE
- **Typography**: Inter font from Google Fonts (weights 300-900)
- **Cards**: Glassmorphism with backdrop-filter blur and subtle borders

## Page Sections
1. **Navigation** — Fixed, transparent-to-solid on scroll, with "Try Free" gradient CTA
2. **Hero** — Full viewport with animated SVG waveforms, floating particles, gradient orbs, stats (29 Languages / ~3s Processing / $0 Cloud Cost), Download CTA
3. **How it Works** — 3 horizontal steps (Press, Speak, Done) with connecting arrows
4. **Features** — 3 glassmorphism cards (Private, Fast, Customizable)
5. **CTA Signup** — Email form with math CAPTCHA, API integration to speechy.frkn.com.tr preserved
6. **Footer** — Minimal with Terms/Privacy links

## Visual Effects
- **Animated Waveform**: 6 layered sine waves (blue, purple, cyan, white) animated via requestAnimationFrame, covering lower 60% of hero
- **Particles**: 40 floating dots with slow upward drift on canvas
- **Gradient Orbs**: 3 blurred animated circles for ambient depth
- **Scroll Animations**: IntersectionObserver-based fade-in with staggered delays
- **Glassmorphism**: backdrop-filter blur + semi-transparent backgrounds + subtle borders

## API Integration Preserved
The signup form continues to POST to `https://speechy.frkn.com.tr/api/signup` with the same CAPTCHA validation logic (math problems: addition, subtraction, multiplication).

## Files Modified
- `landing/index.html` — Complete rewrite
- `landing/style.css` — Complete rewrite
- `landing/script.js` — Complete rewrite

## Deployment
Deployed via rsync to production server (185.106.208.55), excluding terms.html and privacy.html.
