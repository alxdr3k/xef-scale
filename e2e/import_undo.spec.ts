import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { loginAsAdmin } from './helpers';

type UndoFixture = {
  sessionId: number;
  workspaceId: number;
  merchant: string;
};

function railsRunner(script: string): string {
  return execFileSync('bin/rails', ['runner', script], {
    cwd: process.cwd(),
    env: { ...process.env, RAILS_ENV: 'test' },
    encoding: 'utf8',
  }).trim();
}

function createAutoPostedImportFixture(): UndoFixture {
  const token = `E2E 되돌리기 가맹점 ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const amount = 42000 + Math.floor(Math.random() * 100000);
  const script = `
    user = User.find_by!(email: "test@example.com")
    workspace = user.workspaces.find_by!(name: "개인 가계부")
    session = workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "committed",
      total_count: 1,
      success_count: 1,
      completed_at: Time.current,
      committed_at: Time.current,
      committed_by: user
    )
    workspace.transactions.create!(
      parsing_session: session,
      date: Date.current,
      merchant: ${JSON.stringify(token)},
      amount: ${amount},
      status: "committed",
      committed_at: Time.current,
      committed_by: user,
      source_type: "text_paste"
    )
    puts({ sessionId: session.id, workspaceId: workspace.id, merchant: ${JSON.stringify(token)} }.to_json)
  `;

  return JSON.parse(railsRunner(script)) as UndoFixture;
}

test.describe('Import undo flow (가져오기 되돌리기)', () => {
  test('입력 기록에서 auto-posted import를 되돌리면 결제 내역에서 제외된다', async ({ page }) => {
    const fixture = createAutoPostedImportFixture();
    const parsingSessionsPath = `/workspaces/${fixture.workspaceId}/parsing_sessions`;
    const transactionsPath = `/workspaces/${fixture.workspaceId}/transactions`;

    await loginAsAdmin(page);
    await page.goto(parsingSessionsPath);

    const row = page.locator(`tr#parsing_session_${fixture.sessionId}`);
    await expect(row).toBeVisible();
    await expect(row.getByRole('button', { name: '되돌리기' })).toBeVisible();

    page.once('dialog', async (dialog) => {
      await dialog.accept();
    });
    await row.getByRole('button', { name: '되돌리기' }).click();

    await expect(page.getByText('1건의 거래를 되돌렸습니다.')).toBeVisible();

    await page.goto(`${transactionsPath}?q=${encodeURIComponent(fixture.merchant)}`);
    await expect(page.locator('#transactions-list').getByText(fixture.merchant)).toHaveCount(0);
  });
});
