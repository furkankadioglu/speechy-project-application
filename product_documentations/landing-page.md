# Speechy Landing Page

## Overview
The Speechy landing page is a modern, cinematic dark-themed website at **speechy.frkn.com.tr**. It serves as the main marketing and signup page for the Speechy speech-to-text application.

## Pages

### Homepage (index.html)
- **Hero section**: Animated waveform background with key stats (29 languages, ~3s processing, $0 cloud cost)
- **How it Works**: 3-step guide (Press → Speak → Done)
- **Features**: Privacy-first, lightning fast, fully customizable
- **Language marquee**: Animated display of 18 supported UI languages
- **Signup form**: Email-based free trial signup with CAPTCHA protection
- **Download buttons**: Mac download + Windows "Coming Soon"

### Privacy Policy (privacy.html)
- Comprehensive 18-section privacy policy
- Emphasizes 100% on-device processing

### Terms and Conditions (terms.html)
- 14-section terms covering licensing, usage, and legal terms

## Features
- **18 languages** supported for the interface (EN, TR, DE, FR, ES, IT, PT, NL, PL, RU, UK, ZH, JA, KO, AR, HI, ID, VI)
- Full client-side internationalization (i18n) with localStorage persistence
- RTL support for Arabic
- Responsive design (mobile + desktop)
- CAPTCHA-protected signup form
- Glassmorphism design with animated particles and wave effects

## Signup Flow
1. User enters email
2. Solves math CAPTCHA
3. Form submits to `https://speechy.frkn.com.tr/api/signup`
4. Verification email sent
5. Trial starts after email verification (30 days)
