class StripStatementPasswordAndCardWithdrawalSettings < ActiveRecord::Migration[8.1]
  OBSOLETE_KEYS = %w[statement_password statement_passwords exclude_card_withdrawals].freeze

  def up
    User.reset_column_information

    User.where.not(settings: nil).find_each do |user|
      settings = user.settings.is_a?(Hash) ? user.settings.dup : nil
      next if settings.nil?
      next unless OBSOLETE_KEYS.any? { |k| settings.key?(k) }

      OBSOLETE_KEYS.each { |k| settings.delete(k) }
      user.update_columns(settings: settings)
    end
  end

  def down
    # Irreversible: we deliberately drop the stored secrets (statement
    # passwords) and deprecated settings. Recovery is not possible.
    raise ActiveRecord::IrreversibleMigration
  end
end
