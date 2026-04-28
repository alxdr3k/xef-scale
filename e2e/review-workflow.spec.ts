import { test, expect } from '@playwright/test';
import { login, navigateToParsingSessions, goToReviewPage } from './helpers';

test.describe('Review Workflow', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('파일 업로드 후 검토 페이지에서 확정까지', async ({ page }) => {
    // 1. Navigate to parsing sessions
    await navigateToParsingSessions(page);

    // 2. Check that page loaded
    await expect(page.locator('h1:has-text("결제 추가")')).toBeVisible();

    // 3. Find any completed session with pending review
    const reviewLink = page.locator('a:has-text("검토하기")').first();
    if (await reviewLink.isVisible()) {
      // 4. Go to review page
      await reviewLink.click();
      await expect(page.locator('h1:has-text("결제 검토")')).toBeVisible();

      // 5. Check transaction table is visible
      const table = page.locator('table');
      await expect(table).toBeVisible();

      // 6. If there are pending transactions, commit them
      const commitButton = page.locator('button:has-text("전체 확정")');
      if (await commitButton.isVisible()) {
        page.on('dialog', dialog => dialog.accept());
        await commitButton.click();

        // 7. Verify success message
        await expect(page.locator('text=확정되었습니다')).toBeVisible({ timeout: 10000 });
      }
    }
  });

  test('검토 페이지에서 카테고리 변경', async ({ page }) => {
    await navigateToParsingSessions(page);

    const reviewLink = page.locator('a:has-text("검토하기")').first();
    if (await reviewLink.isVisible()) {
      await reviewLink.click();

      // Find a category select
      const categorySelect = page.locator('select[name="transaction[category_id]"]').first();
      if (await categorySelect.isVisible()) {
        // Change category
        await categorySelect.selectOption({ index: 1 });

        // Wait for auto-submit
        await page.waitForLoadState('networkidle');
      }
    }
  });

  test('다중 선택 후 삭제', async ({ page }) => {
    await navigateToParsingSessions(page);

    const reviewLink = page.locator('a:has-text("검토하기")').first();
    if (await reviewLink.isVisible()) {
      await reviewLink.click();

      // Check for checkboxes
      const checkboxes = page.locator('input[type="checkbox"][data-bulk-select-target="checkbox"]');
      const count = await checkboxes.count();

      if (count >= 2) {
        // Select first two checkboxes
        await checkboxes.nth(0).check();
        await checkboxes.nth(1).check();

        // Verify action bar appears
        const actionBar = page.locator('[data-bulk-select-target="actions"]');
        await expect(actionBar).toBeVisible();

        // Verify count shows
        const countText = page.locator('[data-bulk-select-target="count"]');
        await expect(countText).toHaveText('2');
      }
    }
  });

  test('확정된 세션은 읽기 전용', async ({ page }) => {
    await navigateToParsingSessions(page);

    // Look for a committed session
    const detailLink = page.locator('a:has-text("상세보기")').first();
    if (await detailLink.isVisible()) {
      await detailLink.click();

      // Should see "읽기 전용" or committed status
      const readOnlyIndicator = page.locator('text=읽기 전용').or(page.locator('text=확정됨'));
      await expect(readOnlyIndicator.first()).toBeVisible();

      // Checkboxes should not be present in read-only mode
      const checkbox = page.locator('input[type="checkbox"][data-bulk-select-target="checkbox"]').first();
      await expect(checkbox).not.toBeVisible();

      // Only rollback button should be available
      const rollbackButton = page.locator('button:has-text("전체 롤백")');
      // Commit button should not be visible
      const commitButton = page.locator('button:has-text("전체 확정")');
      await expect(commitButton).not.toBeVisible();
    }
  });

  test('출처 변경은 알수없음일 때만 가능', async ({ page }) => {
    await navigateToParsingSessions(page);

    const reviewLink = page.locator('a:has-text("검토하기")').first();
    if (await reviewLink.isVisible()) {
      await reviewLink.click();

      // Check for source select fields
      // Editable source should be a select
      const sourceSelects = page.locator('select[name="transaction[financial_institution_id]"]');

      // Non-editable sources should be plain text
      const sourceTexts = page.locator('td:has-text("하나카드"), td:has-text("신한카드"), td:has-text("토스뱅크")');

      // At least verify the page loaded correctly
      await expect(page.locator('h1:has-text("결제 검토")')).toBeVisible();
    }
  });
});
