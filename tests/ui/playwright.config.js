// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './specs',

  // Base URL sourced from shared env — set before running
  use: {
    baseURL: process.env.SPEECHY_TEST_UI_BASE || 'http://127.0.0.1:8766',
    // Block all external network requests so tests never hit production or CDNs
    extraHTTPHeaders: {},
  },

  // Run tests in parallel within a file
  fullyParallel: true,

  // Retry once on CI, zero locally
  retries: process.env.CI ? 1 : 0,

  // Workers: 1 on CI to keep logs clean, unrestricted locally
  workers: process.env.CI ? 1 : undefined,

  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
