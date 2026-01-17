import { test, expect } from '@playwright/test';
import { login, navigateToParsingSessions } from './helpers';

test.describe('Rollback Functionality', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('확정된 세션 롤백', async ({ page }) => {
    await navigateToParsingSessions(page);

    // Look for a committed session (상세보기 link indicates committed state)
    const detailLink = page.locator('a:has-text("상세보기")').first();
    if (await detailLink.isVisible()) {
      await detailLink.click();

      // Check for rollback button
      const rollbackButton = page.locator('button:has-text("전체 롤백")');
      if (await rollbackButton.isVisible()) {
        // Accept the confirmation dialog
        page.on('dialog', dialog => dialog.accept());

        await rollbackButton.click();

        // Should redirect to parsing sessions list with success message
        await expect(page.locator('text=롤백되었습니다')).toBeVisible({ timeout: 10000 });
      }
    }
  });

  test('롤백 후 상태 확인', async ({ page }) => {
    await navigateToParsingSessions(page);

    // Find a rolled back session (롤백 badge)
    const rolledBackBadge = page.locator('span:has-text("롤백")').first();
    if (await rolledBackBadge.isVisible()) {
      // Get the parent row
      const row = rolledBackBadge.locator('xpath=ancestor::tr');

      // Should still have "상세보기" link
      const detailLink = row.locator('a:has-text("상세보기")');
      await expect(detailLink).toBeVisible();
    }
  });
});
