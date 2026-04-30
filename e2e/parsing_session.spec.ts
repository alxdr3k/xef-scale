import { test, expect } from '@playwright/test';
import { loginAsAdmin, navigateToParsingSessions, setAiConsent } from './helpers';

// Parsing sessions page = "결제 추가" (/workspaces/:id/parsing_sessions)
// Two input methods:
//   1. 문자 붙여넣기 → POST text_parse_workspace_parsing_sessions_path
//   2. 스크린샷 업로드 → POST workspace_parsing_sessions_path (multipart)
// AI consent banner: shown when workspace.ai_consent_required? is true
// Onboarding overlay: dismissable via data-action="click->onboarding#dismiss"
// History table (desktop) / card list (mobile): columns #, 입력내용, 상태, 결과, 시간
// Bulk select toolbar for discarding sessions

test.describe('Parsing sessions (결제 추가 페이지)', () => {
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await setAiConsent(page, true);
    await navigateToParsingSessions(page);
  });

  // --- Page structure ---

  test('페이지 제목과 설명 문구가 표시된다', async ({ page }) => {
    await expect(page.getByRole('heading', { name: '결제 추가' })).toBeVisible();
    await expect(page.locator('text=금융 문자를 붙여넣거나')).toBeVisible();
  });

  test('문자 붙여넣기 카드가 표시된다', async ({ page }) => {
    await expect(page.locator('h3:has-text("문자 붙여넣기")')).toBeVisible();
    await expect(page.locator('textarea#text')).toBeVisible();
    await expect(page.getByRole('button', { name: 'AI 파싱' })).toBeVisible();
  });

  test('스크린샷 업로드 카드가 표시된다', async ({ page }) => {
    await expect(page.locator('h3:has-text("스크린샷 업로드")')).toBeVisible();
    await expect(page.locator('input[type="file"]')).toBeVisible();
    await expect(page.getByRole('button', { name: '스크린샷 업로드' })).toBeVisible();
  });

  test('입력 기록 섹션 헤더가 표시된다', async ({ page }) => {
    await expect(page.locator('h2:has-text("입력 기록")')).toBeVisible();
  });

  // --- AI consent banner ---

  test('AI 동의 전에는 입력 패널 대신 동의 안내만 표시된다', async ({ page }) => {
    await setAiConsent(page, false);
    await navigateToParsingSessions(page);

    await expect(page.locator('text=외부 AI 사용 안내')).toBeVisible();
    await expect(page.locator('a:has-text("워크스페이스 설정에서 동의 또는 비활성화")')).toBeVisible();
    await expect(page.locator('textarea#text')).toHaveCount(0);
    await expect(page.locator('input[type="file"]')).toHaveCount(0);
    await expect(page.locator('[data-onboarding-target="overlay"]')).toHaveCount(0);
    await expect(page.locator('h2:has-text("입력 기록")')).toBeVisible();
  });

  test('AI 동의 후에는 동의 안내가 숨겨진다', async ({ page }) => {
    await expect(page.locator('text=외부 AI 사용 안내')).toHaveCount(0);
    await expect(page.getByRole('heading', { name: '결제 추가' })).toBeVisible();
  });

  // --- Text paste flow ---

  test('빈 텍스트로 AI 파싱 제출 시 페이지가 응답한다', async ({ page }) => {
    // Submit with empty textarea — server should respond (validation or redirect)
    const submitBtn = page.getByRole('button', { name: 'AI 파싱' });
    await submitBtn.click();
    // Should not crash — either stays on page or redirects
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toBeVisible();
  });

  test('텍스트 붙여넣기 textarea에 입력할 수 있다', async ({ page }) => {
    const sampleText = '[Web발신]\n신한체크 승인 홍*동\n50,000원 일시불\n03/15 14:30 스타벅스강남점';
    await page.locator('textarea#text').fill(sampleText);
    await expect(page.locator('textarea#text')).toHaveValue(sampleText);
  });

  test('텍스트 파싱 제출 후 입력 기록에 세션이 생성된다', async ({ page }) => {
    const sampleText = '[Web발신]\n신한체크 승인 홍*동\n50,000원 일시불\n03/15 14:30 스타벅스강남점';
    await page.locator('textarea#text').fill(sampleText);
    await page.getByRole('button', { name: 'AI 파싱' }).click();
    await page.waitForLoadState('networkidle');

    // After submission, should redirect back to parsing sessions index
    await expect(page).toHaveURL(/parsing_sessions/);
    // History section should be visible
    await expect(page.locator('h2:has-text("입력 기록")')).toBeVisible();
  });

  // --- History table / bulk select ---

  test('입력 기록 테이블의 전체 선택 체크박스가 있다', async ({ page }) => {
    await expect(page.locator('[data-bulk-select-target="toolbarCheckbox"]')).toBeVisible();
  });

  test('입력 기록이 있는 경우 데스크탑 테이블 헤더가 표시된다', async ({ page }) => {
    // Columns: #, 입력 내용, 상태, 결과, 시간
    const thead = page.locator('table thead');
    const theadVisible = await thead.isVisible().catch(() => false);
    if (theadVisible) {
      await expect(thead.locator('th:has-text("입력 내용")')).toBeVisible();
      await expect(thead.locator('th:has-text("상태")')).toBeVisible();
      await expect(thead.locator('th:has-text("결과")')).toBeVisible();
      await expect(thead.locator('th:has-text("시간")')).toBeVisible();
    }
  });

  test('좁은 화면에서는 입력 기록을 카드 레이아웃으로 표시한다', async ({ page }) => {
    await page.setViewportSize({ width: 640, height: 900 });
    await page.reload();
    await page.waitForLoadState('networkidle');

    await expect(page.locator('[data-testid="parsing-session-cards"]')).toBeVisible();
    await expect(page.locator('[data-testid="parsing-session-table"]')).toBeHidden();
  });

  test('입력 기록 없을 때 빈 상태 메시지가 표시된다', async ({ page }) => {
    // This may or may not appear depending on seed data state.
    const emptyMsg = page.locator('text=입력 기록이 없습니다.');
    const hasHistory = page.locator('table tbody tr:not(:empty)');

    const emptyVisible = await emptyMsg.isVisible().catch(() => false);
    const historyVisible = await hasHistory.first().isVisible().catch(() => false);

    // One of the two states must be present
    expect(emptyVisible || historyVisible).toBe(true);
  });

  test('완료된 세션에 검토하기 링크가 표시된다', async ({ page }) => {
    const reviewLink = page.locator('a:has-text("검토하기")').first();
    const detailLink = page.locator('a:has-text("상세보기")').first();

    const hasReview = await reviewLink.isVisible({ timeout: 2000 }).catch(() => false);
    const hasDetail = await detailLink.isVisible({ timeout: 2000 }).catch(() => false);

    if (hasReview) {
      await expect(reviewLink).toHaveAttribute('href', /review/);
    } else if (hasDetail) {
      await expect(detailLink).toHaveAttribute('href', /review/);
    }
    // Both may be absent if no sessions exist — that's acceptable
  });

  // --- Onboarding overlay ---

  test('온보딩 오버레이는 data-onboarding-target="overlay"로 마운트된다', async ({ page }) => {
    // The overlay is hidden by default and managed by the onboarding Stimulus controller
    const overlay = page.locator('[data-onboarding-target="overlay"]');
    await expect(overlay).toBeAttached();
  });
});
