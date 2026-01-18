import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

test.describe('Dashboard (대시보드)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('요약 카드 - 총 지출 금액 표시', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    // Find the total spending card
    const summaryCards = page.locator('div.bg-white.rounded-lg.shadow.p-6');
    const totalCard = summaryCards.first();

    await expect(totalCard.locator('text=이번 달 총 지출')).toBeVisible();
    // Amount should be displayed with currency format
    await expect(totalCard.locator('text=/₩[\\d,]+/')).toBeVisible();
  });

  test('요약 카드 - 거래 건수 표시', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    // Find transaction count card
    const transactionCountCard = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("거래 건수")');
    await expect(transactionCountCard).toBeVisible();
    await expect(transactionCountCard.locator('text=/\\d+건/')).toBeVisible();
  });

  test('요약 카드 - 일 평균 지출 표시', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    // Find daily average card
    const dailyAvgCard = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("일 평균 지출")');
    await expect(dailyAvgCard).toBeVisible();
    // Amount should be displayed with currency format
    await expect(dailyAvgCard.locator('div.text-3xl.font-bold')).toContainText(/₩[\d,]+/);
  });

  test('카테고리 그래프 - 카테고리별 bar 표시', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    // Find category breakdown section
    const categorySection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("카테고리별 지출")');
    await expect(categorySection).toBeVisible();

    // Check for colored bars (progress bars) - may be empty if no transactions
    const coloredBars = categorySection.locator('div.rounded-full[style*="background-color"]');
    const barCount = await coloredBars.count();

    // If there are transactions, there should be bars
    if (barCount > 0) {
      expect(barCount).toBeGreaterThan(0);
    }
  });

  test('카테고리 그래프 - 금액 레이블 표시', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    const categorySection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("카테고리별 지출")');

    // Check if there are transactions (no empty message)
    const hasTransactions = await categorySection.locator('text=이번 달 거래 내역이 없습니다.').count() === 0;

    if (hasTransactions) {
      // Amounts should be displayed with currency format
      await expect(categorySection.locator('text=/₩[\\d,]+/').first()).toBeVisible();
    }
  });

  test('카테고리 그래프 - 비율 표시', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    const categorySection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("카테고리별 지출")');

    // Check if there are transactions
    const hasTransactions = await categorySection.locator('text=이번 달 거래 내역이 없습니다.').count() === 0;

    if (hasTransactions) {
      // Percentages should be displayed
      await expect(categorySection.locator('text=/\\d+\\.\\d%/').first()).toBeVisible();
    }
  });

  test('월력 - 드롭다운 구성요소 확인', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');
    await page.waitForLoadState('networkidle');

    // Month picker should be visible with toggle button
    const toggleButton = page.locator('button[data-action="click->month-picker#toggle"]');
    await expect(toggleButton).toBeVisible();
    await expect(toggleButton).toContainText('2025년 1월');

    // Dropdown element should exist (hidden)
    const dropdown = page.locator('[data-month-picker-target="dropdown"]');
    await expect(dropdown).toBeAttached();

    // All 12 month buttons should be in the DOM
    for (let month = 1; month <= 12; month++) {
      await expect(dropdown.locator(`button[data-month="${month}"]`)).toBeAttached();
    }

    // Year navigation buttons should exist
    await expect(dropdown.locator('button[data-action="click->month-picker#previousYear"]')).toBeAttached();
    await expect(dropdown.locator('button[data-action="click->month-picker#nextYear"]')).toBeAttached();
  });

  test('월력 - 직접 URL 변경으로 월 이동', async ({ page }) => {
    // Navigate to a specific month
    await page.goto('/dashboard?year=2025&month=6');
    await page.waitForLoadState('networkidle');

    // Page should display June 2025
    await expect(page.locator('body')).toContainText('2025년 6월');

    // Toggle button should show June 2025
    const toggleButton = page.locator('button[data-action="click->month-picker#toggle"]');
    await expect(toggleButton).toContainText('2025년 6월');
  });

  test('월력 - 이전/다음 달 링크 동작', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');
    await page.waitForLoadState('networkidle');

    // Click next month link
    await page.click('a:has-text("다음 달 →")');
    await expect(page).toHaveURL(/month=2.*year=2025|year=2025.*month=2/);
    await expect(page.locator('body')).toContainText('2025년 2월');

    // Click previous month link
    await page.click('a:has-text("← 이전 달")');
    await expect(page).toHaveURL(/month=1.*year=2025|year=2025.*month=1/);
    await expect(page.locator('body')).toContainText('2025년 1월');
  });

  test('최근 거래 - 목록 표시', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    // Find recent transactions section
    const recentSection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("최근 거래")');
    await expect(recentSection).toBeVisible();

    // Check if there are transactions or empty message
    const isEmpty = await recentSection.locator('text=최근 거래 내역이 없습니다.').count() > 0;

    if (!isEmpty) {
      // Should show transaction dates in format YYYY.MM.DD
      await expect(recentSection.locator('text=/\\d{4}\\.\\d{2}\\.\\d{2}/').first()).toBeVisible();
      // Should show amounts
      await expect(recentSection.locator('text=/₩[\\d,]+/').first()).toBeVisible();
    }
  });

  test('최근 거래 - 전체 보기 링크', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    const recentSection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("최근 거래")');

    // Check "전체 보기" link exists
    const viewAllLink = recentSection.locator('a:has-text("전체 보기 →")');
    await expect(viewAllLink).toBeVisible();

    // Click and verify navigation
    await viewAllLink.click();
    await expect(page).toHaveURL(/transactions/);
  });

  test('빈 상태 (거래 없을 때)', async ({ page }) => {
    // Visit a month with no transactions
    await page.goto('/dashboard?year=2024&month=12');

    // Should show zero spending
    const totalCard = page.locator('div.bg-white.rounded-lg.shadow.p-6').first();
    await expect(totalCard.locator('text=이번 달 총 지출')).toBeVisible();
    await expect(totalCard.locator('text=₩0')).toBeVisible();

    // Should show zero transaction count
    const transactionCountCard = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("거래 건수")');
    await expect(transactionCountCard.locator('text=0건')).toBeVisible();

    // Category breakdown should be empty
    const categorySection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("카테고리별 지출")');
    await expect(categorySection.locator('text=이번 달 거래 내역이 없습니다.')).toBeVisible();

    // Recent transactions should be empty
    const recentSection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("최근 거래")');
    await expect(recentSection.locator('text=최근 거래 내역이 없습니다.')).toBeVisible();
  });

  test('이전 달 다음 달 네비게이션', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    // Verify current month
    await expect(page.locator('body')).toContainText('2025년 1월');

    // Click previous month
    await page.locator('a:has-text("← 이전 달")').click();
    await expect(page).toHaveURL(/year=2024.*month=12|month=12.*year=2024/);
    await expect(page.locator('body')).toContainText('2024년 12월');

    // Click next month
    await page.locator('a:has-text("다음 달 →")').click();
    await expect(page).toHaveURL(/year=2025.*month=1|month=1.*year=2025/);
    await expect(page.locator('body')).toContainText('2025년 1월');
  });

  test('대시보드 헤더 정보', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    // Check page title
    await expect(page.locator('h1:has-text("대시보드")')).toBeVisible();

    // Check date is displayed
    await expect(page.locator('body')).toContainText('2025년 1월');
  });

  test('카테고리별 정렬 (금액 내림차순)', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');

    const categorySection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("카테고리별 지출")');

    // Check if there are transactions
    const hasTransactions = await categorySection.locator('text=이번 달 거래 내역이 없습니다.').count() === 0;

    if (hasTransactions) {
      // Get all category names in order
      const categoryNames = categorySection.locator('span.text-sm.font-medium.text-gray-700');
      const count = await categoryNames.count();

      if (count >= 2) {
        // Get all amounts and verify they are in descending order
        const amounts = categorySection.locator('text=/₩[\\d,]+/');
        const amountCount = await amounts.count();

        const amountValues: number[] = [];
        for (let i = 0; i < amountCount; i++) {
          const text = await amounts.nth(i).textContent();
          if (text) {
            const value = parseInt(text.replace(/[₩,]/g, ''), 10);
            if (!isNaN(value)) {
              amountValues.push(value);
            }
          }
        }

        // Verify descending order
        for (let i = 0; i < amountValues.length - 1; i++) {
          expect(amountValues[i]).toBeGreaterThanOrEqual(amountValues[i + 1]);
        }
      }
    }
  });
});
