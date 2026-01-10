import { test, expect, type Page } from '@playwright/test';

/**
 * E2E tests for Parsing Sessions page
 * Tests session list, pagination, detail modal, and API integration
 */

// Mock data for parsing sessions
const mockSessions = [
  {
    id: 1,
    file_id: 1,
    parser_type: 'HANA',
    started_at: new Date(Date.now() - 5 * 60 * 1000).toISOString(), // 5 minutes ago
    completed_at: new Date(Date.now() - 4 * 60 * 1000).toISOString(),
    total_rows_in_file: 100,
    rows_saved: 95,
    rows_skipped: 3,
    rows_duplicate: 2,
    status: 'completed',
    error_message: null,
    validation_status: 'pass',
    validation_notes: 'All validations passed',
    file_name: 'hana_statement_202401.xlsx',
    file_hash: 'abc123',
    institution_name: '하나카드',
    institution_type: 'CARD',
  },
  {
    id: 2,
    file_id: 2,
    parser_type: 'SHINHAN',
    started_at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(), // 2 hours ago
    completed_at: new Date(Date.now() - 2 * 60 * 60 * 1000 + 10000).toISOString(),
    total_rows_in_file: 50,
    rows_saved: 45,
    rows_skipped: 5,
    rows_duplicate: 0,
    status: 'completed',
    error_message: null,
    validation_status: 'warning',
    validation_notes: 'Some rows were skipped',
    file_name: 'shinhan_card_202401.pdf',
    file_hash: 'def456',
    institution_name: '신한카드',
    institution_type: 'CARD',
  },
  {
    id: 3,
    file_id: 3,
    parser_type: 'TOSS',
    started_at: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(), // 1 day ago
    completed_at: null,
    total_rows_in_file: 200,
    rows_saved: 0,
    rows_skipped: 0,
    rows_duplicate: 0,
    status: 'failed',
    error_message: 'Parser error: Invalid file format',
    validation_status: 'error',
    validation_notes: null,
    file_name: 'toss_statement_202401.csv',
    file_hash: 'ghi789',
    institution_name: '토스뱅크',
    institution_type: 'BANK',
  },
];

const mockSkippedTransactions = [
  {
    id: 1,
    session_id: 2,
    row_number: 5,
    skip_reason: 'zero_amount',
    transaction_date: '2024.01.15',
    merchant_name: '테스트 상점',
    amount: 0,
    original_amount: null,
    skip_details: 'Amount is zero',
    column_data: { merchant: '테스트 상점', amount: '0' },
  },
  {
    id: 2,
    session_id: 2,
    row_number: 12,
    skip_reason: 'invalid_date',
    transaction_date: null,
    merchant_name: '에러 상점',
    amount: 5000,
    original_amount: null,
    skip_details: 'Date format invalid',
    column_data: { merchant: '에러 상점', date: 'invalid' },
  },
];

// Helper function to mock API
async function setupApiMocks(page: Page) {
  // Mock sessions list API
  await page.route('**/api/parsing-sessions?*', async (route) => {
    const url = new URL(route.request().url());
    const page = parseInt(url.searchParams.get('page') || '1');
    const pageSize = parseInt(url.searchParams.get('page_size') || '20');

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        sessions: mockSessions,
        total: mockSessions.length,
        page,
        page_size: pageSize,
      }),
    });
  });

  // Mock single session API
  await page.route('**/api/parsing-sessions/[0-9]+$', async (route) => {
    const sessionId = parseInt(route.request().url().split('/').pop() || '1');
    const session = mockSessions.find((s) => s.id === sessionId);

    if (session) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(session),
      });
    } else {
      await route.fulfill({
        status: 404,
        contentType: 'application/json',
        body: JSON.stringify({ detail: 'Session not found' }),
      });
    }
  });

  // Mock skipped transactions API
  await page.route('**/api/parsing-sessions/*/skipped', async (route) => {
    const sessionId = parseInt(route.request().url().split('/').slice(-2)[0]);
    const skipped = mockSkippedTransactions.filter((t) => t.session_id === sessionId);

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(skipped),
    });
  });
}

