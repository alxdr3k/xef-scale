require "test_helper"

class DuplicateConfirmationTest < ActiveSupport::TestCase
  test "duplicate confirmation is valid with valid attributes" do
    dc = duplicate_confirmations(:pending_duplicate)
    assert dc.valid?
  end

  test "duplicate confirmation requires valid status" do
    dc = DuplicateConfirmation.new(
      parsing_session: parsing_sessions(:completed_session),
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: 'invalid'
    )
    assert_not dc.valid?
    assert_includes dc.errors[:status], "is not included in the list"
  end

  test "pending? returns true for pending status" do
    dc = duplicate_confirmations(:pending_duplicate)
    assert dc.pending?
  end

  test "resolved? returns false for pending status" do
    dc = duplicate_confirmations(:pending_duplicate)
    assert_not dc.resolved?
  end

  test "resolved? returns true for non-pending status" do
    dc = duplicate_confirmations(:resolved_duplicate)
    assert dc.resolved?
  end

  test "keep_both! updates status to keep_both" do
    dc = duplicate_confirmations(:pending_duplicate)
    dc.keep_both!
    assert_equal 'keep_both', dc.status
  end

  test "keep_original! soft deletes new transaction" do
    dc = duplicate_confirmations(:pending_duplicate)
    new_tx = dc.new_transaction

    dc.keep_original!

    assert_equal 'keep_original', dc.status
    assert new_tx.reload.deleted
  end

  test "keep_new! soft deletes original transaction" do
    dc = duplicate_confirmations(:pending_duplicate)
    original_tx = dc.original_transaction

    dc.keep_new!

    assert_equal 'keep_new', dc.status
    assert original_tx.reload.deleted
  end

  test "resolve! with keep_both calls keep_both!" do
    dc = duplicate_confirmations(:pending_duplicate)
    dc.resolve!('keep_both')
    assert_equal 'keep_both', dc.status
  end

  test "resolve! with keep_original calls keep_original!" do
    dc = DuplicateConfirmation.create!(
      parsing_session: parsing_sessions(:completed_session),
      original_transaction: transactions(:shopping_transaction),
      new_transaction: transactions(:other_workspace_transaction),
      status: 'pending'
    )
    dc.resolve!('keep_original')
    assert_equal 'keep_original', dc.status
  end

  test "resolve! with keep_new calls keep_new!" do
    dc = DuplicateConfirmation.create!(
      parsing_session: parsing_sessions(:completed_session),
      original_transaction: transactions(:shopping_transaction),
      new_transaction: transactions(:other_workspace_transaction),
      status: 'pending'
    )
    dc.resolve!('keep_new')
    assert_equal 'keep_new', dc.status
  end

  test "resolve! raises error for invalid decision" do
    dc = duplicate_confirmations(:pending_duplicate)
    assert_raises(ArgumentError) do
      dc.resolve!('invalid')
    end
  end

  test "pending scope returns only pending confirmations" do
    pending = DuplicateConfirmation.pending
    pending.each do |dc|
      assert dc.pending?
    end
  end

  test "resolved scope returns only resolved confirmations" do
    resolved = DuplicateConfirmation.resolved
    resolved.each do |dc|
      assert dc.resolved?
    end
  end
end
