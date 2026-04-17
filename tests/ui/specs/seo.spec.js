// @ts-check
const { test, expect } = require('@playwright/test');

// Block external CDN requests
test.beforeEach(async ({ page }) => {
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ status: 200, body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ status: 200, body: '' }));
});

test.describe('SEO metadata', () => {
  test('og:title is present and non-empty', async ({ page }) => {
    await page.goto('/');
    const val = await page.locator('meta[property="og:title"]').getAttribute('content');
    expect(val).toBeTruthy();
    expect(val.length).toBeGreaterThan(0);
  });

  test('og:description is present and non-empty', async ({ page }) => {
    await page.goto('/');
    const val = await page.locator('meta[property="og:description"]').getAttribute('content');
    expect(val).toBeTruthy();
    expect(val.length).toBeGreaterThan(0);
  });

  test('og:image is present and points to production domain', async ({ page }) => {
    await page.goto('/');
    const val = await page.locator('meta[property="og:image"]').getAttribute('content');
    expect(val).toMatch(/speechy\.frkn\.com\.tr/);
  });

  test('og:url is present and points to production domain', async ({ page }) => {
    await page.goto('/');
    const val = await page.locator('meta[property="og:url"]').getAttribute('content');
    expect(val).toMatch(/speechy\.frkn\.com\.tr/);
  });

  test('twitter:card is present', async ({ page }) => {
    await page.goto('/');
    const val = await page.locator('meta[name="twitter:card"]').getAttribute('content');
    expect(val).toBeTruthy();
  });

  test('twitter:title is present and non-empty', async ({ page }) => {
    await page.goto('/');
    const val = await page.locator('meta[name="twitter:title"]').getAttribute('content');
    expect(val).toBeTruthy();
    expect(val.length).toBeGreaterThan(0);
  });

  test('twitter:image is present', async ({ page }) => {
    await page.goto('/');
    const val = await page.locator('meta[name="twitter:image"]').getAttribute('content');
    expect(val).toBeTruthy();
  });

  test('canonical link points to production domain', async ({ page }) => {
    await page.goto('/');
    const href = await page.locator('link[rel="canonical"]').getAttribute('href');
    expect(href).toMatch(/^https:\/\/speechy\.frkn\.com\.tr\/?$/);
  });

  test('robots.txt returns 200 and references sitemap', async ({ page }) => {
    const response = await page.goto('/robots.txt');
    expect(response.status()).toBe(200);
    const body = await page.content();
    // page.content() wraps plain text in html; check raw text instead
    const text = await response.text();
    expect(text).toContain('Sitemap:');
    expect(text).toContain('speechy.frkn.com.tr');
  });

  test('sitemap.xml returns 200 and contains at least one <url>', async ({ page }) => {
    const response = await page.goto('/sitemap.xml');
    expect(response.status()).toBe(200);
    const text = await response.text();
    // Must be valid-ish XML and contain URL entries
    expect(text).toContain('<?xml');
    expect(text).toContain('<url>');
    expect(text).toContain('<loc>');
  });

  test('site.webmanifest returns 200 and is valid JSON', async ({ page }) => {
    const response = await page.goto('/site.webmanifest');
    expect(response.status()).toBe(200);
    const text = await response.text();
    const parsed = JSON.parse(text); // throws if invalid JSON
    expect(parsed.name).toBeTruthy();
  });

  const favicons = [
    'favicon-16x16.png',
    'favicon-32x32.png',
    'favicon-48x48.png',
    'apple-touch-icon.png',
    'android-chrome-192x192.png',
    'android-chrome-512x512.png',
  ];

  for (const favicon of favicons) {
    test(`favicon ${favicon} is reachable (200)`, async ({ page }) => {
      const response = await page.goto(`/${favicon}`);
      expect(response.status()).toBe(200);
    });
  }
});
