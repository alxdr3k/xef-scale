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

test.describe('Discard Functionality', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('검토 대기 세션 취소하기', async ({ page }) => {
    await navigateToParsingSessions(page);

    // Look for a pending review session (검토하기 link indicates pending state)
    const reviewLink = page.locator('a:has-text("검토하기")').first();
    if (await reviewLink.isVisible()) {
      await reviewLink.click();

      // Check for discard button
      const discardButton = page.locator('button:has-text("취소하기")');
      await expect(discardButton).toBeVisible();

      // Accept the confirmation dialog
      page.on('dialog', dialog => dialog.accept());

      await discardButton.click();

      // Should redirect to parsing sessions list with success message
      await expect(page.locator('text=취소되었습니다')).toBeVisible({ timeout: 10000 });
    }
  });

  test('취소된 세션 상태 확인', async ({ page }) => {
    await navigateToParsingSessions(page);

    // Find a discarded session (취소됨 badge)
    const discardedBadge = page.locator('span:has-text("취소됨")').first();
    if (await discardedBadge.isVisible()) {
      // Get the parent row
      const row = discardedBadge.locator('xpath=ancestor::tr');

      // Should still have "상세보기" link
      const detailLink = row.locator('a:has-text("상세보기")');
      await expect(detailLink).toBeVisible();

      // Click to view details
      await detailLink.click();

      // Should show discarded status badge
      await expect(page.locator('span:has-text("취소됨")')).toBeVisible();

      // Should not show any action buttons (discard, commit)
      await expect(page.locator('button:has-text("취소하기")')).not.toBeVisible();
      await expect(page.locator('button:has-text("거래 내역 반영")')).not.toBeVisible();
    }
  });
});
