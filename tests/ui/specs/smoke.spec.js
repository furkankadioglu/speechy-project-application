// @ts-check
const { test, expect } = require('@playwright/test');

// Block external CDN requests (Google Fonts etc.) to avoid flakes
test.beforeEach(async ({ page }) => {
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ status: 200, body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ status: 200, body: '' }));
});

test.describe('Smoke — basic page sanity', () => {
  test('homepage returns 200', async ({ page }) => {
    const response = await page.goto('/');
    expect(response.status()).toBe(200);
  });

  test('page title includes "Speechy"', async ({ page }) => {
    await page.goto('/');
    const title = await page.title();
    expect(title).toContain('Speechy');
  });

  test('meta description is present and non-empty', async ({ page }) => {
    await page.goto('/');
    const description = await page.locator('meta[name="description"]').getAttribute('content');
    expect(description).toBeTruthy();
    expect(description.length).toBeGreaterThan(10);
  });

  test('main hero h1 heading is visible', async ({ page }) => {
    await page.goto('/');
    const h1 = page.locator('h1.hero-title');
    await expect(h1).toBeVisible();
  });

  test('no console errors on page load', async ({ page }) => {
    const errors = [];
    page.on('console', msg => {
      if (msg.type() === 'error') errors.push(msg.text());
    });
    await page.goto('/');
    // Allow short settle time for JS to run
    await page.waitForTimeout(500);
    expect(errors).toHaveLength(0);
  });

  test('all local resources load without 404', async ({ page }) => {
    const failed = [];
    page.on('response', response => {
      const url = response.url();
      // Only flag local server resources
      if (url.includes('127.0.0.1:8766') && response.status() === 404) {
        failed.push(url);
      }
    });
    await page.goto('/');
    await page.waitForTimeout(500);
    expect(failed).toHaveLength(0);
  });

  test('style.css loads (200)', async ({ page }) => {
    const response = await page.goto('/style.css');
    expect(response.status()).toBe(200);
  });

  test('script.js loads (200)', async ({ page }) => {
    const response = await page.goto('/script.js');
    expect(response.status()).toBe(200);
  });
});
