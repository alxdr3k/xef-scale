import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers';

test.describe('Transactions', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto('/workspaces/1/transactions');
  });

  // Test 1: Table rendering with correct column headers
  test('displays transactions table with correct column headers and data', async ({ page }) => {
    // Verify column header order: 날짜/내역/금액/카테고리/금융기관/작업
    const headers = page.locator('thead th');
    await expect(headers.nth(0)).toHaveText('날짜');
    await expect(headers.nth(1)).toHaveText('내역');
    await expect(headers.nth(2)).toHaveText('금액');
    await expect(headers.nth(3)).toHaveText('카테고리');
    await expect(headers.nth(4)).toHaveText('금융기관');
    await expect(headers.nth(5)).toHaveText('작업');

    // Verify transaction data is displayed
    const transactionList = page.locator('#transactions-list');
    await expect(transactionList.locator('tr')).toHaveCount({ minimum: 1 });

    // Verify merchants are displayed
    await expect(transactionList.getByText('마라탕 집')).toBeVisible();
    await expect(transactionList.getByText('카카오T')).toBeVisible();
    await expect(transactionList.getByText('쿠팡')).toBeVisible();

    // Verify amounts are displayed
    await expect(page.getByText('₩12,000')).toBeVisible();
    await expect(page.getByText('₩8,500')).toBeVisible();
    await expect(page.getByText('₩45,000')).toBeVisible();

    // Verify categories are displayed
    await expect(page.getByText('식비')).toBeVisible();
    await expect(page.getByText('교통/자동차')).toBeVisible();
    await expect(page.getByText('쇼핑')).toBeVisible();

    // Verify financial institutions are displayed
    await expect(page.getByText('신한카드')).toBeVisible();
    await expect(page.getByText('하나카드')).toBeVisible();
    await expect(page.getByText('토스뱅크')).toBeVisible();
  });

  // Test 2: Year filter auto-submit
  test('filters transactions by year automatically', async ({ page }) => {
    const currentYear = new Date().getFullYear();

    // Verify current year is selected
    const yearSelect = page.locator('select#year');
    await expect(yearSelect).toHaveValue(currentYear.toString());

    // Change to previous year
    await yearSelect.selectOption((currentYear - 1).toString());

    // Verify URL updated with year parameter
    await expect(page).toHaveURL(new RegExp(`year=${currentYear - 1}`));

    // Verify selected year is maintained
    await expect(yearSelect).toHaveValue((currentYear - 1).toString());
  });

  // Test 3: Month filter auto-submit
  test('filters transactions by month automatically', async ({ page }) => {
    // Select month
    await page.selectOption('select#month', '1');

    // Verify URL contains month parameter
    await expect(page).toHaveURL(/month=1/);

    // Verify selected month is maintained
    const monthSelect = page.locator('select#month');
    await expect(monthSelect).toHaveValue('1');
  });

  // Test 4: Category filter auto-submit
  test('filters transactions by category automatically', async ({ page }) => {
    // Select category
    await page.selectOption('select#category_id', { label: '식비' });

    // Verify URL contains category_id parameter
    await expect(page).toHaveURL(/category_id=\d+/);

    // Verify only food category is displayed
    const transactionList = page.locator('#transactions-list');
    await expect(transactionList.getByText('마라탕 집')).toBeVisible();
    await expect(transactionList.getByText('카카오T')).not.toBeVisible();
  });

  // Test 5: Financial institution filter auto-submit
  test('filters transactions by financial institution automatically', async ({ page }) => {
    // Select financial institution
    await page.selectOption('select#institution_id', { label: '신한카드' });

    // Verify URL contains institution_id parameter
    await expect(page).toHaveURL(/institution_id=\d+/);

    // Verify only Shinhan Card transactions are displayed
    const transactionList = page.locator('#transactions-list');
    await expect(transactionList.getByText('마라탕 집')).toBeVisible();
    await expect(transactionList.getByText('카카오T')).not.toBeVisible();
    await expect(transactionList.getByText('쿠팡')).not.toBeVisible();
  });

  // Test 6: Text search with debounce
  test('filters transactions by text search with debounce', async ({ page }) => {
    // Enter search query
    await page.fill('input[name="q"]', '마라탕');

    // Wait for debounce (auto-filter controller debounce time)
    await page.waitForTimeout(500);

    // Verify search results
    const transactionList = page.locator('#transactions-list');
    await expect(transactionList.getByText('마라탕 집')).toBeVisible();
    await expect(transactionList.getByText('카카오T')).not.toBeVisible();
    await expect(transactionList.getByText('쿠팡')).not.toBeVisible();

    // Verify no search button exists (auto-submit)
    await expect(page.getByRole('button', { name: '검색' })).not.toBeVisible();
    await expect(page.getByRole('button', { name: '찾기' })).not.toBeVisible();
  });

  // Test 7: Open edit modal
  test('opens edit modal when clicking edit button', async ({ page }) => {
    // Click edit button on first transaction
    const firstRow = page.locator('#transactions-list tr').first();
    await firstRow.getByRole('button', { name: '수정' }).click();

    // Verify modal is opened
    const modal = page.locator('#edit-modal');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h3')).toHaveText('거래 수정');
  });

  // Test 8: Edit modal form fields
  test('displays all form fields in edit modal', async ({ page }) => {
    // Click edit button
    const firstRow = page.locator('#transactions-list tr').first();
    await firstRow.getByRole('button', { name: '수정' }).click();

    // Wait for modal form to load
    const modal = page.locator('#edit-modal');
    await expect(modal.locator('form')).toBeVisible({ timeout: 5000 });

    // Verify form fields exist
    await expect(modal.locator('input[name="transaction[date]"]')).toBeVisible();
    await expect(modal.locator('input[name="transaction[merchant]"]')).toBeVisible();
    await expect(modal.locator('input[name="transaction[amount]"]')).toBeVisible();
    await expect(modal.locator('select[name="transaction[category_id]"]')).toBeVisible();
    await expect(modal.locator('select[name="transaction[financial_institution_id]"]')).toBeVisible();
    await expect(modal.locator('input[name="transaction[description]"]')).toBeVisible();
    await expect(modal.locator('textarea[name="transaction[notes]"]')).toBeVisible();

    // Verify allowance checkbox exists
    await expect(modal.locator('input[type="checkbox"][name="allowance"]')).toBeVisible();
    await expect(modal.getByText('용돈으로 표시')).toBeVisible();
  });

  // Test 9: Edit transaction and save
  test('edits transaction and saves successfully', async ({ page }) => {
    // Click edit button
    const firstRow = page.locator('#transactions-list tr').first();
    await firstRow.getByRole('button', { name: '수정' }).click();

    // Wait for modal form to load
    const modal = page.locator('#edit-modal');
    await expect(modal.locator('form')).toBeVisible({ timeout: 5000 });

    // Modify data
    await modal.locator('input[name="transaction[merchant]"]').fill('수정된 가맹점');
    await modal.locator('input[name="transaction[amount]"]').fill('15000');
    await modal.getByRole('button', { name: '수정' }).click();

    // Verify modal is closed
    await expect(modal).not.toBeVisible({ timeout: 5000 });

    // Verify modified data is displayed
    await expect(page.getByText('수정된 가맹점')).toBeVisible();
    await expect(page.getByText('₩15,000')).toBeVisible();
  });

  // Test 10: Close modal with ESC key
  test('closes modal when pressing ESC key', async ({ page }) => {
    // Click edit button
    const firstRow = page.locator('#transactions-list tr').first();
    await firstRow.getByRole('button', { name: '수정' }).click();

    // Verify modal is opened
    const modal = page.locator('#edit-modal');
    await expect(modal).toBeVisible();

    // Press ESC key
    await page.keyboard.press('Escape');

    // Verify modal is closed
    await expect(modal).not.toBeVisible({ timeout: 5000 });
  });

  // Test 11: Close modal by clicking background overlay
  test('closes modal when clicking background overlay', async ({ page }) => {
    // Click edit button
    const firstRow = page.locator('#transactions-list tr').first();
    await firstRow.getByRole('button', { name: '수정' }).click();

    // Verify modal is opened
    const modal = page.locator('#edit-modal');
    await expect(modal).toBeVisible();

    // Click background overlay (bg-gray-500 div)
    await modal.locator('.bg-gray-500').click();

    // Verify modal is closed
    await expect(modal).not.toBeVisible({ timeout: 5000 });
  });

  // Test 12: Allowance checkbox functionality
  test('toggles allowance checkbox in edit modal', async ({ page }) => {
    // Click edit button
    const firstRow = page.locator('#transactions-list tr').first();
    await firstRow.getByRole('button', { name: '수정' }).click();

    // Wait for modal form to load
    const modal = page.locator('#edit-modal');
    await expect(modal.locator('form')).toBeVisible({ timeout: 5000 });

    // Check allowance checkbox
    await modal.locator('input[name="allowance"]').check();
    await modal.getByRole('button', { name: '수정' }).click();

    // Wait for modal to close
    await expect(modal).not.toBeVisible({ timeout: 5000 });

    // Verify page is still on transactions page
    await expect(page).toHaveURL(/\/workspaces\/\d+\/transactions/);
  });

  // Test 13: Delete with confirmation dialog
  test('deletes transaction with confirmation dialog', async ({ page }) => {
    // Verify transaction exists
    const transactionRow = page.locator('#transactions-list tr').first();
    const merchantText = await transactionRow.locator('td').nth(1).textContent();
    await expect(transactionRow).toBeVisible();

    // Set up dialog handler to accept
    page.on('dialog', dialog => dialog.accept());

    // Click delete button
    await transactionRow.getByRole('button', { name: '삭제' }).click();

    // Verify transaction is removed
    await expect(page.getByText(merchantText!.trim())).not.toBeVisible({ timeout: 5000 });
  });

  // Test 14: Cancel deletion
  test('cancels deletion when dismissing confirmation dialog', async ({ page }) => {
    // Verify transaction exists
    const transactionRow = page.locator('#transactions-list tr').first();
    const merchantText = await transactionRow.locator('td').nth(1).textContent();
    await expect(transactionRow).toBeVisible();

    // Set up dialog handler to dismiss
    page.on('dialog', dialog => dialog.dismiss());

    // Click delete button
    await transactionRow.getByRole('button', { name: '삭제' }).click();

    // Verify transaction still exists
    await expect(page.getByText(merchantText!.trim())).toBeVisible();
  });

  // Test 15: Empty state display
  test('displays empty state when no transactions', async ({ page }) => {
    // Apply a filter that returns no results
    await page.fill('input[name="q"]', 'nonexistent_transaction_xyz_12345');
    await page.waitForTimeout(500);

    // Verify empty state message
    const transactionList = page.locator('#transactions-list');
    await expect(transactionList.getByText('거래 내역이 없습니다.')).toBeVisible();
  });

  // Test 16: Transaction total display
  test('displays total amount of transactions', async ({ page }) => {
    // Verify total is displayed
    await expect(page.getByText('합계:')).toBeVisible();

    // Verify count is displayed
    await expect(page.getByText('건')).toBeVisible();
  });

  // Test 17: Combined filters
  test('combines multiple filters', async ({ page }) => {
    // Apply category filter
    await page.selectOption('select#category_id', { label: '식비' });

    // Apply search query
    await page.fill('input[name="q"]', '마라탕');

    // Wait for debounce
    await page.waitForTimeout(500);

    // Verify both filters are applied in URL
    await expect(page).toHaveURL(/category_id=/);
    await expect(page).toHaveURL(/q=/);

    // Verify filtered results
    const transactionList = page.locator('#transactions-list');
    await expect(transactionList.getByText('마라탕 집')).toBeVisible();
    await expect(transactionList.getByText('카카오T')).not.toBeVisible();
    await expect(transactionList.getByText('쿠팡')).not.toBeVisible();
  });

  // Test 18: Page title and workspace name
  test('displays page title and workspace name', async ({ page }) => {
    await expect(page.getByText('거래 내역')).toBeVisible();
    await expect(page.getByText('가계부')).toBeVisible();
  });

  // Test 19: Add transaction button
  test('displays add transaction button', async ({ page }) => {
    const addButton = page.getByRole('link', { name: '+ 거래 추가' });
    await expect(addButton).toBeVisible();
    await expect(addButton).toHaveAttribute('href', /\/workspaces\/\d+\/transactions\/new/);
  });

  // Test 20: Date format display
  test('displays transaction dates in correct format', async ({ page }) => {
    // Verify date is displayed in yyyy.mm.dd format
    const firstRow = page.locator('#transactions-list tr').first();
    const dateCell = firstRow.locator('td').first();
    const dateText = await dateCell.textContent();

    // Check date format matches yyyy.mm.dd pattern
    expect(dateText?.trim()).toMatch(/^\d{4}\.\d{2}\.\d{2}$/);
  });
});
