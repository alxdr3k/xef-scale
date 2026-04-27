import { Page, expect } from '@playwright/test';

// Test login using email (bypasses OAuth)
export async function loginAsUser(page: Page, email: string = 'test@example.com') {
  await page.goto(`/test_login?email=${encodeURIComponent(email)}`);
  // Wait for redirect to complete (authenticated root is dashboard at /)
  await page.waitForLoadState('networkidle');
}

// Alias for test user (development seeds user)
export async function loginAsAdmin(page: Page) {
  await loginAsUser(page, 'test@example.com');
}

// Legacy login function (kept for compatibility) — delegates to test_login bypass
export async function login(page: Page, email: string = 'test@example.com', _password: string = 'password123') {
  await loginAsUser(page, email);
}

export async function selectWorkspace(page: Page, workspaceName: string) {
  const select = page.locator('select[name="workspace_id"]');
  if (await select.isVisible()) {
    await select.selectOption({ label: workspaceName });
    await page.waitForLoadState('networkidle');
  }
}

export async function navigateToParsingSessions(page: Page) {
  await page.click('a:has-text("가져오기")');
  await page.waitForURL(/parsing_sessions/);
}

export async function uploadFile(page: Page, filePath: string) {
  await navigateToParsingSessions(page);
  const fileInput = page.locator('input[type="file"]');
  await fileInput.setInputFiles(filePath);
  await page.click('input[type="submit"][value="업로드"]');
  await page.waitForLoadState('networkidle');
}

export async function waitForParsingComplete(page: Page, maxWaitTime: number = 30000) {
  const startTime = Date.now();

  while (Date.now() - startTime < maxWaitTime) {
    await page.reload();
    await page.waitForLoadState('networkidle');

    const completedBadge = page.locator('span:has-text("완료")').first();
    if (await completedBadge.isVisible()) {
      return true;
    }

    await page.waitForTimeout(1000);
  }

  return false;
}

export async function goToReviewPage(page: Page) {
  const reviewLink = page.locator('a:has-text("검토하기")').first();
  await reviewLink.click();
  await page.waitForURL(/review/);
}
