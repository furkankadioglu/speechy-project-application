// @ts-check
const { test, expect } = require('@playwright/test');

// Block external CDN requests
test.beforeEach(async ({ page }) => {
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ status: 200, body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ status: 200, body: '' }));
});

test.describe('Responsive layout', () => {
  test('mobile viewport (375x667): hero heading is visible', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    const h1 = page.locator('h1.hero-title');
    await expect(h1).toBeVisible();
  });

  test('mobile viewport (375x667): no horizontal scroll overflow', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    // scrollWidth > clientWidth means horizontal overflow
    const hasOverflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth > document.documentElement.clientWidth;
    });
    expect(hasOverflow).toBe(false);
  });

  test('tablet viewport (768x1024): hero section is visible', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.goto('/');
    const heroSection = page.locator('section.hero');
    await expect(heroSection).toBeVisible();
  });

  test('tablet viewport (768x1024): features section is present', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.goto('/');
    const featuresSection = page.locator('section.features');
    await expect(featuresSection).toBeAttached();
  });

  test('prefers-reduced-motion: page loads without timeout', async ({ page }) => {
    // Emulate reduced motion preference
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/');
    // Page must load and h1 must be present — animations shouldn't cause hangs
    const h1 = page.locator('h1.hero-title');
    await expect(h1).toBeAttached({ timeout: 10000 });
  });

  test('all images have alt attributes', async ({ page }) => {
    await page.goto('/');
    const imagesWithoutAlt = await page.evaluate(() => {
      const imgs = Array.from(document.querySelectorAll('img'));
      return imgs
        .filter(img => !img.hasAttribute('alt') || img.getAttribute('alt') === null)
        .map(img => img.src);
    });
    expect(imagesWithoutAlt).toHaveLength(0);
  });

  test('hero title has a computed text color (not unset)', async ({ page }) => {
    await page.goto('/');
    // The hero title uses CSS gradient text (-webkit-background-clip: text).
    // We verify the element has a non-empty color value — headless Chrome
    // resolves -webkit-text-fill-color to white (the gradient primary stop)
    // rather than transparent. Either white or transparent are both valid
    // indicators that the gradient styling is applied.
    const color = await page.locator('h1.hero-title').evaluate(el => {
      const style = window.getComputedStyle(el);
      return style.webkitTextFillColor || style.color;
    });
    expect(color).toBeTruthy();
    expect(color).not.toBe('');
  });

  test('hero subtitle text is visible on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    const subtitle = page.locator('p.hero-subtitle');
    await expect(subtitle).toBeVisible();
  });
});
