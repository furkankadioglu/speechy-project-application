// @ts-check
const { test, expect } = require('@playwright/test');

// Block external CDN requests
test.beforeEach(async ({ page }) => {
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ status: 200, body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ status: 200, body: '' }));
});

test.describe('Navigation', () => {
  // Header nav links: #features, #how-it-works, #privacy (footer id)
  const headerNavLinks = [
    { text: 'Features', href: '#features', targetId: 'features' },
    { text: 'How it Works', href: '#how-it-works', targetId: 'how-it-works' },
    { text: 'Privacy', href: '#privacy', targetId: 'privacy' },
  ];

  for (const link of headerNavLinks) {
    test(`nav link "${link.text}" anchor target exists on page`, async ({ page }) => {
      await page.goto('/');
      // Verify the nav link exists with correct href
      const navLink = page.locator(`.nav-links a[href="${link.href}"]`);
      await expect(navLink).toBeVisible();
      // Verify the anchor target section/element exists in DOM
      const target = page.locator(`#${link.targetId}`);
      await expect(target).toBeAttached();
    });
  }

  test('"Try Free" nav CTA links to #try-free section', async ({ page }) => {
    await page.goto('/');
    const ctaLink = page.locator('.nav-cta[href="#try-free"]');
    await expect(ctaLink).toBeVisible();
    const tryfreeSection = page.locator('#try-free');
    await expect(tryfreeSection).toBeAttached();
  });

  test('footer links to privacy.html loads with expected heading', async ({ page }) => {
    await page.goto('/');
    // Footer has a direct link to privacy.html (not an anchor)
    const privacyLink = page.locator('.footer-links a[href="privacy.html"]');
    await expect(privacyLink).toBeVisible();

    const [newPage] = await Promise.all([
      page.waitForEvent('load').then(() => page),
      privacyLink.click(),
    ]);

    // After click we stay on same page because it's a normal href
    await page.waitForURL(/privacy\.html/);
    const h1 = page.locator('h1');
    await expect(h1).toContainText('Privacy');
  });

  test('footer link to terms.html loads with expected heading', async ({ page }) => {
    await page.goto('/');
    const termsLink = page.locator('.footer-links a[href="terms.html"]');
    await expect(termsLink).toBeVisible();

    await termsLink.click();
    await page.waitForURL(/terms\.html/);
    const h1 = page.locator('h1');
    await expect(h1).toContainText('Terms');
  });

  test('mobile nav toggle opens mobile menu', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    const toggle = page.locator('#nav-toggle');
    await expect(toggle).toBeVisible();
    await toggle.click();
    const mobileMenu = page.locator('#nav-mobile-menu');
    await expect(mobileMenu).toHaveClass(/open/);
  });
});
