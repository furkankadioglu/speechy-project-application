# Pitch Deck PDF Rendering Fix

## Date
2026-03-14

## Problem
The investor pitch deck PDF (generated via Chrome headless from HTML) had rendering artifacts when viewed in macOS Preview:
- White/colored rectangular patches over text
- Strips and boxes appearing over content areas

## Root Cause
Three CSS patterns that Chrome's PDF renderer handles poorly:

1. **`-webkit-background-clip: text` + `-webkit-text-fill-color: transparent`** — Creates white rectangles in PDF renderers where the clipped background should show through text
2. **`::before` pseudo-elements with large `radial-gradient` overlays** — Oversized (200%) positioned elements with semi-transparent gradients cause rendering artifacts
3. **`rgba()` transparency on backgrounds** — Semi-transparent colors blend incorrectly in PDF output

## Fix Applied
All instances were replaced with PDF-safe alternatives:

### Gradient text → Solid colors
- Cover heading (`h1`): `#ffffff` (white)
- Cover stats (`.cover-stat .num`): `#58A6FF` (cyan)
- Page headings (`.ph h2`): `#007AFF` (blue)
- Stat boxes (`.sb .v`): `#007AFF` (blue)
- CTA heading (`.cta-in h2`): `#ffffff` (white)
- CTA value boxes (`.cb .v`): `#007AFF` (blue)

### Pseudo-element overlays → Removed
- `.cover::before`: `display: none`
- `.cta::before`: `display: none`

### `rgba()` backgrounds → Solid hex equivalents
All `rgba()` values were converted to solid hex colors that visually approximate the original transparency against the dark background (#0D1117):
- Card backgrounds: `#171B22`
- Card borders: `#21262D`
- Problem cards: `#1A1214` with border `#3D1A18`
- Solution cards: `#121A14` with border `#1A3D1E`
- Tag backgrounds: various dark tints
- Stat box backgrounds: various dark tints
- Bar chart gradients: solid dark-to-light gradients

## Files Modified
- `investor-pitch/pitch-deck.html` — All CSS fixes applied
- `investor-pitch/Speechy-Investor-Pitch-Deck.pdf` — Regenerated via Chrome headless