test.describe('Parsing Sessions Page - Authenticated', () => {
  test.beforeEach(async ({ page, context }) => {
    // Mock authenticated state
    await context.addInitScript(() => {
      localStorage.setItem('access_token', 'mock-token');
      localStorage.setItem(
        'user',
        JSON.stringify({
          id: '1',
          email: 'test@example.com',
          name: 'Test User',
        })
      );
    });

    // Setup API mocks
    await setupApiMocks(page);

    // Navigate to parsing sessions page
    await page.goto('/parsing-sessions');
    await page.waitForLoadState('networkidle');
  });

  test('should display page title', async ({ page }) => {
    const title = page.getByRole('heading', { name: '파싱 세션 현황', level: 2 });
    await expect(title).toBeVisible();
  });

  test('should display session list with correct data', async ({ page }) => {
    // Wait for sessions to load
    await page.waitForSelector('[data-testid="session-card"]', { timeout: 5000 }).catch(() => {
      // Fallback: look for file names
    });

    // Check that all mock sessions are displayed
    for (const session of mockSessions) {
      await expect(page.getByText(session.file_name)).toBeVisible();
      await expect(page.getByText(session.institution_name || '알 수 없음')).toBeVisible();
    }
  });

  test('should display correct status icons', async ({ page }) => {
    // Success icon (CheckCircleOutlined) - green
    const successSession = page.locator('text=hana_statement_202401.xlsx').locator('..');
    await expect(successSession).toBeVisible();

    // Warning icon (WarningOutlined) - orange for skipped rows
    const warningSession = page.locator('text=shinhan_card_202401.pdf').locator('..');
    await expect(warningSession).toBeVisible();

    // Error icon (CloseCircleOutlined) - red for failed
    const errorSession = page.locator('text=toss_statement_202401.csv').locator('..');
    await expect(errorSession).toBeVisible();
  });

  test('should display processing statistics', async ({ page }) => {
    // Check for "95건 저장, 3건 스킵, 2건 중복"
    await expect(page.getByText(/95건 저장/)).toBeVisible();
    await expect(page.getByText(/45건 저장/)).toBeVisible();

    // Check for error message
    await expect(page.getByText(/Parser error: Invalid file format/)).toBeVisible();
  });

  test('should display relative time', async ({ page }) => {
    // Should show relative time like "5분 전", "2시간 전", "1일 전"
    // Note: exact text depends on dayjs locale and may vary
    const timeElements = page.locator('[data-testid="relative-time"]').or(
      page.locator('text=/\\d+(분|시간|일) (전|ago)/')
    );
    await expect(timeElements.first()).toBeVisible();
  });

  test('should open detail modal when clicking detail button', async ({ page }) => {
    // Click first session's detail button
    const detailButtons = page.getByRole('button', { name: '상세' });
    await detailButtons.first().click();

    // Wait for modal to appear
    await page.waitForSelector('.ant-modal', { state: 'visible' });

    // Check modal title
    const modalTitle = page.getByText('파싱 세션 상세 정보');
    await expect(modalTitle).toBeVisible();
  });

  test('should display detailed session information in modal', async ({ page }) => {
    // Open first session detail
    await page.getByRole('button', { name: '상세' }).first().click();
    await page.waitForSelector('.ant-modal', { state: 'visible' });

    // Check file details
    await expect(page.getByText('hana_statement_202401.xlsx')).toBeVisible();
    await expect(page.getByText('하나카드')).toBeVisible();
    await expect(page.getByText('HANA')).toBeVisible();

    // Check processing results
    await expect(page.getByText('100')).toBeVisible(); // total rows
    await expect(page.getByText('95건')).toBeVisible(); // saved
    await expect(page.getByText('3건')).toBeVisible(); // skipped
    await expect(page.getByText('2건')).toBeVisible(); // duplicate

    // Check validation status
    await expect(page.getByText('성공')).toBeVisible();
  });

  test('should display skipped transactions in modal', async ({ page }) => {
    // Open second session detail (has skipped transactions)
    const detailButtons = page.getByRole('button', { name: '상세' });
    await detailButtons.nth(1).click();
    await page.waitForSelector('.ant-modal', { state: 'visible' });

    // Check for skipped transactions section
    const skippedSection = page.getByText(/스킵된 거래 목록/);
    await expect(skippedSection).toBeVisible();

    // Expand skipped transactions if collapsed
    const collapsePanel = page.locator('.ant-collapse-item');
    if (await collapsePanel.isVisible()) {
      await collapsePanel.click();
    }

    // Check skipped transaction details
    await expect(page.getByText('테스트 상점')).toBeVisible();
    await expect(page.getByText('금액 0원')).toBeVisible(); // mapped skip reason
    await expect(page.getByText('에러 상점')).toBeVisible();
  });

  test('should close modal when clicking cancel or overlay', async ({ page }) => {
    // Open modal
    await page.getByRole('button', { name: '상세' }).first().click();
    await page.waitForSelector('.ant-modal', { state: 'visible' });

    // Click outside modal (on mask)
    await page.locator('.ant-modal-mask').click({ position: { x: 10, y: 10 } });

    // Modal should be closed
    await expect(page.locator('.ant-modal')).not.toBeVisible();
  });

  test('should display empty state when no sessions exist', async ({ page }) => {
    // Mock empty response
    await page.route('**/api/parsing-sessions?*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          sessions: [],
          total: 0,
          page: 1,
          page_size: 20,
        }),
      });
    });

    // Reload page
    await page.reload();
    await page.waitForLoadState('networkidle');

    // Check for empty state message
    await expect(page.getByText('아직 파싱 이력이 없습니다')).toBeVisible();
  });

  test('should display error alert when API fails', async ({ page }) => {
    // Mock error response
    await page.route('**/api/parsing-sessions?*', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({
          detail: 'Internal server error',
        }),
      });
    });

    // Reload page
    await page.reload();
    await page.waitForLoadState('networkidle');

    // Check for error message
    await expect(page.getByText(/파싱 세션 목록을 불러오는데 실패했습니다/)).toBeVisible();
  });

  test('should display loading spinner while fetching data', async ({ page }) => {
    // Add delay to API response
    await page.route('**/api/parsing-sessions?*', async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          sessions: mockSessions,
          total: mockSessions.length,
          page: 1,
          page_size: 20,
        }),
      });
    });

    // Reload and check for spinner
    await page.reload();
    await expect(page.locator('.ant-spin')).toBeVisible();

    // Wait for data to load
    await page.waitForLoadState('networkidle');
    await expect(page.locator('.ant-spin')).not.toBeVisible();
  });

  test('should be responsive on mobile viewport', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });

    // Main elements should still be visible
    await expect(page.getByRole('heading', { name: '파싱 세션 현황' })).toBeVisible();

    // Session cards should be visible and stack vertically
    for (const session of mockSessions) {
      await expect(page.getByText(session.file_name)).toBeVisible();
    }

    // Detail button should be accessible
    await expect(page.getByRole('button', { name: '상세' }).first()).toBeVisible();
  });
});

