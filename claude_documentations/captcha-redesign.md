# CAPTCHA Redesign — Landing Page

## Date
2026-03-14

## Problem
The CAPTCHA on the signup form was nearly invisible on the dark landing page background. The input field had no visible border/background, the label used `--text-muted` which was too dim, and the overall layout felt like a bolt-on element rather than part of the form.

## Changes Made

### `landing/style.css`
- **`.captcha-box`**: Changed from `rgba(255,255,255,0.04)` background to `rgba(168,85,247,0.06)` (subtle purple tint). Added stronger border (`rgba(168,85,247,0.25)`), full width, and `focus-within` state with purple glow.
- **`.captcha-label`**: Upgraded from `--text-muted` to `--text-secondary` for readability. Added `font-weight: 500`.
- **`.captcha-question`**: Applied blue-to-purple gradient text (matching the hero title treatment). Increased size to `1.1rem` with better monospace font stack.
- **`.captcha-box input`**: Visible purple-tinted border (`1.5px`), brighter background (`rgba(255,255,255,0.08)`), proper focus state with ring shadow, placeholder styling.
- **Error state**: Added red background tint and red ring shadow alongside the shake animation.
- **Responsive**: Added mobile-specific sizing within the `@media (max-width: 768px)` block.

### `landing/index.html`
- Changed label text from "Verify:" to "Quick check:" (friendlier).
- Added `aria-label="CAPTCHA answer"` for accessibility.

### `landing/script.js`
- No changes needed — the JS logic was already correct.

## Deployment
Deployed via rsync to `speechy.frkn.com.tr`.
