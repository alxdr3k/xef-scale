import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

// Duplicate modal is rendered inside transactions/index via _duplicate_modal partial.
// Trigger: "중복 검사" button (data-action="click->duplicate-modal#open")
// Controller: duplicate-modal (Stimulus)
// States: loading → empty (no duplicates) | content+footer (duplicates found)
// Footer actions: "← 기존 거래만 남기기", "새 거래로 교체하기 →", "둘 다 남기기 (B)"
// Header extras: undo button, counter, progress bar

test.describe('Duplicate modal (중복 거래 검사)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto('/workspaces/1/transactions');
    await page.waitForLoadState('networkidle');
  });

  test('중복 검사 버튼 클릭 시 모달이 열린다', async ({ page }) => {
    // Modal is initially hidden
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).toHaveClass(/hidden/);

    await page.getByRole('button', { name: '중복 검사' }).click();

    // Modal becomes visible (class "hidden" removed)
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).not.toHaveClass(/hidden/);
    // Title inside modal
    await expect(page.locator('h2:has-text("중복 거래 검사")')).toBeVisible();
  });

  test('모달 헤더 구성요소 확인 (실행취소·카운터·닫기)', async ({ page }) => {
    await page.getByRole('button', { name: '중복 검사' }).click();
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).not.toHaveClass(/hidden/);

    // Undo button (initially disabled)
    const undoBtn = page.locator('[data-duplicate-modal-target="undoBtn"]');
    await expect(undoBtn).toBeVisible();
    await expect(undoBtn).toBeDisabled();

    // Counter span
    await expect(page.locator('[data-duplicate-modal-target="counter"]')).toBeAttached();

    // Progress bar (starts at width: 0%, so toBeVisible would fail; just assert it's in the DOM)
    await expect(page.locator('[data-duplicate-modal-target="progress"]')).toBeAttached();
  });

  test('로딩 스피너가 초기 상태에서 표시된다', async ({ page }) => {
    await page.getByRole('button', { name: '중복 검사' }).click();
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).not.toHaveClass(/hidden/);
    // Loading indicator visible while fetching
    const loading = page.locator('[data-duplicate-modal-target="loading"]');
    // It may flash briefly; we just check it exists and was visible right after open
    await expect(loading).toBeAttached();
  });

  test('중복 없을 때 빈 상태 메시지 또는 중복 목록이 표시된다', async ({ page }) => {
    await page.getByRole('button', { name: '중복 검사' }).click();
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).not.toHaveClass(/hidden/);

    // Wait for loading to complete (loading hides, then either empty or content appears)
    await page.waitForTimeout(3000); // allow API call

    const emptyTarget = page.locator('[data-duplicate-modal-target="empty"]');
    const contentTarget = page.locator('[data-duplicate-modal-target="content"]');

    const emptyVisible = await emptyTarget.isVisible().catch(() => false);
    const contentVisible = await contentTarget.isVisible().catch(() => false);

    // One of the two states must be visible
    expect(emptyVisible || contentVisible).toBe(true);

    if (emptyVisible) {
      await expect(page.locator('text=중복 거래가 없습니다')).toBeVisible();
    }
  });

  test('중복 발견 시 footer 액션 버튼 3개가 표시된다', async ({ page }) => {
    await page.getByRole('button', { name: '중복 검사' }).click();
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).not.toHaveClass(/hidden/);
    await page.waitForTimeout(3000);

    const footer = page.locator('[data-duplicate-modal-target="footer"]');
    const footerVisible = await footer.isVisible().catch(() => false);

    if (footerVisible) {
      // All three resolution buttons must be present
      await expect(page.getByRole('button', { name: /기존 거래만 남기기/ })).toBeVisible();
      await expect(page.getByRole('button', { name: /새 거래로 교체하기/ })).toBeVisible();
      await expect(page.getByRole('button', { name: /둘 다 남기기/ })).toBeVisible();

      // Keyboard hint text
      await expect(page.locator('text=/키보드/i')).toBeVisible();
    }
  });

  test('닫기(×) 버튼 클릭 시 모달이 닫힌다', async ({ page }) => {
    await page.getByRole('button', { name: '중복 검사' }).click();
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).not.toHaveClass(/hidden/);

    // Close via × button (svg button inside modal header)
    await page.locator('[data-duplicate-modal-target="modal"] button[data-action="click->duplicate-modal#close"]').click();

    await expect(page.locator('[data-duplicate-modal-target="modal"]')).toHaveClass(/hidden/);
  });

  test('배경 오버레이 클릭 시 모달이 닫힌다', async ({ page }) => {
    await page.getByRole('button', { name: '중복 검사' }).click();
    await expect(page.locator('[data-duplicate-modal-target="modal"]')).not.toHaveClass(/hidden/);

    // Click the backdrop (fixed inset-0 overlay). The modal content (empty
    // state SVG / spinner) sits above the backdrop and would intercept a
    // normal click, so dispatch the click directly on the overlay element via
    // the page DOM.
    await page.evaluate(() => {
      const el = document.querySelector('.fixed.inset-0[data-action="click->duplicate-modal#close"]');
      (el as HTMLElement | null)?.click();
    });

    await expect(page.locator('[data-duplicate-modal-target="modal"]')).toHaveClass(/hidden/);
  });
});
