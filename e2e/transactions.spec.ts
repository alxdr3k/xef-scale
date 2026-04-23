import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

// The transactions index uses inline cell-based editing (data-controller
// "inline-edit") rather than a per-row modal. Bulk actions (delete,
// allowance, category) run through the selection toolbar, not per-row
// buttons. Tests below reflect that current shape.

test.describe('Transactions (거래 내역)', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto('/workspaces/1/transactions');
  });

  test('컬럼 헤더가 현재 UI 순서와 일치한다', async ({ page }) => {
    const headers = page.locator('thead th');
    await expect(headers.nth(0)).toHaveText('날짜');
    await expect(headers.nth(1)).toHaveText('내역');
    await expect(headers.nth(2)).toHaveText('금액');
    await expect(headers.nth(3)).toHaveText('카테고리');
    await expect(headers.nth(4)).toHaveText('금융기관');
    await expect(headers.nth(5)).toHaveText('댓글');
  });

  test('거래 목록에 시드 데이터가 노출된다', async ({ page }) => {
    const list = page.locator('#transactions-list');
    await expect(list.locator('tr')).not.toHaveCount(0);
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).toBeVisible();
    await expect(list.getByText('쿠팡')).toBeVisible();
  });

  test('연도 필터가 자동 제출된다', async ({ page }) => {
    const currentYear = new Date().getFullYear();
    const yearSelect = page.locator('select#year');
    await expect(yearSelect).toHaveValue(currentYear.toString());

    await yearSelect.selectOption((currentYear - 1).toString());
    await expect(page).toHaveURL(new RegExp(`year=${currentYear - 1}`));
    await expect(yearSelect).toHaveValue((currentYear - 1).toString());
  });

  test('월 필터가 자동 제출된다', async ({ page }) => {
    await page.selectOption('select#month', '1');
    await expect(page).toHaveURL(/month=1/);
    await expect(page.locator('select#month')).toHaveValue('1');
  });

  test('카테고리 필터 자동 제출 및 결과 반영', async ({ page }) => {
    await page.selectOption('select#category_id', { label: '식비' });
    await expect(page).toHaveURL(/category_id=\d+/);

    const list = page.locator('#transactions-list');
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).not.toBeVisible();
  });

  test('금융기관 필터 자동 제출 및 결과 반영', async ({ page }) => {
    await page.selectOption('select#institution_id', { label: '신한카드' });
    await expect(page).toHaveURL(/institution_id=\d+/);

    const list = page.locator('#transactions-list');
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('쿠팡')).not.toBeVisible();
  });

  test('검색 자동 제출 (디바운스)', async ({ page }) => {
    await page.fill('input[name="q"]', '마라탕');
    await page.waitForTimeout(500);

    const list = page.locator('#transactions-list');
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).not.toBeVisible();

    await expect(page.getByRole('button', { name: '검색' })).not.toBeVisible();
    await expect(page.getByRole('button', { name: '찾기' })).not.toBeVisible();
  });

  test('빈 결과 상태 메시지', async ({ page }) => {
    await page.fill('input[name="q"]', 'nonexistent_transaction_xyz_12345');
    await page.waitForTimeout(500);
    const list = page.locator('#transactions-list');
    await expect(list.getByText('거래 내역이 없습니다.')).toBeVisible();
  });

  test('합계와 건수가 표시된다', async ({ page }) => {
    await expect(page.getByText('합계:')).toBeVisible();
    await expect(page.getByText('건')).toBeVisible();
  });

  test('여러 필터를 동시에 적용할 수 있다', async ({ page }) => {
    await page.selectOption('select#category_id', { label: '식비' });
    await page.fill('input[name="q"]', '마라탕');
    await page.waitForTimeout(500);

    await expect(page).toHaveURL(/category_id=/);
    await expect(page).toHaveURL(/q=/);

    const list = page.locator('#transactions-list');
    await expect(list.getByText('마라탕 집')).toBeVisible();
    await expect(list.getByText('카카오T')).not.toBeVisible();
  });

  test('페이지 제목과 워크스페이스 이름 표시', async ({ page }) => {
    await expect(page.getByText('거래 내역')).toBeVisible();
    await expect(page.getByText('가계부')).toBeVisible();
  });

  test('거래 추가 버튼 노출', async ({ page }) => {
    const addButton = page.getByRole('link', { name: '+ 거래 추가' });
    await expect(addButton).toBeVisible();
    await expect(addButton).toHaveAttribute('href', /\/workspaces\/\d+\/transactions\/new/);
  });

  test('날짜 포맷이 yyyy.mm.dd 형식으로 표시된다', async ({ page }) => {
    const firstRow = page.locator('#transactions-list tr').first();
    const dateCell = firstRow.locator('td').first();
    const dateText = await dateCell.textContent();
    expect(dateText?.trim()).toMatch(/\d{4}\.\d{2}\.\d{2}/);
  });

  test('금액 셀은 인라인 편집 컨트롤러를 사용한다', async ({ page }) => {
    const firstRow = page.locator('#transactions-list tr').first();
    const amountEditor = firstRow.locator('[data-controller="inline-edit"][data-inline-edit-field-value="amount"]');
    await expect(amountEditor).toHaveCount(1);
    // 초기에는 display가 보이고 편집 input은 숨겨져 있다
    await expect(amountEditor.locator('[data-inline-edit-target="display"]')).toBeVisible();
    await expect(amountEditor.locator('[data-inline-edit-target="editor"]')).toBeHidden();
  });

  test('벌크 선택 툴바가 렌더된다 (개별 삭제 버튼 없음)', async ({ page }) => {
    // 전체 선택 체크박스가 노출된다
    await expect(page.locator('[data-bulk-select-target="toolbarCheckbox"]')).toBeVisible();
    // 개별 행에 수정/삭제 버튼은 없다
    const firstRow = page.locator('#transactions-list tr').first();
    await expect(firstRow.getByRole('button', { name: '수정' })).toHaveCount(0);
    await expect(firstRow.getByRole('button', { name: '삭제' })).toHaveCount(0);
  });
});
