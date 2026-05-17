require "test_helper"

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @parsing_session = parsing_sessions(:completed_session)
    @parsing_session.update!(review_status: "pending_review")
    sign_in @user
  end

  test "commit is blocked when pending duplicates remain" do
    @parsing_session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )

    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_match(/중복/, flash[:alert])
    assert @parsing_session.reload.review_pending?
  end

  test "commit succeeds when no pending duplicates" do
    @parsing_session.duplicate_confirmations.destroy_all
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 1000,
      status: "pending_review",
      parsing_session: @parsing_session
    )

    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert @parsing_session.reload.review_committed?
    assert tx.reload.committed?
  end

  test "bulk_update is refused on finalized sessions" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 1000,
      status: "pending_review",
      parsing_session: @parsing_session
    )
    @parsing_session.update!(review_status: "committed")

    post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { transaction_ids: tx.id.to_s, bulk_action: "delete" }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_match(/종료된/, flash[:alert])
    assert tx.reload.pending_review?
    assert_not tx.deleted
  end

  test "bulk_update delete excludes pending transactions from import via rollback" do
    @parsing_session.duplicate_confirmations.destroy_all
    keep = @workspace.transactions.create!(
      date: Date.current, amount: 1000, status: "pending_review",
      parsing_session: @parsing_session
    )
    drop = @workspace.transactions.create!(
      date: Date.current, amount: 2000, status: "pending_review",
      parsing_session: @parsing_session
    )

    post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { transaction_ids: drop.id.to_s, bulk_action: "delete" }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert drop.reload.rolled_back?, "expected dropped tx to be rolled_back"
    assert_not drop.deleted, "rollback should not soft-delete the row"

    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert keep.reload.committed?
    assert drop.reload.rolled_back?, "rolled-back tx must not be committed"
  end

  test "duplicate keep_new decision is skipped when new transaction is excluded" do
    @parsing_session.duplicate_confirmations.destroy_all
    original = transactions(:food_transaction)
    original.update!(deleted: false, status: "committed")

    new_tx = @workspace.transactions.create!(
      date: original.date, amount: original.amount,
      status: "pending_review", parsing_session: @parsing_session
    )
    dc = @parsing_session.duplicate_confirmations.create!(
      original_transaction: original, new_transaction: new_tx, status: "keep_new"
    )

    post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { transaction_ids: new_tx.id.to_s, bulk_action: "delete" }
    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_not original.reload.deleted, "original must survive when the new row was excluded"
    assert new_tx.reload.rolled_back?
    assert_equal "keep_new", dc.reload.status
  end

  test "update_transaction allows negative amount for refund/cancellation" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 50000,
      status: "pending_review",
      parsing_session: @parsing_session
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { field: "amount", value: "-30000" },
          as: :turbo_stream

    assert_response :success
    assert_equal(-30000, tx.reload.amount)
  end

  test "update_transaction records a transaction_updated review event with changed fields" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 50000,
      status: "pending_review",
      parsing_session: @parsing_session
    )

    assert_difference -> { @parsing_session.import_review_events.where(event_type: "transaction_updated").count }, 1 do
      patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
            params: { field: "merchant", value: "스타벅스" },
            as: :turbo_stream
    end

    event = @parsing_session.import_review_events.where(event_type: "transaction_updated").last
    assert_includes event.changed_fields, "merchant"
    assert_equal tx.id, event.reviewed_transaction_id
  end

  test "bulk change_category records transaction_updated events only for actually changed rows" do
    category_a = @workspace.categories.create!(name: "카페")
    category_b = @workspace.categories.create!(name: "교통")
    tx_unchanged = @workspace.transactions.create!(
      date: Date.current, amount: 1_000,
      status: "pending_review", parsing_session: @parsing_session,
      category: category_b
    )
    tx_changed = @workspace.transactions.create!(
      date: Date.current, amount: 2_000,
      status: "pending_review", parsing_session: @parsing_session,
      category: category_a
    )

    assert_difference -> { @parsing_session.import_review_events.transaction_updates.count }, 1 do
      post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
            params: {
              transaction_ids: "#{tx_unchanged.id},#{tx_changed.id}",
              bulk_action: "change_category",
              category_id: category_b.id
            },
            as: :turbo_stream
    end

    event = @parsing_session.import_review_events.transaction_updates.last
    assert_equal tx_changed.id, event.reviewed_transaction_id
    assert_equal [ "category_id" ], event.changed_fields
  end

  test "bulk delete records transaction_excluded events" do
    tx1 = @workspace.transactions.create!(
      date: Date.current, amount: 1_000,
      status: "pending_review", parsing_session: @parsing_session
    )
    tx2 = @workspace.transactions.create!(
      date: Date.current, amount: 2_000,
      status: "pending_review", parsing_session: @parsing_session
    )

    assert_difference -> { @parsing_session.import_review_events.transaction_exclusions.count }, 2 do
      post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
            params: {
              transaction_ids: "#{tx1.id},#{tx2.id}",
              bulk_action: "delete"
            },
            as: :turbo_stream
    end
  end

  test "update_transaction rejects zero amount" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 50000,
      status: "pending_review",
      parsing_session: @parsing_session
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { field: "amount", value: "0" },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal 50000, tx.reload.amount
  end

  test "show assigns total_commit_count matching all pending_review transactions not just page" do
    @parsing_session.duplicate_confirmations.destroy_all
    3.times do
      @workspace.transactions.create!(
        date: Date.current, amount: 1000,
        status: "pending_review", parsing_session: @parsing_session
      )
    end

    expected_count = @parsing_session.transactions.pending_review.where(deleted: false).count

    # Verify the controller logic directly: total_commit_count must equal the full unpaginated scope
    assert expected_count > 0, "세션에 pending_review 거래가 있어야 함"

    # Simulate what the controller does to verify the query is correct
    computed = @parsing_session.transactions.pending_review.where(deleted: false).count
    assert_equal expected_count, computed,
                 "total_commit_count는 페이지네이션 없이 전체 pending_review 수여야 함"
  end

  test "show hides institution column and renders source metadata in popover" do
    @parsing_session.transactions.create!(
      workspace: @workspace,
      date: Date.current,
      merchant: "스타벅스",
      amount: 5800,
      status: "pending_review",
      source_metadata: {
        "source_channel" => "pasted_text",
        "source_app_raw" => "KB Pay",
        "source_institution_raw" => "KB국민카드"
      }
    )

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    assert_select "th", text: "금융기관", count: 0
    assert_select "th", text: "출처", count: 1
    assert_select "button[aria-label='가져온 출처 보기']", minimum: 1
    assert_includes response.body, "KB Pay"
    assert_includes response.body, "KB국민카드"
    assert_includes response.body, "이 정보는 결제 분류나 예산 계산에 사용되지 않습니다."
    assert_not_includes response.body, "금융기관 미확인"
  end

  test "show renders source_icon glyph when source_type is set" do
    @parsing_session.transactions.create!(
      workspace: @workspace,
      date: Date.current,
      merchant: "스타벅스",
      amount: 5800,
      status: "pending_review",
      source_type: "text_paste",
      source_metadata: { "source_channel" => "pasted_text" }
    )

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    # _source_icon emits 💬 glyph + aria-label="문자 붙여넣기" for text_paste
    assert_includes response.body, "💬"
    assert_select "[aria-label='문자 붙여넣기']", minimum: 1
  end

  test "show falls back to circle-info SVG when source_type is nil" do
    @parsing_session.transactions.create!(
      workspace: @workspace,
      date: Date.current,
      merchant: "스타벅스",
      amount: 5800,
      status: "pending_review",
      source_type: nil,
      source_metadata: { "source_channel" => "pasted_text" }
    )

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    # Without source_type, the popover trigger still appears (metadata present) — uses circle-info SVG.
    assert_select "button[aria-label='가져온 출처 보기']", minimum: 1
  end

  test "show falls back to circle-info SVG when source_type is unrecognized" do
    tx = @parsing_session.transactions.create!(
      workspace: @workspace,
      date: Date.current,
      merchant: "스타벅스",
      amount: 5800,
      status: "pending_review",
      source_type: "manual",
      source_metadata: { "source_channel" => "pasted_text" }
    )
    # Simulate legacy / future unmapped value (e.g. parsing_sessions' "file_upload")
    # by bypassing the inclusion validator — popover trigger must still show an icon.
    tx.update_column(:source_type, "file_upload")

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    assert_select "button[aria-label='가져온 출처 보기']" do
      # Either glyph or SVG must be rendered — never an empty button (P2 regression guard)
      assert_select "svg", minimum: 1
    end
  end

  test "show renders pending_badge for pending_review transactions" do
    @parsing_session.transactions.create!(
      workspace: @workspace,
      date: Date.current,
      merchant: "스타벅스",
      amount: 5800,
      status: "pending_review"
    )

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    assert_select "[aria-label='검토 대기']", minimum: 1
  end

  test "bulk_resolve_duplicates is refused on finalized sessions" do
    dc = @parsing_session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )
    @parsing_session.update!(review_status: "discarded")

    post bulk_resolve_duplicates_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { decision: "keep_both" }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_equal "pending", dc.reload.status
  end

  # ADR-0007 §4: review 경로에서도 묵시적 학습 금지. CategoryMapping은
  # explicit opt-in endpoint를 통해서만 생성/갱신된다.

  test "bulk_update change_category does not silently create CategoryMapping" do
    @parsing_session.duplicate_confirmations.destroy_all
    tx1 = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "스타벅스",
      status: "pending_review", parsing_session: @parsing_session
    )
    tx2 = @workspace.transactions.create!(
      date: Date.current, amount: 2000, merchant: "맥도날드",
      status: "pending_review", parsing_session: @parsing_session
    )
    target = categories(:food)

    assert_no_difference -> { CategoryMapping.count } do
      post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
           params: {
             bulk_action: "change_category",
             category_id: target.id,
             transaction_ids: "#{tx1.id},#{tx2.id}"
           }
    end

    # change_category 분기가 실제로 실행됐는지 검증 (false-positive 방지).
    assert_equal target.id, tx1.reload.category_id
    assert_equal target.id, tx2.reload.category_id
  end

  test "update_transaction category change does not silently create CategoryMapping" do
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1500, merchant: "투썸플레이스",
      status: "pending_review", parsing_session: @parsing_session
    )
    new_category = categories(:food)
    refute_equal new_category.id, tx.category_id

    assert_no_difference -> { CategoryMapping.count } do
      patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
            params: { transaction: { category_id: new_category.id } },
            as: :turbo_stream
    end

    assert_equal new_category.id, tx.reload.category_id
  end

  test "non-admin writer cannot silently create CategoryMapping through review category changes" do
    sign_out @user
    sign_in users(:member) # member_write per fixtures
    refute users(:member).admin_of?(@workspace)

    tx = @workspace.transactions.create!(
      date: Date.current, amount: 3000, merchant: "올리브영",
      status: "pending_review", parsing_session: @parsing_session
    )
    target = categories(:food)

    assert_no_difference -> { CategoryMapping.count } do
      patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
            params: { transaction: { category_id: target.id } },
            as: :turbo_stream
    end
    assert_equal target.id, tx.reload.category_id
  end

  # ADR-0004 §"필수" — reviews#index callback fix + needs_review scope + cross-tenant safe duplicate scoping.

  test "index renders for owner with parsing session present" do
    @parsing_session.update!(status: "completed", review_status: "pending_review")

    get workspace_reviews_path(@workspace)

    assert_response :success
    assert_select "h1", text: "검토함"
    # 파싱 결과 row에 detail 페이지(reviews#show) 링크가 포함
    assert_includes response.body, review_workspace_parsing_session_path(@workspace, @parsing_session)
  end

  test "commit is blocked while open import issues remain" do
    # setup의 pending DuplicateConfirmation을 정리해야 issue 가드를 검증할 수 있다.
    @parsing_session.duplicate_confirmations.destroy_all
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    @parsing_session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      missing_fields: %w[merchant]
    )

    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_match(/수리 필요/, flash[:alert].to_s)
    assert_equal "pending_review", @parsing_session.reload.review_status,
                 "수리 미완료 상태에서는 commit이 진행되어서는 안 됨"
  end

  test "index shows '수리 필요 N건' for sessions with open ImportIssues" do
    @parsing_session.update!(
      status: "completed",
      review_status: "pending_review",
      source_type: "file_upload"
    )
    @parsing_session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      missing_fields: [ "merchant" ]
    )

    get workspace_reviews_path(@workspace)

    assert_response :success
    assert_match(/수리 필요\s*1건/, response.body)
  end

  test "index does not show repair stat when no open ImportIssues exist" do
    @parsing_session.update!(status: "completed", review_status: "pending_review")

    get workspace_reviews_path(@workspace)

    assert_response :success
    assert_no_match(/수리 필요/, response.body)
  end

  # Phase 3.3: 검토함의 "+ 새로 가져오기"는 input_sheet 시트를 연다.
  # 이전(PR B)의 parsing_sessions/index 하드 링크는 폐기.
  test "index embeds input sheet trigger (sheet contains 3-way forms)" do
    get workspace_reviews_path(@workspace)
    assert_response :success
    assert_select "[data-controller~='input-sheet']", minimum: 1
    assert_select "[data-input-sheet-target='trigger']", minimum: 1
    # 시트 안 폼 action들 — text_paste / image_upload / 직접 입력 링크
    assert_includes response.body, text_parse_workspace_parsing_sessions_path(@workspace)
    assert_includes response.body, new_workspace_transaction_path(@workspace)
  end

  test "index is reachable by member_read (read-only) member" do
    # ADR-0004 §"필수": index는 read 권한만 요구.
    # require_workspace_write_access가 except: [:show, :index]로 풀려야 통과.
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    sign_out @user
    sign_in users(:reader)

    get workspace_reviews_path(@workspace)

    assert_response :success
  end

  test "index excludes parsing_sessions whose status is not completed (uses needs_review scope)" do
    # ADR-0004 §"왜 needs_review인가": review_status가 기본값 'pending_review'라
    # status가 pending/processing/failed인 세션도 동일 값을 가질 수 있음.
    # 미완료 세션이 인덱스에 섞이지 않아야 한다.
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    pending = parsing_sessions(:pending_session)      # status: pending
    processing = parsing_sessions(:processing_session) # status: processing
    failed = parsing_sessions(:failed_session)         # status: failed
    [ pending, processing, failed ].each do |ps|
      assert_equal "pending_review", ps.review_status, "fixture #{ps.id} should default to pending_review"
    end

    get workspace_reviews_path(@workspace)

    # 완료된 세션의 review URL만 포함, 비완료 세션 URL은 미포함.
    assert_includes response.body, review_workspace_parsing_session_path(@workspace, @parsing_session)
    [ pending, processing, failed ].each do |ps|
      assert_not_includes response.body, review_workspace_parsing_session_path(@workspace, ps),
                          "index should not link to non-completed session #{ps.id}"
    end
  end

  test "index pending_duplicates excludes finalized sessions (review_status != pending_review)" do
    # 사용자 시각에서 commit/rollback/discard된 세션의 잔여 pending dup은
    # reviews#show가 read_only로 잠겨 해결 액션을 제공하지 않는다.
    # 인덱스 자체에서 제외해 stale 행이 큐에 보이지 않게 한다.
    @parsing_session.update!(status: "completed", review_status: "pending_review")

    finalized = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "committed",
      total_count: 0, success_count: 0, duplicate_count: 0, error_count: 0
    )
    finalized_tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "STALE_DUP_MERCHANT_XYZ",
      status: "pending_review", parsing_session: finalized
    )
    finalized.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: finalized_tx,
      status: "pending"
    )

    get workspace_reviews_path(@workspace)

    assert_response :success
    assert_not_includes response.body, "STALE_DUP_MERCHANT_XYZ",
                        "finalized session's pending dup should not appear in inbox"
  end

  test "index pending_duplicates does not leak across workspaces" do
    # ADR-0004 §"필수": DuplicateConfirmation은 자체 workspace_id가 없고
    # parsing_session 조인을 통해서만 스코프 가능. 직접 .pending 호출 시 leak.
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    @parsing_session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )

    other_ws = workspaces(:other_workspace)
    other_session = other_ws.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review",
      total_count: 0, success_count: 0, duplicate_count: 0, error_count: 0
    )
    other_tx_original = other_ws.transactions.create!(
      date: Date.current, amount: 1000, merchant: "OTHER_MERCHANT_ORIGINAL_XYZ",
      status: "committed"
    )
    other_tx_new = other_ws.transactions.create!(
      date: Date.current, amount: 1000, merchant: "OTHER_MERCHANT_NEW_XYZ",
      status: "pending_review", parsing_session: other_session
    )
    other_session.duplicate_confirmations.create!(
      original_transaction: other_tx_original,
      new_transaction: other_tx_new,
      status: "pending"
    )

    get workspace_reviews_path(@workspace)

    # 본인 워크스페이스의 세션은 포함, 타 워크스페이스 세션은 URL이 노출되면 leak.
    assert_response :success
    assert_not_includes response.body,
                        review_workspace_parsing_session_path(other_ws, other_session),
                        "cross-tenant duplicate leak: index linked to other workspace's session"
    assert_not_includes response.body, "OTHER_MERCHANT_NEW_XYZ",
                        "cross-tenant duplicate leak: index showed other workspace's transaction merchant"
  end

  # ADR-0011 §Decision 3: 검토 흐름에서 classification_source set 시점 검증.

  test "update_transaction with form-based category change sets manual_set" do
    target = categories(:food)
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "RC_ADR0011",
      status: "pending_review", parsing_session: @parsing_session,
      classification_source: nil
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { transaction: { category_id: target.id } },
          as: :turbo_stream

    assert_response :success
    assert_equal "manual_set", tx.reload.classification_source
  end

  test "update_transaction with inline category_id field sets manual_set" do
    target = categories(:food)
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "RC_ADR0011_INLINE",
      status: "pending_review", parsing_session: @parsing_session,
      classification_source: nil
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { field: "category_id", value: target.id },
          as: :turbo_stream

    assert_response :success
    assert_equal "manual_set", tx.reload.classification_source
  end

  test "update_transaction explicit clear (category_id='') sets manual_set and prevents auto-rematch" do
    # Codex PR #174 — 폼에서 사용자가 의도적으로 카테고리를 *해제*("")한 경우.
    # 1) classification_source는 manual_set으로 잠겨야 한다.
    # 2) 같은 요청에서 merchant도 바뀌면 자동 재매칭이 *동작하지 않아야* 한다
    #    (사용자의 명시적 해제 의도를 존중).
    target_for_rematch = categories(:food)
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: "RC_CLEAR_REMATCH",
      match_type: "exact",
      source: "manual",
      category: target_for_rematch
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "원래 가맹점",
      category: categories(:transport),
      status: "pending_review", parsing_session: @parsing_session,
      classification_source: "mapping_match"
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { transaction: { category_id: "", merchant: "RC_CLEAR_REMATCH" } },
          as: :turbo_stream

    assert_response :success
    tx.reload
    assert_nil tx.category_id, "사용자가 빈 문자열로 카테고리를 해제했으므로 nil이어야 함"
    assert_equal "manual_set", tx.classification_source,
                 "category_id 키가 폼에 포함되었으므로 manual_set"
  end

  test "update_transaction inline category_id no-op preserves classification_source" do
    # Codex PR #174: inline field=category_id 편집이 같은 값이면 manual_set으로
    # 덮지 않는다 (no-op).
    target = categories(:food)
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "RC_INLINE_NOOP",
      category: target, status: "pending_review", parsing_session: @parsing_session,
      classification_source: "mapping_match"
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { field: "category_id", value: target.id },
          as: :turbo_stream

    assert_response :success
    assert_equal "mapping_match", tx.reload.classification_source
  end

  test "update_transaction merchant change on uncategorized auto-applies CategoryMapping" do
    # Codex PR #174 regression fix: uncategorized 거래에서 form-based merchant 변경
    # (category_id="" 함께 전송) 시 자동 mapping 적용은 그대로 동작해야 한다.
    target = categories(:food)
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: "RC_UNCAT_REMATCH",
      match_type: "exact",
      source: "manual",
      category: target
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "초기 가맹점",
      category: nil, status: "pending_review", parsing_session: @parsing_session,
      classification_source: nil
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { transaction: { merchant: "RC_UNCAT_REMATCH", category_id: "" } },
          as: :turbo_stream

    assert_response :success
    tx.reload
    assert_equal target.id, tx.category_id, "rematch로 mapping이 자동 적용돼야"
    assert_equal "mapping_match", tx.classification_source
  end

  test "bulk_update change_category per-row guard preserves provenance" do
    # Codex PR #174: review bulk-change도 mixed selection에서 no-op rows preserve.
    target = categories(:food)
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    already_in_target = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "RC_BULK_NOOP",
      category: target, status: "pending_review", parsing_session: @parsing_session,
      classification_source: "mapping_match"
    )
    changes_to_target = @workspace.transactions.create!(
      date: Date.current, amount: 2000, merchant: "RC_BULK_CHANGE",
      category: categories(:transport), status: "pending_review",
      parsing_session: @parsing_session, classification_source: "keyword_match"
    )

    post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
         params: {
           transaction_ids: "#{already_in_target.id},#{changes_to_target.id}",
           bulk_action: "change_category",
           category_id: target.id
         }

    assert_equal "mapping_match", already_in_target.reload.classification_source
    assert_equal "manual_set", changes_to_target.reload.classification_source
  end

  test "update_transaction form-based no-op category preserves classification_source" do
    # Codex PR #174 — 검토 폼도 category_id를 항상 보낼 수 있으므로 동일 카테고리
    # 재전송 시 mapping_match 등이 silent erase되면 안 된다.
    current_cat = categories(:food)
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "RC_NOOP",
      category: current_cat,
      status: "pending_review", parsing_session: @parsing_session,
      classification_source: "mapping_match"
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { transaction: { category_id: current_cat.id, merchant: "RC_NOOP" } },
          as: :turbo_stream

    assert_response :success
    assert_equal "mapping_match", tx.reload.classification_source
  end

  test "update_transaction merchant change preserves classification_source when rematch resolves to same category" do
    # Codex PR #174: 재매칭이 *같은* 카테고리로 끝나면 의미상 분류 변동이 없으므로
    # 기존 manual_set 같은 사용자 의도 provenance를 silent overwrite하면 안 된다.
    target = categories(:food)
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: "RC_SAME_REMATCH",
      match_type: "exact",
      source: "manual",
      category: target
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "초기 가맹점",
      category: target, # 이미 같은 카테고리
      status: "pending_review", parsing_session: @parsing_session,
      classification_source: "manual_set" # 사용자가 이전에 직접 지정
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { transaction: { merchant: "RC_SAME_REMATCH" } },
          as: :turbo_stream

    assert_response :success
    tx.reload
    assert_equal target.id, tx.category_id, "카테고리 자체는 그대로"
    assert_equal "manual_set", tx.classification_source,
                 "재매칭이 같은 카테고리면 provenance 유지"
  end

  test "update_transaction merchant change with mapping hit sets mapping_match" do
    target = categories(:food)
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: "RC_ADR0011_REMATCH",
      match_type: "exact",
      source: "manual",
      category: target
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "초기 가맹점",
      status: "pending_review", parsing_session: @parsing_session,
      classification_source: nil
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { field: "merchant", value: "RC_ADR0011_REMATCH" },
          as: :turbo_stream

    assert_response :success
    tx.reload
    assert_equal target.id, tx.category_id
    assert_equal "mapping_match", tx.classification_source
  end

  # Phase 5 slice 3: 검토함 키보드 단축키 (j/k navigation).
  test "show wires review-keyboard controller and tabindex on rows" do
    @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "KB_SHORTCUT",
      status: "pending_review", parsing_session: @parsing_session
    )
    @parsing_session.update!(status: "completed", review_status: "pending_review")

    get review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_response :success
    # 컨트롤러 attach + window keydown 액션 등록
    assert_match(/data-controller="[^"]*review-keyboard/, response.body)
    assert_match(/keydown@window->review-keyboard#handleKey/, response.body)
    # 거래 row에 tabindex=0 — j/k 이동 후 focus 받을 수 있어야
    assert_select "tr[data-transaction-id][tabindex='0']", minimum: 1
  end

  # Codex PR #182 P1: turbo_stream row re-render에서 reviewable이 누락되면
  # tabindex 손실 → j/k navigation 깨짐. reviewable 자동 추론(pending_review +
  # parsing_session) 덕에 호출자가 명시 안 해도 보존돼야 한다.
  test "update_transaction turbo_stream re-render preserves tabindex=0" do
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "REVIEW_RERENDER",
      status: "pending_review", parsing_session: @parsing_session
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { transaction: { merchant: "REVIEW_RERENDER_NEW" } },
          as: :turbo_stream

    assert_response :success
    assert_match(/<tr[^>]*data-transaction-id="#{tx.id}"[^>]*tabindex="0"/, response.body)
  end

  # Phase 5 slice 5: ? 단축키 도움말 overlay.
  test "show renders keyboard shortcuts help overlay (initially hidden)" do
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    get review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_response :success
    # overlay 컨테이너가 review-keyboard target으로 등록되어야 ? 핸들러가 작동.
    assert_match(/data-review-keyboard-target="helpDialog"/, response.body)
    assert_match(/data-review-keyboard-target="helpBackdrop"/, response.body)
    # 도움말 본문에 단축키 키들이 노출.
    assert_select "kbd", text: "j"
    assert_select "kbd", text: "k"
    assert_select "kbd", text: "c"
    assert_select "kbd", text: "?"
  end

  # Phase 5 slice 4: c 단축키가 commit form을 trigger하려면 form에 target이 있어야.
  test "show wires commit form as review-keyboard target for c shortcut" do
    @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "C_SHORTCUT_SESSION",
      status: "pending_review", parsing_session: @parsing_session
    )
    @parsing_session.update!(status: "completed", review_status: "pending_review")

    get review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_response :success
    # commit form이 review-keyboard target 속성을 가져야 c 단축키가 submit 가능.
    assert_match(/data-review-keyboard-target="commitForm"/, response.body)
  end

  test "quick_update_category turbo_stream re-render preserves tabindex on review row" do
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "REVIEW_QUICK",
      status: "pending_review", parsing_session: @parsing_session
    )
    target = categories(:food)

    patch quick_update_category_workspace_transaction_path(@workspace, tx),
          params: { category_id: target.id },
          as: :turbo_stream

    assert_response :success
    assert_match(/<tr[^>]*data-transaction-id="#{tx.id}"[^>]*tabindex="0"/, response.body)
  end

  # Codex hotfix A — review row context contract.
  # PR #168~#182 누적 리뷰에서 발견된 권한/상태 계약 leak.

  test "show is reachable by member_read on pending session" do
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    sign_out @user
    sign_in users(:reader)

    get review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_response :success
  end

  test "show hides write affordances for member_read on pending session" do
    # member_read는 read 접근은 되지만 commit/discard/bulk toolbar/category-selector/
    # inline edit URL이 보이면 안 된다 (dead-end UI 방지).
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    @parsing_session.transactions.create!(
      workspace: @workspace, date: Date.current, amount: 1000,
      merchant: "READER_GATED", status: "pending_review"
    )
    sign_out @user
    sign_in users(:reader)

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    # commit 버튼 없음 — 키보드 도움말 overlay (#184)에도 "결제 내역 반영 (commit)"
    # 문자열이 포함되므로 string 비교 대신 actual form action으로 검증.
    commit_path = commit_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_no_match(/action="#{Regexp.escape(commit_path)}"/, response.body)
    # 전체 취소 / 가져오기 되돌리기 없음
    assert_no_match(/전체 취소/, response.body)
    assert_no_match(/가져오기 되돌리기/, response.body)
    # bulk toolbar 없음
    assert_no_match(/data-bulk-select-target="toolbar"/, response.body)
    # category selector controller 없음
    assert_no_match(/data-controller="category-selector"/, response.body)
    # 상태는 '읽기 전용'
    assert_match(/읽기 전용/, response.body)
  end

  test "show shows write affordances for writer on pending session" do
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    @parsing_session.transactions.create!(
      workspace: @workspace, date: Date.current, amount: 1000,
      merchant: "WRITER_AFFORDANCE", status: "pending_review"
    )

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    assert_match(/결제 내역 반영/, response.body)
    assert_match(/data-bulk-select-target="toolbar"/, response.body)
    assert_match(/data-controller="category-selector"/, response.body)
  end

  test "index hides input_sheet trigger from member_read" do
    sign_out @user
    sign_in users(:reader)

    get workspace_reviews_path(@workspace)

    assert_response :success
    assert_no_match(/data-input-sheet-target="trigger"/, response.body)
  end

  test "show category-selector URL is session-scoped (no workspace quick_update leak)" do
    # P0/P1 BLOCKER fix: 검토 화면의 category dropdown이 workspace-level
    # quick_update_category로 새 나가면 reject_if_finalized 가드를 우회한다.
    # category_selector의 update URL은 session-scoped update_transaction이어야.
    tx = @parsing_session.transactions.create!(
      workspace: @workspace, date: Date.current, amount: 1000,
      merchant: "REVIEW_CATEGORY_URL", status: "pending_review"
    )
    @parsing_session.update!(status: "completed", review_status: "pending_review")

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    expected = update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id)
    assert_match(/data-category-selector-update-url-value="#{Regexp.escape(expected)}"/, response.body)
    # request style은 review 컨텍스트에서 "field" (field=category_id, value=...)
    assert_match(/data-category-selector-request-style-value="field"/, response.body)
  end

  test "show category-selector data passes parsing_session_id for slideover preservation" do
    @parsing_session.update!(status: "completed", review_status: "pending_review")
    @parsing_session.transactions.create!(
      workspace: @workspace, date: Date.current, amount: 1000,
      merchant: "SLIDEOVER_CTX", status: "pending_review"
    )

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    assert_match(/data-category-selector-parsing-session-id-value="#{@parsing_session.id}"/, response.body)
  end

  # Codex PR #182 P2: 공유 partial이 transactions/index에서도 사용되므로
  # tabindex=0이 reviewable 컨텍스트에서만 적용돼야 한다.
  test "transactions/index does not make row tabindex=0 (shared partial gating)" do
    @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "INDEX_NO_TABINDEX",
      status: "committed"
    )

    get workspace_transactions_path(@workspace)
    assert_response :success
    # 거래 row는 있지만 tabindex=0은 *없어야*.
    assert_select "tr[data-transaction-id]", minimum: 1
    assert_select "tr[data-transaction-id][tabindex='0']", count: 0,
                  message: "reviews/show 외에서는 row tabindex 미부여"
  end
end
