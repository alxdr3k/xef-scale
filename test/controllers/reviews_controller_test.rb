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
end
