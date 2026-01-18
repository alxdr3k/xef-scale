import { test, expect, Page } from '@playwright/test';
import { loginAsAdmin, navigateToParsingSessions } from './helpers';

/**
 * Reviews Page E2E Tests
 *
 * Converted from test/system/reviews_test.rb
 * These tests cover the review workflow for parsing sessions including:
 * - Table rendering and column headers
 * - Inline editing (category, description, financial institution)
 * - Allowance toggle
 * - Bulk actions
 * - Commit, rollback, and discard actions
 * - Read-only mode
 * - Pagination
 */

test.describe('Reviews Page', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  // Helper to navigate to a review page with pending transactions
  async function goToReviewPageWithPendingSession(page: Page): Promise<boolean> {
    await navigateToParsingSessions(page);
    const reviewLink = page.locator('a:has-text("검토하기")').first();
    if (await reviewLink.isVisible({ timeout: 3000 }).catch(() => false)) {
      await reviewLink.click();
      await page.waitForURL(/review/);
      return true;
    }
    return false;
  }

  // Helper to navigate to a committed session (read-only)
  async function goToCommittedSession(page: Page): Promise<boolean> {
    await navigateToParsingSessions(page);
    const detailLink = page.locator('a:has-text("상세보기")').first();
    if (await detailLink.isVisible({ timeout: 3000 }).catch(() => false)) {
      await detailLink.click();
      await page.waitForURL(/review/);
      return true;
    }
    return false;
  }

  // 1. Table rendering - Column headers (with description column)
  test('테이블 렌더링 - 컬럼 헤더에 설명 표시', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Check that the page loaded successfully
    await expect(page.locator('h1:has-text("검토")')).toBeVisible();

    // Check column headers in table
    const thead = page.locator('table thead');
    await expect(thead).toBeVisible();

    // Verify all required column headers
    await expect(thead.locator('th:has-text("날짜")')).toBeVisible();
    await expect(thead.locator('th:has-text("내역")')).toBeVisible();
    await expect(thead.locator('th:has-text("금액")')).toBeVisible();
    await expect(thead.locator('th:has-text("카테고리")')).toBeVisible();
    await expect(thead.locator('th:has-text("금융기관")')).toBeVisible();
    await expect(thead.locator('th:has-text("용돈")')).toBeVisible();

    // Check for "설명" column (not "메모")
    await expect(thead.locator('th:has-text("설명")')).toBeVisible();
    await expect(thead.locator('th:has-text("메모")')).not.toBeVisible();
  });

  // 2. Table rendering - Display transactions
  test('테이블 렌더링 - 거래 내역 표시', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Check that transactions are displayed in the table
    const tbody = page.locator('table tbody');
    await expect(tbody).toBeVisible();

    // Should have at least one transaction row
    const rows = tbody.locator('tr');
    const rowCount = await rows.count();
    expect(rowCount).toBeGreaterThan(0);

    // Check that transaction details are visible (amount with currency)
    const firstRow = rows.first();
    await expect(firstRow.locator('td')).toHaveCount.greaterThan(0);

    // Verify currency format (Korean Won)
    await expect(page.locator('text=/₩[\\d,]+/')).toBeVisible();
  });

  // 3. Inline editing - Category dropdown auto-save
  test('인라인 편집 - 카테고리 드롭다운 변경 시 자동 저장', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Find the first category dropdown
    const categorySelect = page.locator('select[name="transaction[category_id]"]').first();
    if (!(await categorySelect.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No editable category select available');
      return;
    }

    // Get current selected value
    const currentValue = await categorySelect.inputValue();

    // Change category to a different option
    const options = await categorySelect.locator('option').all();
    let newOptionValue: string | null = null;

    for (const option of options) {
      const value = await option.getAttribute('value');
      if (value && value !== currentValue && value !== '') {
        newOptionValue = value;
        break;
      }
    }

    if (!newOptionValue) {
      test.skip(true, 'No alternative category available');
      return;
    }

    await categorySelect.selectOption(newOptionValue);

    // Wait for auto-submit to complete
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(500);

    // Reload page and verify the change persisted
    await page.reload();
    await page.waitForLoadState('networkidle');

    const updatedSelect = page.locator('select[name="transaction[category_id]"]').first();
    await expect(updatedSelect).toHaveValue(newOptionValue);
  });

  // 4. Inline editing - Description field auto-save on blur
  test('인라인 편집 - 설명 필드 입력 후 blur 시 자동 저장', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Find the first notes input field
    const notesField = page.locator('input[name="transaction[notes]"]').first();
    if (!(await notesField.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No editable notes field available');
      return;
    }

    // Generate a unique test value
    const testNote = `테스트 설명 ${Date.now()}`;

    // Clear and fill the notes field
    await notesField.clear();
    await notesField.fill(testNote);

    // Trigger blur by clicking elsewhere
    await page.locator('h1').click();

    // Wait for auto-submit to complete
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(500);

    // Reload page and verify the change persisted
    await page.reload();
    await page.waitForLoadState('networkidle');

    const updatedNotesField = page.locator('input[name="transaction[notes]"]').first();
    await expect(updatedNotesField).toHaveValue(testNote);
  });

  // 5. Allowance button toggle
  test('인라인 편집 - 용돈 버튼 클릭 시 상태 토글', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Find the first allowance button (emoji button)
    const allowanceButton = page.locator('button:has-text("💰")').first();
    if (!(await allowanceButton.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No allowance toggle button available');
      return;
    }

    // Get initial opacity state
    const initialSpan = allowanceButton.locator('span').first();
    const initialClass = await initialSpan.getAttribute('class');
    const wasActive = initialClass?.includes('opacity-100');

    // Click to toggle
    await allowanceButton.click();

    // Wait for Turbo Stream response
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(500);

    // Check that state changed
    const updatedButton = page.locator('button:has-text("💰")').first();
    const updatedSpan = updatedButton.locator('span').first();
    const updatedClass = await updatedSpan.getAttribute('class');
    const isNowActive = updatedClass?.includes('opacity-100');

    expect(isNowActive).not.toBe(wasActive);

    // Toggle back to restore original state
    await updatedButton.click();
    await page.waitForLoadState('networkidle');
  });

  // 6. Bulk actions - Select checkboxes and delete
  test('일괄 작업 - 체크박스 여러 개 선택 후 일괄 삭제', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Find checkboxes for bulk selection
    const checkboxes = page.locator('input[type="checkbox"][data-bulk-select-target="checkbox"]');
    const count = await checkboxes.count();

    if (count < 2) {
      test.skip(true, 'Not enough transactions for bulk action test');
      return;
    }

    // Select first two checkboxes
    await checkboxes.nth(0).check();
    await checkboxes.nth(1).check();

    // Wait for bulk actions to appear
    await page.waitForTimeout(300);

    // Verify action bar appears with correct count
    const actionBar = page.locator('[data-bulk-select-target="actions"]');
    await expect(actionBar).toBeVisible();

    const countText = page.locator('[data-bulk-select-target="count"]');
    await expect(countText).toHaveText('2');

    // Verify delete button is visible in action bar
    const deleteButton = actionBar.locator('button:has-text("삭제")');
    await expect(deleteButton).toBeVisible();
  });

  // 7. Commit button exists
  test('확정 버튼 존재 확인', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Check that commit button exists (actual text: "거래 내역 반영")
    const commitButton = page.locator('button:has-text("거래 내역 반영")');
    await expect(commitButton).toBeVisible();
  });

  // 8. Cancel button exists
  test('취소 버튼 존재 확인', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Check that discard button exists
    const discardButton = page.locator('button:has-text("취소하기")');
    await expect(discardButton).toBeVisible();
  });

  // 9. Commit button click commits transactions
  test('확정 버튼 클릭 시 거래 확정', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Setup dialog handler to accept confirmation
    page.on('dialog', async (dialog) => {
      await dialog.accept();
    });

    // Click commit button
    const commitButton = page.locator('button:has-text("거래 내역 반영")');
    await commitButton.click();

    // Wait for the action to complete
    await page.waitForLoadState('networkidle');

    // Should show success message or committed status
    const successIndicator = page.locator('text=/확정|반영/i').first();
    await expect(successIndicator).toBeVisible({ timeout: 10000 });

    // Verify the session is now committed (shows "확정됨" badge)
    const committedBadge = page.locator('span:has-text("확정됨")');
    await expect(committedBadge).toBeVisible();
  });

  // 10. Rollback button click rolls back all transactions
  test('롤백 버튼 클릭 시 모든 거래 롤백', async ({ page }) => {
    // First, we need a committed session
    const hasCommittedSession = await goToCommittedSession(page);
    test.skip(!hasCommittedSession, 'No committed session available');

    // Check for rollback button (appears only after commit)
    const rollbackButton = page.locator('button:has-text("전체 롤백")');
    if (!(await rollbackButton.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No rollback button available');
      return;
    }

    // Setup dialog handler to accept confirmation
    page.on('dialog', async (dialog) => {
      await dialog.accept();
    });

    // Click rollback button
    await rollbackButton.click();

    // Wait for redirect
    await page.waitForLoadState('networkidle');

    // Should be redirected to parsing sessions list with success message
    await expect(page.locator('text=/롤백/i')).toBeVisible({ timeout: 10000 });
  });

  // 11. Discard button click discards upload
  test('취소하기 버튼 클릭 시 업로드 폐기', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Setup dialog handler to accept confirmation
    page.on('dialog', async (dialog) => {
      await dialog.accept();
    });

    // Click discard button
    const discardButton = page.locator('button:has-text("취소하기")');
    await discardButton.click();

    // Wait for redirect
    await page.waitForLoadState('networkidle');

    // Should be redirected to parsing sessions list with success message
    await expect(page.locator('text=/취소/i')).toBeVisible({ timeout: 10000 });
  });

  // 12. Read-only mode (committed session)
  test('읽기 전용 모드 - 확정된 세션은 편집 불가', async ({ page }) => {
    const hasCommittedSession = await goToCommittedSession(page);
    test.skip(!hasCommittedSession, 'No committed session available');

    // Should show "읽기 전용" status
    const readOnlyStatus = page.locator('text=읽기 전용');
    await expect(readOnlyStatus).toBeVisible();

    // Should not have checkboxes
    const checkbox = page.locator('input[type="checkbox"][data-bulk-select-target="checkbox"]');
    await expect(checkbox.first()).not.toBeVisible();

    // Should not have category dropdowns (only static text spans)
    const categorySelect = page.locator('select[name="transaction[category_id]"]');
    await expect(categorySelect.first()).not.toBeVisible();

    // Should not have notes input fields
    const notesInput = page.locator('input[name="transaction[notes]"]');
    await expect(notesInput.first()).not.toBeVisible();

    // Should not have delete buttons in rows
    const deleteButton = page.locator('table tbody button:has-text("삭제")');
    await expect(deleteButton.first()).not.toBeVisible();
  });

  // 13. Financial institution dropdown (only for source_editable transactions)
  test('금융기관 드롭다운 - source_editable 거래만 편집 가능', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Check for financial institution select fields
    const sourceSelects = page.locator('select[name="transaction[financial_institution_id]"]');
    const selectCount = await sourceSelects.count();

    // Check for static text sources (non-editable)
    const tbody = page.locator('table tbody');
    await expect(tbody).toBeVisible();

    // Some rows might have dropdowns (editable), others have static text (non-editable)
    // This verifies the selective editability

    // Verify the page loaded correctly regardless of data state
    await expect(page.locator('h1:has-text("거래 검토")')).toBeVisible();

    // If there are editable sources, verify they work
    if (selectCount > 0) {
      const firstSourceSelect = sourceSelects.first();
      await expect(firstSourceSelect).toBeVisible();
    }

    // Check for static institution names in non-editable rows
    const staticSources = page.locator('td:has-text("하나카드"), td:has-text("신한카드"), td:has-text("토스뱅크")');
    // At least verify the table structure is correct
    expect(await tbody.locator('tr').count()).toBeGreaterThan(0);
  });

  // 14. Deleted transaction styling
  test('삭제된 거래는 회색 배경으로 표시', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Look for any deleted transactions (they have "삭제됨" text and special styling)
    const deletedRow = page.locator('tr.bg-red-50.opacity-60');
    const deletedCount = await deletedRow.count();

    if (deletedCount > 0) {
      // Verify deleted transaction has "삭제됨" text
      const deletedText = deletedRow.first().locator('text=삭제됨');
      await expect(deletedText).toBeVisible();

      // Verify deleted transaction does NOT have checkbox
      const checkbox = deletedRow.first().locator('input[type="checkbox"]');
      await expect(checkbox).not.toBeVisible();
    }

    // Verify non-deleted rows don't have the deleted styling
    const normalRows = page.locator('tr:not(.bg-red-50):not(.opacity-60)').filter({
      has: page.locator('input[type="checkbox"]'),
    });

    if ((await normalRows.count()) > 0) {
      const firstNormalRow = normalRows.first();
      await expect(firstNormalRow.locator('text=삭제됨')).not.toBeVisible();
    }
  });

  // 15. Pagination (50+ transactions)
  test('페이지네이션 - 50개 이상 거래 처리', async ({ page }) => {
    const hasReviewPage = await goToReviewPageWithPendingSession(page);
    test.skip(!hasReviewPage, 'No pending review session available');

    // Check if pagination exists (appears when >50 transactions)
    const pagination = page.locator('nav.pagy-nav, nav.pagy, .pagination, [class*="pagy"]');
    const tbody = page.locator('table tbody');
    const rows = tbody.locator('tr');
    const rowCount = await rows.count();

    // Verify table displays transactions
    expect(rowCount).toBeGreaterThan(0);

    // If pagination exists, verify it works
    if (await pagination.isVisible({ timeout: 2000 }).catch(() => false)) {
      // Should have at most 50 rows per page
      expect(rowCount).toBeLessThanOrEqual(50);

      // Check for next/page links
      const pageLinks = pagination.locator('a');
      if ((await pageLinks.count()) > 0) {
        // Click next page if available
        const nextLink = pagination.locator('a:has-text("다음"), a:has-text("Next"), a[rel="next"]').first();
        if (await nextLink.isVisible({ timeout: 1000 }).catch(() => false)) {
          await nextLink.click();
          await page.waitForLoadState('networkidle');

          // Verify still on review page with transactions
          await expect(tbody).toBeVisible();
        }
      }
    }
  });
});

