// @ts-check
const { test, expect } = require('@playwright/test');

// Block external CDN requests
test.beforeEach(async ({ page }) => {
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ status: 200, body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ status: 200, body: '' }));
});

test.describe('Policy pages', () => {
  test('/privacy.html loads with status 200', async ({ page }) => {
    const response = await page.goto('/privacy.html');
    expect(response.status()).toBe(200);
  });

  test('/privacy.html has <h1> containing "Privacy"', async ({ page }) => {
    await page.goto('/privacy.html');
    const h1 = page.locator('h1');
    await expect(h1).toContainText('Privacy');
  });

  test('/privacy.html links back to index.html', async ({ page }) => {
    await page.goto('/privacy.html');
    // Both the nav logo and the "Back to Home" link point to index.html
    const backLink = page.locator('a[href="index.html"]').first();
    await expect(backLink).toBeVisible();
  });

  test('/terms.html loads with status 200', async ({ page }) => {
    const response = await page.goto('/terms.html');
    expect(response.status()).toBe(200);
  });

  test('/terms.html has <h1> containing "Terms"', async ({ page }) => {
    await page.goto('/terms.html');
    const h1 = page.locator('h1');
    await expect(h1).toContainText('Terms');
  });

  test('/terms.html links back to index.html', async ({ page }) => {
    await page.goto('/terms.html');
    const backLink = page.locator('a[href="index.html"]').first();
    await expect(backLink).toBeVisible();
  });

  test('privacy.html footer contains Terms link', async ({ page }) => {
    await page.goto('/privacy.html');
    const termsLink = page.locator('a[href="terms.html"]');
    await expect(termsLink).toBeAttached();
  });

  test('terms.html contains at least one Privacy link', async ({ page }) => {
    await page.goto('/terms.html');
    // terms.html has multiple privacy.html links (footer + inline); use first()
    const privacyLink = page.locator('a[href="privacy.html"]').first();
    await expect(privacyLink).toBeAttached();
  });
});
