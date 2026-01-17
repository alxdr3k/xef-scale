require "test_helper"

class FinancialInstitutionTest < ActiveSupport::TestCase
  test "financial institution is valid with valid attributes" do
    fi = financial_institutions(:shinhan_card)
    assert fi.valid?
  end

  test "financial institution requires name" do
    fi = FinancialInstitution.new(identifier: 'test')
    assert_not fi.valid?
    assert_includes fi.errors[:name], "can't be blank"
  end

  test "financial institution requires identifier" do
    fi = FinancialInstitution.new(name: 'Test')
    assert_not fi.valid?
    assert_includes fi.errors[:identifier], "can't be blank"
  end

  test "financial institution identifier must be unique" do
    existing = financial_institutions(:shinhan_card)
    fi = FinancialInstitution.new(name: 'New', identifier: existing.identifier)
    assert_not fi.valid?
    assert_includes fi.errors[:identifier], "has already been taken"
  end

  test "banks scope returns only bank type" do
    banks = FinancialInstitution.banks
    banks.each do |fi|
      assert_equal 'bank', fi.institution_type
    end
    assert_includes banks, financial_institutions(:toss_bank)
    assert_not_includes banks, financial_institutions(:shinhan_card)
  end

  test "cards scope returns only card type" do
    cards = FinancialInstitution.cards
    cards.each do |fi|
      assert_equal 'card', fi.institution_type
    end
    assert_includes cards, financial_institutions(:shinhan_card)
    assert_not_includes cards, financial_institutions(:toss_bank)
  end

  test "pays scope returns only pay type" do
    pays = FinancialInstitution.pays
    pays.each do |fi|
      assert_equal 'pay', fi.institution_type
    end
    assert_includes pays, financial_institutions(:toss_pay)
  end

  test "seed_default! creates missing supported institutions" do
    # Delete one institution that's not referenced by transactions
    test_institution = FinancialInstitution.create!(name: 'Test', identifier: 'test_inst', institution_type: 'bank')
    test_institution.destroy

    initial_count = FinancialInstitution.count
    FinancialInstitution.seed_default!

    # Should have all supported institutions
    FinancialInstitution::SUPPORTED_INSTITUTIONS.each do |attrs|
      assert FinancialInstitution.exists?(identifier: attrs[:identifier])
    end
  end

  test "seed_default! is idempotent" do
    FinancialInstitution.seed_default!
    initial_count = FinancialInstitution.count

    FinancialInstitution.seed_default!
    assert_equal initial_count, FinancialInstitution.count
  end

  test "SUPPORTED_INSTITUTIONS contains expected institutions" do
    identifiers = FinancialInstitution::SUPPORTED_INSTITUTIONS.map { |i| i[:identifier] }
    assert_includes identifiers, 'shinhan_card'
    assert_includes identifiers, 'hana_card'
    assert_includes identifiers, 'toss_bank'
    assert_includes identifiers, 'kakao_bank'
  end
end
