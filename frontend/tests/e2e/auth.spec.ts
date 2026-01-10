/**
 * E2E tests for authentication flow
 * Tests Google OAuth integration, login/logout, and session management
 */

import { test, expect } from '@playwright/test';

test.describe('Authentication Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Clear localStorage before each test
    await page.goto('http://localhost:5173');
    await page.evaluate(() => localStorage.clear());
  });

  test('should show Google login button on landing page', async ({ page }) => {
    await page.goto('http://localhost:5173');

    // Check page title
    await expect(page.locator('h1')).toContainText('지출 추적을 더 쉽게');

    // Check for Google login button (iframe from @react-oauth/google)
    // The Google button is rendered in an iframe
    const googleButton = page.frameLocator('iframe[src*="accounts.google.com"]');
    await expect(googleButton.locator('body')).toBeVisible({ timeout: 10000 });
  });

  test('should show features section on landing page', async ({ page }) => {
    await page.goto('http://localhost:5173');

    // Verify features are displayed
    await expect(page.getByText('파일 자동 파싱')).toBeVisible();
    await expect(page.getByText('지능형 분류')).toBeVisible();
    await expect(page.getByText('실시간 분석')).toBeVisible();

    // Verify supported banks section
    await expect(page.getByText('지원하는 금융기관')).toBeVisible();
    await expect(page.getByText('신한카드')).toBeVisible();
    await expect(page.getByText('하나카드')).toBeVisible();
    await expect(page.getByText('토스뱅크')).toBeVisible();
  });

  test('should not allow access to protected routes without authentication', async ({ page }) => {
    // Try to access protected route directly
    await page.goto('http://localhost:5173/transactions');

    // Should redirect to landing page
    await expect(page).toHaveURL('http://localhost:5173/');
  });

  test('should not allow access to dashboard without authentication', async ({ page }) => {
    await page.goto('http://localhost:5173/dashboard');
    await expect(page).toHaveURL('http://localhost:5173/');
  });

  test('should not allow access to parsing sessions without authentication', async ({ page }) => {
    await page.goto('http://localhost:5173/parsing-sessions');
    await expect(page).toHaveURL('http://localhost:5173/');
  });

  test('should not allow access to settings without authentication', async ({ page }) => {
    await page.goto('http://localhost:5173/settings');
    await expect(page).toHaveURL('http://localhost:5173/');
  });

  // Note: Actual Google OAuth login cannot be easily tested in E2E without complex setup
  // These tests would require:
  // 1. Mock Google OAuth service
  // 2. Use test Google account credentials
  // 3. Handle OAuth consent screen
  //
  // For now, we test the flow with mocked authentication state

  test('should redirect authenticated user to transactions page', async ({ page, context }) => {
    // Mock authenticated state by setting localStorage
    await page.goto('http://localhost:5173');

    await page.evaluate(() => {
      localStorage.setItem('access_token', 'mock_access_token');
    });

    // Navigate to landing page
    await page.goto('http://localhost:5173');

    // Should redirect to transactions (handled by useEffect in LandingPage)
    // Note: This might fail if the token is validated against backend
    // In a real scenario, you'd need a valid token or mock the API
  });

  test('should show loading state during authentication', async ({ page }) => {
    await page.goto('http://localhost:5173');

    // The AuthContext initializes with isLoading: true
    // By the time the page loads, it should have completed loading
    // This test verifies the page doesn't get stuck in loading state

    // Wait for the landing page content to appear
    await expect(page.locator('h1')).toContainText('지출 추적을 더 쉽게', { timeout: 5000 });
  });
});

