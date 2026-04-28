import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

// Transactions index uses:
// - Inline cell editing via data-controller="inline-edit"
// - Bulk actions via data-controller="bulk-select" (toolbar checkbox, no per-row edit/delete buttons)
// - Auto-filter form (year/month/category/institution selects + search debounce)
// - Duplicate modal trigger button ("중복 검사")
// Seed workspace: id=1, name="개인 가계부"
// Seed merchants: 마라탕 집 (식비 / 신한카드), 카카오T (교통), 쿠팡 (쇼핑)

test.describe('Transactions (결제 내역)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto('/workspaces/1/transactions');
    await page.waitForLoadState('networkidle');
  });

  // --- Page structure ---

  test('페이지 제목과 워크스페이스명 표시', async ({ page }) => {
    await expect(page.getByRole('heading', { name: '결제 내역' })).toBeVisible();
    await expect(page.getByRole('paragraph').filter({ hasText: '가계부' }).first()).toBeVisible();
  });

  test('결제 추가 버튼 노출 및 href 정확성', async ({ page }) => {
    const addBtn = page.getByRole('link', { name: '+ 결제 추가' });
    await expect(addBtn).toBeVisible();
    await expect(addBtn).toHaveAttribute('href', /\/workspaces\/\d+\/transactions\/new/);
  });

  test('컬럼 헤더가 현재 UI 순서와 일치한다', async ({ page }) => {
    // Financial institution column removed — now source-only metadata shown in details accordion.
    // Column order: 날짜 / 내역 / 금액 / 카테고리 / 출처(source metadata) / 댓글
    const headers = page.locator('thead th');
    await expect(headers.nth(0)).toContainText('날짜');
    await expect(headers.nth(1)).toContainText('내역');
    await expect(headers.nth(2)).toContainText('금액');
    await expect(headers.nth(3)).toContainText('카테고리');
    await expect(headers.nth(4)).toContainText('출처');
    await expect(headers.nth(5)).toContainText('댓글');
    await expect(page.locator('thead th:has-text("금융기관")')).not.toBeVisible();
  });

  test('합계 금액과 총 건수가 표시된다', async ({ page }) => {
    await expect(page.locator('text=합계:')).toBeVisible();
    await expect(page.locator('text=/₩[\\d,]+/').first()).toBeVisible();
    await expect(page.locator('text=/\\d+건/').first()).toBeVisible();
  });

  // --- Seed data ---

  test('시드 결제 데이터가 목록에 노출된다', async ({ page }) => {
    const list = page.locator('#transactions-list');
    await expect(list.locator('tr')).not.toHaveCount(0);
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).toBeVisible();
    await expect(list.getByText('쿠팡')).toBeVisible();
  });

  test('날짜 포맷이 yyyy.mm.dd 형식으로 표시된다', async ({ page }) => {
    const firstRow = page.locator('#transactions-list tr').first();
    const dateText = await firstRow.locator('td').first().textContent();
    expect(dateText?.trim()).toMatch(/\d{4}\.\d{2}\.\d{2}/);
  });

  // --- Inline editing ---

  test('금액 셀은 inline-edit 컨트롤러를 사용한다 (초기 표시/편집 상태)', async ({ page }) => {
    const firstRow = page.locator('#transactions-list tr').first();
    const amountEditor = firstRow.locator('[data-controller="inline-edit"][data-inline-edit-field-value="amount"]');
    await expect(amountEditor).toHaveCount(1);
    await expect(amountEditor.locator('[data-inline-edit-target="display"]')).toBeVisible();
    await expect(amountEditor.locator('[data-inline-edit-target="editor"]')).toBeHidden();
  });

  test('금액 셀 클릭 시 편집 input이 활성화된다', async ({ page }) => {
    const firstRow = page.locator('#transactions-list tr').first();
    const amountDisplay = firstRow.locator('[data-controller="inline-edit"][data-inline-edit-field-value="amount"] [data-inline-edit-target="display"]');
    await amountDisplay.click();
    const amountEditor = firstRow.locator('[data-controller="inline-edit"][data-inline-edit-field-value="amount"] [data-inline-edit-target="editor"]');
    await expect(amountEditor).toBeVisible();
  });

  // --- Bulk selection toolbar ---

  test('벌크 선택 툴바 체크박스가 렌더된다', async ({ page }) => {
    await expect(page.locator('[data-bulk-select-target="toolbarCheckbox"]')).toBeVisible();
  });

  test('개별 행에 수정/삭제 버튼이 없다', async ({ page }) => {
    const firstRow = page.locator('#transactions-list tr').first();
    await expect(firstRow.getByRole('button', { name: '수정' })).toHaveCount(0);
    await expect(firstRow.getByRole('button', { name: '삭제' })).toHaveCount(0);
  });

  test('전체 선택 체크박스 체크 시 선택 상태 툴바가 노출된다', async ({ page }) => {
    await page.locator('[data-bulk-select-target="toolbarCheckbox"]').check();
    await expect(page.locator('[data-bulk-select-target="toolbarSelected"]')).toBeVisible();
    await expect(page.locator('[data-bulk-select-target="toolbarCount"]')).not.toHaveText('0');
  });

  // --- Filters ---

  test('연도 필터 변경 시 URL이 자동 업데이트된다', async ({ page }) => {
    const currentYear = new Date().getFullYear();
    const yearSelect = page.locator('select#year');
    await expect(yearSelect).toHaveValue(currentYear.toString());

    await yearSelect.selectOption((currentYear - 1).toString());
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(new RegExp(`year=${currentYear - 1}`));
    await expect(yearSelect).toHaveValue((currentYear - 1).toString());
  });

  test('월 필터 변경 시 URL이 자동 업데이트된다', async ({ page }) => {
    await page.locator('select#month').selectOption('3');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(/month=3/);
    await expect(page.locator('select#month')).toHaveValue('3');
  });

  test('카테고리 필터 적용 시 해당 카테고리 결제만 표시된다', async ({ page }) => {
    await page.locator('select#category_id').selectOption({ label: '식비' });
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(/category_id=\d+/);
    const list = page.locator('#transactions-list');
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).not.toBeVisible();
  });

  test('금융기관 필터 드롭다운이 UI에 존재하지 않는다', async ({ page }) => {
    // Financial institution was demoted to source metadata.
    // The institution_id filter select is no longer rendered in the UI.
    await expect(page.locator('select#institution_id')).not.toBeVisible();
  });

  test('검색어 입력 시 디바운스 후 결과가 필터된다', async ({ page }) => {
    await page.locator('input[name="q"]').fill('마라탕');
    await page.waitForTimeout(600); // debounce
    await page.waitForLoadState('networkidle');
    const list = page.locator('#transactions-list');
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).not.toBeVisible();
    // No explicit submit button — auto-filter
    await expect(page.getByRole('button', { name: '검색' })).not.toBeVisible();
  });

  test('결과 없는 검색어 입력 시 빈 상태 메시지 표시', async ({ page }) => {
    await page.locator('input[name="q"]').fill('nonexistent_xyz_12345');
    await page.waitForTimeout(600);
    await page.waitForLoadState('networkidle');
    await expect(page.locator('#transactions-list').getByText('결제 내역이 없습니다.')).toBeVisible();
  });

  test('여러 필터를 동시에 적용할 수 있다', async ({ page }) => {
    await page.locator('select#category_id').selectOption({ label: '식비' });
    await page.waitForLoadState('networkidle');
    await page.locator('input[name="q"]').fill('마라탕');
    await page.waitForTimeout(600);
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(/category_id=/);
    await expect(page).toHaveURL(/q=/);
    const list = page.locator('#transactions-list');
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).not.toBeVisible();
  });

  // --- Duplicate check button ---

  test('중복 검사 버튼이 표시된다', async ({ page }) => {
    await expect(page.getByRole('button', { name: '중복 검사' })).toBeVisible();
  });
});
