import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

// /dashboard now points at the calendar home. Monthly assertions live
// against /dashboard/monthly so they stay valid when the default home
// evolves further.

test.describe('Calendar dashboard (기본 홈)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('루트 접속 시 캘린더 대시보드가 열린다', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1:has-text("대시보드")')).toBeVisible();
    await expect(page.locator('body')).toContainText(/\d{4}년 \d{1,2}월/);
  });

  test('/dashboard는 캘린더 뷰를 렌더한다', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
    // Calendar grid has weekday headers 일 월 화 수 목 금 토
    for (const label of ['일', '월', '화', '수', '목', '금', '토']) {
      await expect(page.locator(`.grid.grid-cols-7 >> text=${label}`).first()).toBeVisible();
    }
  });

  test('이전/다음 달 링크 동작', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=6');
    await expect(page.locator('body')).toContainText('2025년 6월');

    await page.click('a:has-text("← 이전 달")');
    await expect(page.locator('body')).toContainText('2025년 5월');

    await page.click('a:has-text("다음 달 →")');
    await expect(page.locator('body')).toContainText('2025년 6월');
  });
});

test.describe('Monthly report (/dashboard/monthly)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('요약 카드 - 총 지출 금액 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');

    const summaryCards = page.locator('div.bg-white.rounded-lg.shadow.p-6');
    const totalCard = summaryCards.first();

    await expect(totalCard.locator('text=이번 달 총 지출')).toBeVisible();
    await expect(totalCard.locator('text=/₩[\\d,]+/')).toBeVisible();
  });

  test('요약 카드 - 거래 건수 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    const transactionCountCard = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("거래 건수")');
    await expect(transactionCountCard).toBeVisible();
    await expect(transactionCountCard.locator('text=/\\d+건/')).toBeVisible();
  });

  test('요약 카드 - 일 평균 지출 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    const dailyAvgCard = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("일 평균 지출")');
    await expect(dailyAvgCard).toBeVisible();
    await expect(dailyAvgCard.locator('div.text-3xl.font-bold')).toContainText(/₩[\d,]+/);
  });

  test('카테고리 그래프 - 섹션 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    const categorySection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("카테고리별 지출")');
    await expect(categorySection).toBeVisible();
  });

  test('월력 - 드롭다운 구성요소 확인', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.waitForLoadState('networkidle');

    const toggleButton = page.locator('button[data-action="click->month-picker#toggle"]');
    await expect(toggleButton).toBeVisible();
    await expect(toggleButton).toContainText('2025년 1월');

    const dropdown = page.locator('[data-month-picker-target="dropdown"]');
    await expect(dropdown).toBeAttached();

    for (let month = 1; month <= 12; month++) {
      await expect(dropdown.locator(`button[data-month="${month}"]`)).toBeAttached();
    }
  });

  test('월력 - 직접 URL 변경으로 월 이동', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=6');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toContainText('2025년 6월');
  });

  test('월력 - 이전/다음 달 링크 동작', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.click('a:has-text("다음 달 →")');
    await expect(page.locator('body')).toContainText('2025년 2월');

    await page.click('a:has-text("← 이전 달")');
    await expect(page.locator('body')).toContainText('2025년 1월');
  });

  test('최근 거래 - 섹션 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    const recentSection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("최근 거래")');
    await expect(recentSection).toBeVisible();
  });

  test('최근 거래 - 전체 보기 링크', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    const recentSection = page.locator('div.bg-white.rounded-lg.shadow.p-6:has-text("최근 거래")');
    const viewAllLink = recentSection.locator('a:has-text("전체 보기 →")');
    await expect(viewAllLink).toBeVisible();

    await viewAllLink.click();
    await expect(page).toHaveURL(/transactions/);
  });

  test('빈 상태 - 거래 없을 때', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2024&month=12');

    const totalCard = page.locator('div.bg-white.rounded-lg.shadow.p-6').first();
    await expect(totalCard.locator('text=이번 달 총 지출')).toBeVisible();
    await expect(totalCard.locator('text=₩0')).toBeVisible();
  });

  test('대시보드 헤더 정보', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await expect(page.locator('h1:has-text("대시보드")')).toBeVisible();
    await expect(page.locator('body')).toContainText('2025년 1월');
  });
});
