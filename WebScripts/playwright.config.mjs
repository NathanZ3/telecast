import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './test',
  testMatch: /.*\.spec\.mjs/,
  timeout: 30_000,
  retries: 0,
  reporter: [['list']],
  projects: [
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],
});
