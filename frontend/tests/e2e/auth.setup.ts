import { test as setup, expect } from '@playwright/test';
import * as path from 'path';

/**
 * Authentication setup for E2E tests
 *
 * This setup file runs before all tests and creates an authenticated state
 * that can be reused across all test files. It uses a test authentication
 * endpoint that generates valid JWT tokens for testing.
 *
 * The /api/test/login endpoint is only enabled in development/test environments
 * and should never be deployed to production.
 */

const authFile = path.join(__dirname, '../../.auth/user.json');

setup('authenticate', async ({ page, request }) => {
  // Call the test authentication endpoint to get valid JWT tokens
  // This endpoint generates real JWT tokens signed with the same secret key
  const response = await request.post('http://localhost:8000/api/test/login');

  expect(response.ok()).toBeTruthy();

  const authData = await response.json();

  // Navigate to the landing page
  await page.goto('/');

  // Set tokens in localStorage (same as what AuthContext.login() does)
  await page.evaluate(({ accessToken, refreshToken }) => {
    localStorage.setItem('access_token', accessToken);
    localStorage.setItem('refresh_token', refreshToken);
  }, {
    accessToken: authData.access_token,
    refreshToken: authData.refresh_token
  });

  // Verify authentication worked by navigating to protected route
  await page.goto('/transactions');

  // Wait for the page to load
  await page.waitForLoadState('networkidle');

  // Wait for table to appear (indicates successful authentication)
  await expect(page.locator('table')).toBeVisible({ timeout: 10000 });

  // Save authentication state to file for reuse in other tests
  await page.context().storageState({ path: authFile });
});
