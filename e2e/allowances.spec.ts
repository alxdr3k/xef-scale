import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

test.describe('Allowances (용돈)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('테이블 렌더링 - 컬럼 순서 확인', async ({ page }) => {
    await page.goto('/allowances?year=2025&month=1');

    // Header columns in current UI: date / merchant / amount / category.
    // Financial institution column was removed (now source-only metadata).
    // (Per-row release was removed in favor of bulk-select; there is no "작업" column.)
    await expect(page.locator('thead th:has-text("날짜")')).toBeVisible();
    await expect(page.locator('thead th:has-text("내역")')).toBeVisible();
    await expect(page.locator('thead th:has-text("금액")')).toBeVisible();
    await expect(page.locator('thead th:has-text("카테고리")')).toBeVisible();
    await expect(page.locator('thead th:has-text("금융기관")')).not.toBeVisible();
  });

  // The per-row "해제" button no longer exists — unmark happens via bulk-select.
  // Marking the test as fixme until a bulk-select e2e flow is added.
  test.fixme('해제 버튼 - 확인 대화상자와 행 제거', async ({ page }) => {
    // TODO(#97): Rewrite against the bulk-select unmark flow (toggle row → click
    // toolbar "용돈 해제"). Currently no per-row 해제 button exists.
    await page.goto('/allowances?year=2025&month=1');
  });

  test('월력 - 드롭다운 열림과 닫힘', async ({ page }) => {
    await page.goto('/allowances?year=2025&month=1');

    // Month picker should be visible
    await expect(page.locator('[data-controller="month-picker"]')).toBeVisible();

    // Dropdown should be hidden initially
    const dropdown = page.locator('[data-month-picker-target="dropdown"]');
    await expect(dropdown).toHaveClass(/hidden/);

    // Click to open dropdown
    await page.locator('[data-action="click->month-picker#toggle"]').click();

    // Dropdown should be visible (no hidden class)
    await expect(dropdown).not.toHaveClass(/hidden/);

    // Click outside to close (click on page title)
    await page.locator('h1').click();

    // Dropdown should be hidden again
    await expect(dropdown).toHaveClass(/hidden/, { timeout: 1000 });
  });

  test('월력 - 연도 화살표로 연도 변경', async ({ page }) => {
    await page.goto('/allowances?year=2025&month=1');

    // Open month picker dropdown
    await page.locator('[data-action="click->month-picker#toggle"]').click();

    const dropdown = page.locator('[data-month-picker-target="dropdown"]');

    // Verify initial year display
    await expect(dropdown).toContainText('2025년');

    // Click next year button
    await page.locator('[data-action="click->month-picker#nextYear"]').click();

    // Year should increment
    await expect(dropdown).toContainText('2026년');

    // Click previous year button twice
    await page.locator('[data-action="click->month-picker#previousYear"]').click();
    await page.locator('[data-action="click->month-picker#previousYear"]').click();

    // Year should decrement to 2024
    await expect(dropdown).toContainText('2024년');
  });

  test('월력 - 월 선택 시 페이지 이동', async ({ page }) => {
    await page.goto('/allowances?year=2025&month=1');

    // Open month picker dropdown
    await page.locator('[data-action="click->month-picker#toggle"]').click();

    // Select March (3월)
    await page.locator('[data-month-picker-target="dropdown"] button[data-month="3"]').click();

    // URL should change to March
    await expect(page).toHaveURL(/year=2025.*month=3|month=3.*year=2025/);

    // Page should show March
    await expect(page.locator('body')).toContainText('2025년 3월');
  });

  test('월력 - 연도 변경 후 월 선택', async ({ page }) => {
    await page.goto('/allowances?year=2025&month=1');

    // Open month picker dropdown
    await page.locator('[data-action="click->month-picker#toggle"]').click();

    // Change to 2024
    await page.locator('[data-action="click->month-picker#previousYear"]').click();

    const dropdown = page.locator('[data-month-picker-target="dropdown"]');
    await expect(dropdown).toContainText('2024년');

    // Select December
    await page.locator('[data-month-picker-target="dropdown"] button[data-month="12"]').click();

    // Should navigate to December 2024
    await expect(page).toHaveURL(/year=2024.*month=12|month=12.*year=2024/);
    await expect(page.locator('body')).toContainText('2024년 12월');
  });

  test('빈 상태 메시지 표시', async ({ page }) => {
    // Visit a month with no allowance transactions
    await page.goto('/allowances?year=2024&month=12');

    // Should show empty state message
    await expect(page.locator('text=이번 달 용돈 내역이 없습니다.')).toBeVisible();
  });

  test('총 용돈 금액 표시', async ({ page }) => {
    await page.goto('/allowances?year=2025&month=1');

    // Check total amount section is displayed
    const summaryCard = page.locator('.bg-white.rounded-lg.shadow.p-6.mb-8');
    await expect(summaryCard.locator('text=이번 달 용돈 지출')).toBeVisible();

    // Total amount should be displayed with currency format
    await expect(summaryCard.locator('text=/₩[\\d,]+/')).toBeVisible();
  });

  test('이전 달 다음 달 네비게이션', async ({ page }) => {
    await page.goto('/allowances?year=2025&month=1');

    // Click previous month
    await page.locator('a:has-text("← 이전 달")').click();
    await expect(page).toHaveURL(/year=2024.*month=12|month=12.*year=2024/);
    await expect(page.locator('body')).toContainText('2024년 12월');

    // Click next month twice to get to February 2025 (await each navigation
    // so Turbo finishes before the next click).
    await page.locator('a:has-text("다음 달 →")').click();
    await expect(page).toHaveURL(/year=2025.*month=1|month=1.*year=2025/);
    await page.locator('a:has-text("다음 달 →")').click();
    await expect(page).toHaveURL(/year=2025.*month=2|month=2.*year=2025/);
    await expect(page.locator('body')).toContainText('2025년 2월');
  });

  test('연도 경계에서 네비게이션', async ({ page }) => {
    await page.goto('/allowances?year=2024&month=12');

    // Next month should be January 2025
    await page.locator('a:has-text("다음 달 →")').click();
    await expect(page).toHaveURL(/year=2025.*month=1|month=1.*year=2025/);
    await expect(page.locator('body')).toContainText('2025년 1월');

    // Previous month should be December 2024
    await page.locator('a:has-text("← 이전 달")').click();
    await expect(page).toHaveURL(/year=2024.*month=12|month=12.*year=2024/);
    await expect(page.locator('body')).toContainText('2024년 12월');
  });
});