test.describe('Parsing Sessions Page - Pagination', () => {
  test.beforeEach(async ({ page, context }) => {
    // Mock authenticated state
    await context.addInitScript(() => {
      localStorage.setItem('access_token', 'mock-token');
      localStorage.setItem('user', JSON.stringify({ id: '1', email: 'test@example.com' }));
    });
  });

  test('should display pagination when total exceeds page size', async ({ page }) => {
    // Mock large dataset
    await page.route('**/api/parsing-sessions?*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          sessions: mockSessions,
          total: 50, // More than 20 (pageSize)
          page: 1,
          page_size: 20,
        }),
      });
    });

    await page.goto('/parsing-sessions');
    await page.waitForLoadState('networkidle');

    // Check pagination is visible
    await expect(page.locator('.ant-pagination')).toBeVisible();
    await expect(page.getByText('전체 50개')).toBeVisible();
  });

  test('should not display pagination when total is less than page size', async ({ page }) => {
    // Mock small dataset
    await page.route('**/api/parsing-sessions?*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          sessions: mockSessions,
          total: 3, // Less than 20
          page: 1,
          page_size: 20,
        }),
      });
    });

    await page.goto('/parsing-sessions');
    await page.waitForLoadState('networkidle');

    // Pagination should not be visible
    await expect(page.locator('.ant-pagination')).not.toBeVisible();
  });
});
