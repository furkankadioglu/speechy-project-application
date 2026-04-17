# Landing Page UI Tests — Playwright E2E Suite

## Overview

55-test Playwright suite covering the Speechy landing page (`landing/`). All tests
run against a local `python3 -m http.server` on port 8766. No production network
calls are made — external requests (Google Fonts, API) are either mocked or blocked.

## File Layout

```
tests/ui/
├── run.sh                  # Entry point — starts server, installs, runs, tears down
├── package.json            # @playwright/test only
├── package-lock.json
├── playwright.config.js    # Chromium only, baseURL from SPEECHY_TEST_UI_BASE
├── .gitignore              # node_modules/, playwright-report/, test-results/
├── README.md               # User guide, debug instructions
└── specs/
    ├── smoke.spec.js       # 8 tests — HTTP 200, title, description, h1, no errors, no 404s
    ├── seo.spec.js         # 15 tests — OG, Twitter, canonical, robots, sitemap, webmanifest, 6 favicons
    ├── nav.spec.js         # 7 tests — header anchors, footer links, mobile toggle
    ├── signup.spec.js      # 7 tests — form presence, validation, CAPTCHA, mocked API responses
    ├── responsive.spec.js  # 8 tests — 375px/768px viewports, reduced-motion, alt attrs, gradient text
    └── policy.spec.js      # 8 tests — privacy.html, terms.html, back-links
```

## Running

```bash
bash tests/ui/run.sh
```

Total runtime: ~6 seconds locally.

## Key Implementation Notes

### CAPTCHA bypass
The signup form has a client-side math CAPTCHA. Tests read the question from
`#captcha-question`, evaluate it, and fill the correct answer programmatically.

### API mocking
All `/api/signup` calls use `page.route('**/api/signup', ...)` to return synthetic
200/409/429 responses. The production server is never contacted.

### Font CDN blocking
`https://fonts.googleapis.com/**` and `https://fonts.gstatic.com/**` are
intercepted in `beforeEach` and fulfilled with empty 200 responses.

### Static server choice
`python3 -m http.server` was chosen because Python 3 ships with macOS and
requires no npm install step. Port 8766 is defined in `tests/.env.test`.

## Findings During Test Writing

- `terms.html` has two `a[href="privacy.html"]` links (inline + footer). Playwright
  strict mode fails if a locator matches multiple elements — used `.first()` to fix.
- CSS gradient text (`-webkit-background-clip: text`) computes `background-image: none`
  in headless Chrome even when the stylesheet declares a gradient. The
  `webkitTextFillColor` property returns the resolved color (`rgb(255, 255, 255)`)
  rather than transparent in headless mode. Test was adapted to verify any non-empty
  color is present rather than asserting a specific value.
