import { test, expect } from '@playwright/test';
import { loginAsUser } from './helpers';

test.describe('Mobile bottom navigation', () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true });

  test.beforeEach(async ({ page }) => {
    await loginAsUser(page);
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    if (page.url().includes('/users/sign_in')) {
      await loginAsUser(page, 'admin@example.com');
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
    }
  });

  test('primary mobile destinations are reachable', async ({ page }) => {
    let bottomNav = page.locator('nav.mobile-bottom-nav');
    await expect(bottomNav).toBeVisible();

    await bottomNav.getByRole('link', { name: '결제' }).click();
    await expect(page).toHaveURL(/\/workspaces\/\d+\/transactions/);

    await page.goto('/dashboard');
    bottomNav = page.locator('nav.mobile-bottom-nav');
    await bottomNav.getByRole('link', { name: '가져오기' }).click();
    await expect(page).toHaveURL(/\/workspaces\/\d+\/parsing_sessions/);

    await page.goto('/dashboard');
    bottomNav = page.locator('nav.mobile-bottom-nav');
    await bottomNav.getByRole('link', { name: '설정' }).click();
    await expect(page).toHaveURL(/\/workspaces\/\d+\/settings/);
    await expect(page.getByRole('heading', { name: '워크스페이스 설정' })).toBeVisible();
    await expect(page.getByRole('link', { name: '계정 설정' })).toBeVisible();
  });
});
