require "test_helper"
require Rails.root.join(
  "db/migrate/20260422074047_strip_statement_password_and_card_withdrawal_settings.rb"
)

class StripStatementPasswordAndCardWithdrawalSettingsTest < ActiveSupport::TestCase
  test "removes obsolete statement/card settings but keeps other keys" do
    user = users(:admin)
    user.update_column(:settings, {
      "statement_password" => "820101",
      "statement_passwords" => { "shinhan_card" => "820101" },
      "exclude_card_withdrawals" => true,
      "excluded_merchants" => [ "본인이체" ]
    })

    StripStatementPasswordAndCardWithdrawalSettings.new.up

    stored = user.reload.settings
    assert_equal({ "excluded_merchants" => [ "본인이체" ] }, stored)
  end

  test "skips users without obsolete keys" do
    user = users(:admin)
    user.update_column(:settings, { "excluded_merchants" => [ "X" ] })

    assert_nothing_raised { StripStatementPasswordAndCardWithdrawalSettings.new.up }
    assert_equal({ "excluded_merchants" => [ "X" ] }, user.reload.settings)
  end

  test "skips users with nil settings" do
    user = users(:admin)
    user.update_column(:settings, nil)

    assert_nothing_raised { StripStatementPasswordAndCardWithdrawalSettings.new.up }
    assert_nil user.reload.settings
  end

  test "down raises IrreversibleMigration" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      StripStatementPasswordAndCardWithdrawalSettings.new.down
    end
  end
end