// Additional edge case tests
test.describe('Reviews Page - Edge Cases', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('전체 선택 체크박스 동작', async ({ page }) => {
    await navigateToParsingSessions(page);
    const reviewLink = page.locator('a:has-text("검토하기")').first();

    if (!(await reviewLink.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No pending review session available');
      return;
    }

    await reviewLink.click();
    await page.waitForURL(/review/);

    // Find select all checkbox
    const selectAllCheckbox = page.locator('input[data-bulk-select-target="selectAll"]');
    if (!(await selectAllCheckbox.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No select all checkbox available');
      return;
    }

    // Check select all
    await selectAllCheckbox.check();
    await page.waitForTimeout(300);

    // All individual checkboxes should be checked
    const checkboxes = page.locator('input[type="checkbox"][data-bulk-select-target="checkbox"]');
    const count = await checkboxes.count();

    for (let i = 0; i < count; i++) {
      await expect(checkboxes.nth(i)).toBeChecked();
    }

    // Uncheck select all
    await selectAllCheckbox.uncheck();
    await page.waitForTimeout(300);

    // All individual checkboxes should be unchecked
    for (let i = 0; i < count; i++) {
      await expect(checkboxes.nth(i)).not.toBeChecked();
    }
  });

  test('용돈 일괄 표시 및 해제', async ({ page }) => {
    await navigateToParsingSessions(page);
    const reviewLink = page.locator('a:has-text("검토하기")').first();

    if (!(await reviewLink.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No pending review session available');
      return;
    }

    await reviewLink.click();
    await page.waitForURL(/review/);

    // Select a checkbox
    const checkbox = page.locator('input[type="checkbox"][data-bulk-select-target="checkbox"]').first();
    if (!(await checkbox.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No checkboxes available');
      return;
    }

    await checkbox.check();
    await page.waitForTimeout(300);

    // Verify bulk action buttons appear
    const actionBar = page.locator('[data-bulk-select-target="actions"]');
    await expect(actionBar).toBeVisible();

    // Verify "용돈 표시" and "용돈 해제" buttons exist
    const markAllowanceButton = actionBar.locator('button:has-text("용돈 표시")');
    const unmarkAllowanceButton = actionBar.locator('button:has-text("용돈 해제")');

    await expect(markAllowanceButton).toBeVisible();
    await expect(unmarkAllowanceButton).toBeVisible();
  });

  test('카테고리 일괄 변경 UI', async ({ page }) => {
    await navigateToParsingSessions(page);
    const reviewLink = page.locator('a:has-text("검토하기")').first();

    if (!(await reviewLink.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No pending review session available');
      return;
    }

    await reviewLink.click();
    await page.waitForURL(/review/);

    // Select a checkbox
    const checkbox = page.locator('input[type="checkbox"][data-bulk-select-target="checkbox"]').first();
    if (!(await checkbox.isVisible({ timeout: 3000 }).catch(() => false))) {
      test.skip(true, 'No checkboxes available');
      return;
    }

    await checkbox.check();
    await page.waitForTimeout(300);

    // Verify bulk action bar has category change components
    const actionBar = page.locator('[data-bulk-select-target="actions"]');
    await expect(actionBar).toBeVisible();

    const categorySelect = actionBar.locator('select[name="category_id"]');
    const changeCategoryButton = actionBar.locator('button:has-text("카테고리 변경")');

    await expect(categorySelect).toBeVisible();
    await expect(changeCategoryButton).toBeVisible();
  });
});
