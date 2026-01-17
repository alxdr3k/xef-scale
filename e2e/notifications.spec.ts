import { test, expect } from '@playwright/test';
import { login } from './helpers';

test.describe('Notifications', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('알림 벨 및 드롭다운', async ({ page }) => {
    // 1. Find notification bell
    const notificationBell = page.locator('[data-controller="notifications"] button').first();
    await expect(notificationBell).toBeVisible();

    // 2. Click to open dropdown
    await notificationBell.click();

    // 3. Dropdown should be visible
    const dropdown = page.locator('[data-notifications-target="dropdown"]');
    await expect(dropdown).toBeVisible();

    // 4. Check for "전체 알림 보기" link
    const viewAllLink = page.locator('a:has-text("전체 알림 보기")');
    await expect(viewAllLink).toBeVisible();
  });

  test('알림 페이지 접근', async ({ page }) => {
    // Navigate to notifications page
    await page.goto('/notifications');

    // Check page title
    await expect(page.locator('h1:has-text("알림")')).toBeVisible();
  });

  test('모두 읽음 처리', async ({ page }) => {
    await page.goto('/notifications');

    // If there are unread notifications, click "모두 읽음으로 표시"
    const markAllReadLink = page.locator('a:has-text("모두 읽음으로 표시")');
    if (await markAllReadLink.isVisible()) {
      await markAllReadLink.click();
      await page.waitForLoadState('networkidle');
    }
  });

  test('알림 클릭 시 해당 페이지로 이동', async ({ page }) => {
    await page.goto('/notifications');

    // Find first notification with action URL
    const notificationLink = page.locator('.bg-white a').first();
    if (await notificationLink.isVisible()) {
      const href = await notificationLink.getAttribute('href');
      if (href && href.includes('review')) {
        await notificationLink.click();
        await expect(page).toHaveURL(/review/);
      }
    }
  });
});