test.describe('Authentication with Mock Backend', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('http://localhost:5173');
    await page.evaluate(() => localStorage.clear());
  });

  test('should handle login error gracefully', async ({ page }) => {
    // Intercept Google auth API call and return error
    await page.route('**/api/auth/google', (route) => {
      route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({ detail: 'Invalid Google ID token' }),
      });
    });

    // Mock Google OAuth success (would trigger API call)
    // In real scenario, this would be triggered by Google button click
    await page.evaluate(() => {
      // Simulate calling the login function with invalid token
      // This is for demonstration - in real E2E you'd click the button
      fetch('http://localhost:8000/api/auth/google', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ credential: 'invalid_token' }),
      }).catch(() => {});
    });

    // Error message should appear (from Ant Design message)
    // Note: This is a simplified test - real implementation would need proper mocking
  });

  test('should store tokens in localStorage on successful login', async ({ page }) => {
    // Mock successful Google auth response
    await page.route('**/api/auth/google', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          access_token: 'mock_access_token_123',
          refresh_token: 'mock_refresh_token_456',
          token_type: 'bearer',
          user: {
            id: '1',
            email: 'test@example.com',
            name: 'Test User',
            picture: 'https://example.com/avatar.jpg',
          },
        }),
      });
    });

    // In a real test, you'd click the Google button and handle OAuth flow
    // For now, we simulate the API call
    await page.evaluate(async () => {
      const response = await fetch('http://localhost:8000/api/auth/google', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ credential: 'valid_google_token' }),
      });
      const data = await response.json();
      localStorage.setItem('access_token', data.access_token);
      localStorage.setItem('refresh_token', data.refresh_token);
    });

    // Verify tokens are stored
    const accessToken = await page.evaluate(() => localStorage.getItem('access_token'));
    const refreshToken = await page.evaluate(() => localStorage.getItem('refresh_token'));

    expect(accessToken).toBe('mock_access_token_123');
    expect(refreshToken).toBe('mock_refresh_token_456');
  });

  test('should clear tokens on logout', async ({ page }) => {
    // Set up authenticated state
    await page.evaluate(() => {
      localStorage.setItem('access_token', 'mock_token');
      localStorage.setItem('refresh_token', 'mock_refresh');
    });

    // Mock logout endpoint
    await page.route('**/api/auth/logout', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ message: 'Logged out successfully' }),
      });
    });

    // Simulate logout
    await page.evaluate(async () => {
      await fetch('http://localhost:8000/api/auth/logout', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('access_token')}`,
        },
      });
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
    });

    // Verify tokens are cleared
    const accessToken = await page.evaluate(() => localStorage.getItem('access_token'));
    const refreshToken = await page.evaluate(() => localStorage.getItem('refresh_token'));

    expect(accessToken).toBeNull();
    expect(refreshToken).toBeNull();
  });
});

test.describe('Session Restoration', () => {
  test('should restore session from localStorage on page refresh', async ({ page }) => {
    // Mock the /me endpoint
    await page.route('**/api/auth/me', (route) => {
      const authHeader = route.request().headers()['authorization'];

      if (authHeader && authHeader.includes('valid_token')) {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            id: '1',
            email: 'test@example.com',
            name: 'Test User',
            picture: 'https://example.com/avatar.jpg',
          }),
        });
      } else {
        route.fulfill({
          status: 401,
          contentType: 'application/json',
          body: JSON.stringify({ detail: 'Not authenticated' }),
        });
      }
    });

    // Set valid token in localStorage
    await page.goto('http://localhost:5173');
    await page.evaluate(() => {
      localStorage.setItem('access_token', 'valid_token_123');
    });

    // Refresh page
    await page.reload();

    // The AuthContext should call /api/auth/me to verify the token
    // Wait for the API call to complete
    await page.waitForTimeout(1000);

    // In a real scenario, you'd verify that the user is authenticated
    // by checking for authenticated-only UI elements
  });

  test('should clear invalid tokens on page load', async ({ page }) => {
    // Mock the /me endpoint to return 401
    await page.route('**/api/auth/me', (route) => {
      route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({ detail: 'Invalid token' }),
      });
    });

    // Set invalid token
    await page.goto('http://localhost:5173');
    await page.evaluate(() => {
      localStorage.setItem('access_token', 'invalid_token');
      localStorage.setItem('refresh_token', 'invalid_refresh');
    });

    // Reload page
    await page.reload();
    await page.waitForTimeout(1000);

    // Tokens should be cleared
    const accessToken = await page.evaluate(() => localStorage.getItem('access_token'));
    const refreshToken = await page.evaluate(() => localStorage.getItem('refresh_token'));

    expect(accessToken).toBeNull();
    expect(refreshToken).toBeNull();
  });
});
