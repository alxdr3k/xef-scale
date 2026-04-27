# Seed financial institutions
puts "Seeding financial institutions..."
FinancialInstitution.seed_default!
puts "Created #{FinancialInstitution.count} financial institutions"

# Create a test user if in development or test
if Rails.env.development? || Rails.env.test?
  puts "Seeding development data..."

  # Create test user
  user = User.find_or_create_by!(email: 'test@example.com') do |u|
    u.password = 'password123'
    u.name = '테스트 사용자'
  end
  puts "Created test user: #{user.email}"

  # Create a workspace for the test user
  workspace = user.owned_workspaces.find_or_create_by!(name: '개인 가계부')
  puts "Created workspace: #{workspace.name}"

  # Create some sample transactions
  if workspace.transactions.empty?
    categories = workspace.categories.to_a
    institutions = FinancialInstitution.all.to_a

    sample_transactions = [
      { date: Date.today - 1, merchant: '스타벅스 강남점', amount: 5500, description: '아메리카노' },
      { date: Date.today - 2, merchant: 'GS25 역삼점', amount: 3200, description: '간식' },
      { date: Date.today - 3, merchant: '배달의민족', amount: 18000, description: '치킨' },
      { date: Date.today - 5, merchant: '쿠팡', amount: 45000, description: '생활용품' },
      { date: Date.today - 7, merchant: 'SK에너지 셀프주유소', amount: 70000, description: '주유' },
      { date: Date.today - 10, merchant: '네이버페이', amount: 12000, description: '온라인 쇼핑' },
      { date: Date.today - 14, merchant: 'KT', amount: 55000, description: '통신비' },
      { date: Date.today - 20, merchant: '삼성생명', amount: 100000, description: '보험료' }
    ]

    sample_transactions.each do |tx|
      category = categories.find { |c| c.matches?(tx[:merchant]) } || categories.last
      institution = institutions.sample

      workspace.transactions.create!(
        date: tx[:date],
        merchant: tx[:merchant],
        amount: tx[:amount],
        description: tx[:description],
        category: category,
        financial_institution: institution
      )
    end
    puts "Created #{sample_transactions.count} sample transactions"
  end
end

puts "Seeding complete!"
