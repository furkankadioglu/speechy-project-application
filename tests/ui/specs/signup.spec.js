// @ts-check
/**
 * Signup form tests.
 *
 * The landing page DOES have a signup form (#signup-form) in the #try-free section.
 * It uses:
 *   - Email input (#signup-email)
 *   - CAPTCHA math question (#captcha-question / #captcha-answer)
 *   - Submit button (#signup-btn)
 *   - Message area (#signup-message)
 *
 * The form POSTs to https://speechy.frkn.com.tr/api/signup.
 * All API calls are intercepted with page.route() — no real network calls.
 *
 * CAPTCHA note: The CAPTCHA is a client-side math check. To bypass it in tests we:
 *   1. Read the generated question from the DOM.
 *   2. Evaluate the expression and fill in the correct answer.
 */

const { test, expect } = require('@playwright/test');

// Block external CDN + fonts
test.beforeEach(async ({ page }) => {
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ status: 200, body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ status: 200, body: '' }));
});

/** Helper: solve the captcha question displayed on the page and fill the answer. */
async function solveCaptcha(page) {
  const questionText = await page.locator('#captcha-question').textContent();
  // Format is e.g. "5 + 3 =" or "12 − 4 =" or "3 × 6 ="
  const expr = questionText.replace('=', '').trim()
    .replace('−', '-')   // minus sign
    .replace('×', '*');  // multiplication sign
  // Safe eval of simple arithmetic (only digits and operators)
  if (!/^[\d\s\+\-\*]+$/.test(expr)) throw new Error('Unexpected captcha expr: ' + expr);
  // eslint-disable-next-line no-eval
  const answer = eval(expr);
  await page.locator('#captcha-answer').fill(String(answer));
}

test.describe('Signup form', () => {
  test('form is present on the landing page', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#signup-form')).toBeAttached();
    await expect(page.locator('#signup-email')).toBeVisible();
    await expect(page.locator('#signup-btn')).toBeVisible();
  });

  test('submit with empty email shows error, no network call', async ({ page }) => {
    let apiCalled = false;
    await page.route('**/api/signup', () => { apiCalled = true; });

    await page.goto('/');
    await page.locator('#signup-form').scrollIntoViewIfNeeded();

    // Leave email blank, fill captcha, submit
    await solveCaptcha(page);
    await page.locator('#signup-btn').click();

    const message = page.locator('#signup-message');
    await expect(message).toBeVisible();
    const text = await message.textContent();
    expect(text.toLowerCase()).toContain('valid email');
    expect(apiCalled).toBe(false);
  });

  test('submit with invalid email format shows error, no network call', async ({ page }) => {
    let apiCalled = false;
    await page.route('**/api/signup', () => { apiCalled = true; });

    await page.goto('/');
    await page.locator('#signup-form').scrollIntoViewIfNeeded();
    await page.locator('#signup-email').fill('notanemail');
    await solveCaptcha(page);
    await page.locator('#signup-btn').click();

    const message = page.locator('#signup-message');
    await expect(message).toBeVisible();
    const text = await message.textContent();
    expect(text.toLowerCase()).toContain('valid email');
    expect(apiCalled).toBe(false);
  });

  test('wrong captcha answer shows error message', async ({ page }) => {
    let apiCalled = false;
    await page.route('**/api/signup', () => { apiCalled = true; });

    await page.goto('/');
    await page.locator('#signup-form').scrollIntoViewIfNeeded();
    await page.locator('#signup-email').fill('test@example.com');
    // Deliberately wrong answer
    await page.locator('#captcha-answer').fill('9999');
    await page.locator('#signup-btn').click();

    const message = page.locator('#signup-message');
    await expect(message).toBeVisible();
    const text = await message.textContent();
    expect(text.toLowerCase()).toMatch(/wrong|math|captcha/);
    expect(apiCalled).toBe(false);
  });

  test('valid email + correct captcha → mocked success → success message shown', async ({ page }) => {
    // Intercept and mock the API endpoint
    await page.route('**/api/signup', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ success: true, message: 'Verification email sent.' }),
      });
    });

    await page.goto('/');
    await page.locator('#signup-form').scrollIntoViewIfNeeded();
    await page.locator('#signup-email').fill('tester@example.com');
    await solveCaptcha(page);
    await page.locator('#signup-btn').click();

    const message = page.locator('#signup-message');
    await expect(message).toBeVisible();
    const text = await message.textContent();
    expect(text.toLowerCase()).toContain('tester@example.com');
  });

  test('mocked 429 response → rate limiting error shown', async ({ page }) => {
    await page.route('**/api/signup', async route => {
      await route.fulfill({
        status: 429,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Too many requests. Please try again later.' }),
      });
    });

    await page.goto('/');
    await page.locator('#signup-form').scrollIntoViewIfNeeded();
    await page.locator('#signup-email').fill('ratelimited@example.com');
    await solveCaptcha(page);
    await page.locator('#signup-btn').click();

    const message = page.locator('#signup-message');
    await expect(message).toBeVisible();
    const text = await message.textContent();
    // The script shows result.data.error for non-ok responses
    expect(text).toBeTruthy();
    expect(text.length).toBeGreaterThan(0);
  });

  test('mocked 409 "trial already exists" → appropriate message shown', async ({ page }) => {
    await page.route('**/api/signup', async route => {
      await route.fulfill({
        status: 409,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'A trial for this email already exists.' }),
      });
    });

    await page.goto('/');
    await page.locator('#signup-form').scrollIntoViewIfNeeded();
    await page.locator('#signup-email').fill('existing@example.com');
    await solveCaptcha(page);
    await page.locator('#signup-btn').click();

    const message = page.locator('#signup-message');
    await expect(message).toBeVisible();
    const text = await message.textContent();
    expect(text).toBeTruthy();
    expect(text.length).toBeGreaterThan(0);
  });
});
