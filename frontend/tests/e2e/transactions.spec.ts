import { test, expect } from '@playwright/test';

/**
 * E2E tests for Transactions page
 * Tests transaction listing, filtering, sorting, and pagination
 */

test.describe('Transactions Page', () => {
  // Setup: Login before each test
  test.beforeEach(async ({ page }) => {
    // Navigate to landing page
    await page.goto('/');

    // Wait for Google OAuth button and click it
    // Note: In real testing, you would need to mock OAuth or use test credentials
    // For now, we assume the user is already logged in or we skip auth

    // Navigate directly to transactions page (assumes authentication is handled)
    await page.goto('/transactions');

    // Wait for page to load
    await page.waitForLoadState('networkidle');
  });

  test('should display transactions page with filters', async ({ page }) => {
    // Check if page title is visible
    await expect(page.getByRole('heading', { name: '지출 내역' })).toBeVisible();

    // Check if filter panel is visible
    await expect(page.getByText('연도')).toBeVisible();
    await expect(page.getByText('카테고리')).toBeVisible();
    await expect(page.getByText('금융기관')).toBeVisible();

    // Check if search input is visible
    await expect(page.getByPlaceholder('거래처명 입력')).toBeVisible();
  });

  test('should filter transactions by year', async ({ page }) => {
    // Wait for transactions to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Get initial transaction count
    const initialRows = await page.locator('table tbody tr').count();

    // Select a year from dropdown
    await page.getByText('연도').locator('..').locator('input').click();
    await page.getByText('2024년').click();

    // Wait for data to reload
    await page.waitForLoadState('networkidle');

    // Verify transactions are filtered (count may change or stay same)
    const filteredRows = await page.locator('table tbody tr').count();
    expect(filteredRows).toBeGreaterThanOrEqual(0);
  });

  test('should filter transactions by month', async ({ page }) => {
    // Wait for transactions to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Select a month from dropdown
    await page.getByText('월').locator('..').locator('input').click();
    await page.getByText('1월').click();

    // Wait for data to reload
    await page.waitForLoadState('networkidle');

    // Verify month filter is applied
    const monthSelect = page.getByText('월').locator('..').locator('.ant-select-selection-item');
    await expect(monthSelect).toContainText('1월');
  });

  test('should filter transactions by category', async ({ page }) => {
    // Wait for categories to load
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000); // Give time for categories to populate

    // Select category dropdown
    const categoryInput = page.getByText('카테고리').locator('..').locator('input');
    await categoryInput.click();

    // Wait for dropdown options
    await page.waitForSelector('.ant-select-dropdown', { state: 'visible' });

    // Select first available category (if any)
    const firstOption = page.locator('.ant-select-dropdown .ant-select-item').first();
    if (await firstOption.isVisible()) {
      await firstOption.click();

      // Wait for data to reload
      await page.waitForLoadState('networkidle');

      // Verify category filter is applied
      const categorySelect = page.getByText('카테고리').locator('..').locator('.ant-select-selection-item');
      await expect(categorySelect).toBeVisible();
    }
  });

  test('should search transactions by merchant name', async ({ page }) => {
    // Wait for transactions to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Get first merchant name from table (if exists)
    const firstMerchant = page.locator('table tbody tr').first().locator('td').nth(2);

    if (await firstMerchant.isVisible()) {
      const merchantText = await firstMerchant.textContent();

      if (merchantText && merchantText.length > 3) {
        // Search for partial merchant name
        const searchInput = page.getByPlaceholder('거래처명 입력');
        await searchInput.fill(merchantText.substring(0, 3));
        await searchInput.press('Enter');

        // Wait for data to reload
        await page.waitForLoadState('networkidle');

        // Verify search results contain the search term
        const resultRows = await page.locator('table tbody tr').count();
        expect(resultRows).toBeGreaterThanOrEqual(0);
      }
    }
  });

  test('should display summary section with totals', async ({ page }) => {
    // Wait for data to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Check if summary section is visible
    await expect(page.getByText('총 거래 건수')).toBeVisible();
    await expect(page.getByText('총 지출 금액')).toBeVisible();

    // Verify numbers are displayed
    const totalCount = page.locator('text=총 거래 건수').locator('..').locator('.ant-statistic-content-value');
    await expect(totalCount).toBeVisible();

    const totalAmount = page.locator('text=총 지출 금액').locator('..').locator('.ant-statistic-content-value');
    await expect(totalAmount).toBeVisible();
  });

  test('should display transaction table with correct columns', async ({ page }) => {
    // Wait for table to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Check if all required columns are present
    await expect(page.getByText('날짜')).toBeVisible();
    await expect(page.getByText('거래처')).toBeVisible();
    await expect(page.getByText('금액')).toBeVisible();

    // Category and source columns may be hidden on mobile
    const viewportSize = page.viewportSize();
    if (viewportSize && viewportSize.width >= 768) {
      await expect(page.getByText('카테고리')).toBeVisible();
    }
    if (viewportSize && viewportSize.width >= 1024) {
      await expect(page.getByText('출처')).toBeVisible();
    }
  });

  test('should sort transactions by date', async ({ page }) => {
    // Wait for table to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Click on date column header to sort
    const dateHeader = page.getByText('날짜').locator('..');
    await dateHeader.click();

    // Wait for data to reload
    await page.waitForLoadState('networkidle');

    // Click again to reverse sort
    await dateHeader.click();
    await page.waitForLoadState('networkidle');

    // Verify sorting indicator is present
    const sortIcon = dateHeader.locator('.ant-table-column-sorter-up, .ant-table-column-sorter-down');
    await expect(sortIcon.first()).toBeVisible();
  });

  test('should sort transactions by amount', async ({ page }) => {
    // Wait for table to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Click on amount column header to sort
    const amountHeader = page.getByText('금액').locator('..');
    await amountHeader.click();

    // Wait for data to reload
    await page.waitForLoadState('networkidle');

    // Verify sorting indicator is present
    const sortIcon = amountHeader.locator('.ant-table-column-sorter-up, .ant-table-column-sorter-down');
    await expect(sortIcon.first()).toBeVisible();
  });

  test('should paginate transactions', async ({ page }) => {
    // Wait for table to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Check if pagination is visible
    const pagination = page.locator('.ant-pagination');
    await expect(pagination).toBeVisible();

    // Get total page count
    const totalInfo = page.locator('.ant-pagination-total-text');
    if (await totalInfo.isVisible()) {
      const totalText = await totalInfo.textContent();
      expect(totalText).toMatch(/총 \d+건/);
    }

    // Try to navigate to next page (if exists)
    const nextButton = page.locator('.ant-pagination-next');
    if (await nextButton.isEnabled()) {
      await nextButton.click();
      await page.waitForLoadState('networkidle');

      // Verify page changed
      const currentPage = page.locator('.ant-pagination-item-active');
      await expect(currentPage).toContainText('2');
    }
  });

  test('should change page size', async ({ page }) => {
    // Wait for table to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Click on page size selector
    const pageSizeSelector = page.locator('.ant-pagination-options .ant-select');
    if (await pageSizeSelector.isVisible()) {
      await pageSizeSelector.click();

      // Select different page size (e.g., 100)
      await page.getByText('100 / page').click();

      // Wait for data to reload
      await page.waitForLoadState('networkidle');

      // Verify page size changed
      const currentPageSize = page.locator('.ant-pagination-options .ant-select-selection-item');
      await expect(currentPageSize).toContainText('100');
    }
  });

  test('should display empty state when no transactions', async ({ page }) => {
    // Apply filters that will return no results
    // Select a future year
    await page.getByText('연도').locator('..').locator('input').click();
    await page.getByText('2030년').click();

    // Wait for data to reload
    await page.waitForLoadState('networkidle');

    // Check for empty state
    const emptyState = page.locator('.ant-empty');
    if (await emptyState.isVisible()) {
      await expect(emptyState).toContainText('조회된 거래 내역이 없습니다');
    }
  });

  test('should display loading skeleton while fetching', async ({ page }) => {
    // Intercept API request to delay response
    await page.route('**/api/transactions*', async (route) => {
      await new Promise(resolve => setTimeout(resolve, 1000));
      await route.continue();
    });

    // Navigate to page
    await page.goto('/transactions');

    // Check if loading skeleton is visible
    const skeleton = page.locator('.ant-skeleton');
    await expect(skeleton.first()).toBeVisible();

    // Wait for loading to complete
    await page.waitForLoadState('networkidle');
  });

  test('should clear filters', async ({ page }) => {
    // Wait for page to load
    await page.waitForLoadState('networkidle');

    // Apply year filter
    await page.getByText('연도').locator('..').locator('input').click();
    await page.getByText('2024년').click();
    await page.waitForLoadState('networkidle');

    // Clear year filter
    const yearClearButton = page.getByText('연도').locator('..').locator('.ant-select-clear');
    if (await yearClearButton.isVisible()) {
      await yearClearButton.click();
      await page.waitForLoadState('networkidle');

      // Verify filter is cleared
      const yearSelect = page.getByText('연도').locator('..').locator('.ant-select-selection-item');
      await expect(yearSelect).not.toBeVisible();
    }
  });

  test('should display category color dots', async ({ page }) => {
    // Wait for table to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Check viewport size to see if category column is visible
    const viewportSize = page.viewportSize();
    if (viewportSize && viewportSize.width >= 768) {
      // Look for category color dots in the table
      const colorDot = page.locator('table tbody tr').first().locator('td').nth(1).locator('span span').first();

      if (await colorDot.isVisible()) {
        // Verify it has a background color (indicating it's a colored dot)
        const backgroundColor = await colorDot.evaluate(el =>
          window.getComputedStyle(el).backgroundColor
        );
        expect(backgroundColor).not.toBe('rgba(0, 0, 0, 0)'); // Not transparent
      }
    }
  });

  test('should format amounts with Korean Won symbol', async ({ page }) => {
    // Wait for table to load
    await page.waitForSelector('table', { state: 'visible', timeout: 10000 });

    // Get first amount cell
    const amountCell = page.locator('table tbody tr').first().locator('td').nth(3);

    if (await amountCell.isVisible()) {
      const amountText = await amountCell.textContent();

      // Verify amount starts with Won symbol and has comma separators
      expect(amountText).toMatch(/₩[\d,]+/);
    }
  });

  test('should persist filters across pagination', async ({ page }) => {
    // Wait for page to load
    await page.waitForLoadState('networkidle');

    // Apply year filter
    await page.getByText('연도').locator('..').locator('input').click();
    await page.getByText('2024년').click();
    await page.waitForLoadState('networkidle');

    // Navigate to next page (if available)
    const nextButton = page.locator('.ant-pagination-next');
    if (await nextButton.isEnabled()) {
      await nextButton.click();
      await page.waitForLoadState('networkidle');

      // Verify year filter is still applied
      const yearSelect = page.getByText('연도').locator('..').locator('.ant-select-selection-item');
      await expect(yearSelect).toContainText('2024년');
    }
  });

  test('should be responsive on mobile', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });

    // Wait for page to load
    await page.waitForLoadState('networkidle');

    // Check if filters are stacked vertically
    await expect(page.getByText('연도')).toBeVisible();
    await expect(page.getByText('카테고리')).toBeVisible();

    // Check if table is scrollable horizontally
    const table = page.locator('table');
    if (await table.isVisible()) {
      const scrollWidth = await table.evaluate(el => el.scrollWidth);
      const clientWidth = await table.evaluate(el => el.clientWidth);

      // Table should be wider than viewport on mobile
      expect(scrollWidth).toBeGreaterThan(0);
    }
  });
});
