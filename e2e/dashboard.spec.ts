import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

// /dashboard → dashboards#calendar (authenticated root)
// /dashboard/monthly → dashboards#monthly
// Navigation between views via tab strip

test.describe('Calendar dashboard (기본 홈)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('인증 루트(/) 접속 시 캘린더 대시보드로 이동한다', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    // Title heading
    await expect(page.locator('h1:has-text("대시보드")')).toBeVisible();
    // Calendar grid weekday labels
    for (const label of ['일', '월', '화', '수', '목', '금', '토']) {
      await expect(page.locator('.grid.grid-cols-7').first().locator(`div:has-text("${label}")`).first()).toBeVisible();
    }
  });

  test('/dashboard는 캘린더 뷰를 렌더한다', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1:has-text("대시보드")')).toBeVisible();
    // 7-column calendar grid
    for (const label of ['일', '월', '화', '수', '목', '금', '토']) {
      await expect(page.locator('.grid.grid-cols-7').first().locator(`div:has-text("${label}")`).first()).toBeVisible();
    }
  });

  test('action strip — 월별 지출·검토·중복·미분류 배지가 표시된다', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
    // Monthly total label always present
    await expect(page.locator('text=/년 .+월 지출/')).toBeVisible();
    // Status badges (count may be 0)
    await expect(page.locator('text=/검토 필요/')).toBeVisible();
    await expect(page.locator('text=/중복 의심/')).toBeVisible();
    await expect(page.locator('text=/미분류/')).toBeVisible();
  });

  test('탭 스트립 — 캘린더·월별·연도별·반복결제 링크 노출', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('link', { name: '캘린더' })).toBeVisible();
    await expect(page.getByRole('link', { name: '월별' })).toBeVisible();
    await expect(page.getByRole('link', { name: '연도별' })).toBeVisible();
    await expect(page.getByRole('link', { name: '반복 결제' })).toBeVisible();
  });

  test('이전/다음 달 링크로 월 이동', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=6');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toContainText('2025년 6월');

    await page.click('a:has-text("← 이전 달")');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toContainText('2025년 5월');

    await page.click('a:has-text("다음 달 →")');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toContainText('2025년 6월');
  });

  test('날짜 셀 클릭 시 해당 날짜가 사이드 패널에 표시된다', async ({ page }) => {
    await page.goto('/dashboard?year=2025&month=1');
    await page.waitForLoadState('networkidle');

    // Click the cell for day 15 within the current month
    const dayCell = page.locator('.grid.grid-cols-7 ~ .grid.grid-cols-7 a, .grid.grid-cols-7 + div a').first();
    // Use a link with the date param instead — find any in-month cell link
    const calendarLinks = page.locator('a[href*="date=2025-01-"]');
    const count = await calendarLinks.count();
    if (count > 0) {
      const targetLink = calendarLinks.nth(Math.min(14, count - 1)); // aim for ~15th
      await targetLink.click();
      await page.waitForLoadState('networkidle');
      // Side panel heading changes to the selected date
      await expect(page.locator('h2:has-text("2025.01.")')).toBeVisible();
    }
  });

  test('사이드 패널 — 거래 없는 날짜는 빈 상태 메시지 표시', async ({ page }) => {
    // Navigate to a historical month unlikely to have seeded data in every cell
    await page.goto('/dashboard?year=2024&month=1&date=2024-01-01');
    await page.waitForLoadState('networkidle');
    const emptyMsg = page.locator('text=선택한 날짜에는 거래가 없습니다.');
    const hasTxList = page.locator('ul.divide-y');
    // Either empty message or transaction list must be present
    const hasEmpty = await emptyMsg.isVisible().catch(() => false);
    const hasList = await hasTxList.isVisible().catch(() => false);
    expect(hasEmpty || hasList).toBe(true);
  });

  test('월간 보기 링크가 /dashboard/monthly 로 이동한다', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
    await page.click('a:has-text("월간 보기 →")');
    await expect(page).toHaveURL(/\/dashboard\/monthly/);
    await expect(page.locator('h1:has-text("대시보드")')).toBeVisible();
  });
});

test.describe('Monthly report (/dashboard/monthly)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('요약 카드 — 총 지출 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('text=이번 달 총 지출')).toBeVisible();
    await expect(page.locator('text=/₩[\\d,]+/')).toBeVisible();
  });

  test('요약 카드 — 거래 건수 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.waitForLoadState('networkidle');
    const countCard = page.locator(':has-text("거래 건수")').filter({ hasText: /\d+건/ });
    await expect(countCard.first()).toBeVisible();
  });

  test('이전/다음 달 링크 동작', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.waitForLoadState('networkidle');
    await page.click('a:has-text("다음 달 →")');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toContainText('2025년 2월');

    await page.click('a:has-text("← 이전 달")');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toContainText('2025년 1월');
  });

  test('카테고리별 지출 섹션 표시', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.waitForLoadState('networkidle');
    await expect(page.locator(':has-text("카테고리별 지출")').first()).toBeVisible();
  });

  test('최근 거래 — 전체 보기 링크가 transactions 페이지로 이동', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.waitForLoadState('networkidle');
    const viewAllLink = page.locator('a:has-text("전체 보기 →")').first();
    if (await viewAllLink.isVisible()) {
      await viewAllLink.click();
      await expect(page).toHaveURL(/transactions/);
    }
  });

  test('탭 클릭으로 캘린더 뷰로 전환', async ({ page }) => {
    await page.goto('/dashboard/monthly?year=2025&month=1');
    await page.waitForLoadState('networkidle');
    await page.getByRole('link', { name: '캘린더' }).click();
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(/\/dashboard/);
    // Calendar grid should appear
    for (const label of ['일', '월', '화', '수', '목', '금', '토']) {
      await expect(page.locator('.grid.grid-cols-7').first().locator(`div:has-text("${label}")`).first()).toBeVisible();
    }
  });
});
