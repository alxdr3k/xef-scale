import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { loginAsAdmin } from './helpers';

type RepairFixture = {
  issueId: number;
  sessionId: number;
  workspaceId: number;
  merchant: string;
  amount: number;
};

function railsRunner(script: string): string {
  return execFileSync('bin/rails', ['runner', script], {
    cwd: process.cwd(),
    env: { ...process.env, RAILS_ENV: 'test' },
    encoding: 'utf8',
  }).trim();
}

function createMissingDateFixture(): RepairFixture {
  const token = `E2E 수리 가맹점 ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const amount = 32000 + Math.floor(Math.random() * 100000);
  const script = `
    user = User.find_by!(email: "test@example.com")
    workspace = user.workspaces.find_by!(name: "개인 가계부")
    session = workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "committed",
      total_count: 1,
      success_count: 0,
      error_count: 1,
      completed_at: Time.current
    )
    issue = workspace.import_issues.create!(
      parsing_session: session,
      source_type: "image_upload",
      issue_type: "missing_required_fields",
      status: "open",
      missing_fields: ["date"],
      merchant: ${JSON.stringify(token)},
      amount: ${amount},
      raw_payload: { "description" => "E2E repair fixture" }
    )
    Notification.create_import_repair_needed!(session, user)
    puts({ issueId: issue.id, sessionId: session.id, workspaceId: workspace.id, merchant: issue.merchant, amount: issue.amount }.to_json)
  `;

  return JSON.parse(railsRunner(script)) as RepairFixture;
}

test.describe('Import repair flow (가져오기 수정 필요 항목)', () => {
  test('누락 필수값을 채우면 repair queue에서 바로 결제 내역에 반영된다', async ({ page }) => {
    const fixture = createMissingDateFixture();
    const transactionsPath = `/workspaces/${fixture.workspaceId}/transactions`;
    const repairPath = `${transactionsPath}?repair=required&import_session_id=${fixture.sessionId}`;

    await loginAsAdmin(page);
    await page.goto(transactionsPath);
    await expect(page.getByText('수정이 필요한 가져오기 항목')).toBeVisible();

    await page.getByRole('link', { name: '수정 필요 항목 보기' }).click();
    await expect(page).toHaveURL(/repair=required/);
    await expect(page.getByRole('heading', { name: '수정 필요한 항목만 표시 중' })).toBeVisible();

    await page.goto(repairPath);
    const repairRow = page.locator(`#import_issue_${fixture.issueId}`);
    await expect(repairRow.locator('input[name="import_issue[merchant]"]')).toHaveValue(fixture.merchant);
    await expect(repairRow.getByText('날짜 필요')).toBeVisible();

    await repairRow.locator('input[name="import_issue[date]"]').fill('2026-04-25');
    await repairRow.getByRole('button', { name: '반영' }).click();

    await expect(page.getByText('결제 내역에 반영했습니다.')).toBeVisible();
    await expect(page.getByText('수정이 필요한 가져오기 항목이 없습니다.')).toBeVisible();

    await page.goto(`${transactionsPath}?q=${encodeURIComponent(fixture.merchant)}`);
    await expect(page.locator('#transactions-list').getByText(fixture.merchant)).toBeVisible();
    await expect(page.locator('#transactions-list').getByText(fixture.amount.toLocaleString('en-US'))).toBeVisible();
  });
});
