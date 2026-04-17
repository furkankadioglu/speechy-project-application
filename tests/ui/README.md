# Speechy UI Tests — Playwright E2E

End-to-end tests for the Speechy landing page (`landing/`), run locally against a
`python3 -m http.server` instance on port 8766.

## Prerequisites

- **Node.js 18+** — `node --version`
- **npm** — bundled with Node
- **Python 3** — ships with macOS 12+ (used as the static file server)
- **curl** — used by `run.sh` to health-check the server (ships with macOS)

## Running

```bash
# From the repo root:
bash tests/ui/run.sh

# Or from tests/ui/:
./run.sh
```

`run.sh` will:
1. Source `tests/.env.test` for shared environment variables.
2. Run `npm ci` if `node_modules/` is missing.
3. Install the Chromium browser via `npx playwright install chromium`.
4. Start a `python3 -m http.server` for `landing/` on port 8766.
5. Wait for the server (up to 20 s) then run `npx playwright test`.
6. Kill the server on exit.

## Why `python3 -m http.server`?

Python 3 ships with macOS and requires no additional npm packages. It correctly
serves the static HTML/CSS/JS/images with appropriate MIME types. `npx serve`
was considered but adds a download step on first use and requires npm.

## Debug / UI mode

```bash
cd tests/ui
npx playwright test --ui          # opens the interactive Playwright UI
npx playwright test --headed      # runs with a visible browser
npx playwright test --debug       # step-through debugger
npx playwright show-report        # open the last HTML report
```

## Spec files

| File | What it tests |
|------|---------------|
| `specs/smoke.spec.js` | HTTP 200, title, meta description, h1 visible, no console errors, no 404s |
| `specs/seo.spec.js` | OG tags, Twitter card, canonical URL, robots.txt, sitemap.xml, webmanifest, all favicons |
| `specs/nav.spec.js` | Header nav anchors exist on page, footer links to privacy/terms work, mobile menu toggle |
| `specs/signup.spec.js` | Form present, empty/invalid email validation, CAPTCHA validation, mocked success/429/409 API responses |
| `specs/responsive.spec.js` | 375px no overflow, hero visible on mobile/tablet, reduced-motion, all images have alt, gradient text color |
| `specs/policy.spec.js` | privacy.html and terms.html load, h1 content, back-links to index |

## Environment variables

All defined in `tests/.env.test`:

| Variable | Default | Notes |
|----------|---------|-------|
| `SPEECHY_TEST_UI_BASE` | `http://127.0.0.1:8766` | Base URL for Playwright |
| `SPEECHY_TEST_UI_PORT` | `8766` | Port for the static server |

## Caveats

- **External requests are mocked** — Google Fonts (`fonts.googleapis.com`,
  `fonts.gstatic.com`) are intercepted and fulfilled with empty 200 responses so
  tests never hit the internet.
- **CAPTCHA bypass** — The signup form has a client-side math CAPTCHA. The
  signup tests read the displayed question from the DOM, evaluate it, and fill
  the correct answer. This is intentional — the CAPTCHA is server-verified on
  real submissions but the client-side check is what gates the fetch call.
- **API calls are always mocked** — `page.route('**/api/signup', ...)` is used
  so no real requests reach `speechy.frkn.com.tr`.
- Reports are written to `tests/ui/playwright-report/` (gitignored).
