# frozen_string_literal: true

namespace :import do
  # 카테고리 색상 팔레트
  CATEGORY_COLORS = %w[
    #FF6B6B #4ECDC4 #45B7D1 #96CEB4 #DDA0DD
    #FFB347 #87CEEB #C0C0C0 #F0E68C #98D8C8
    #F7DC6F #BB8FCE #85C1E9 #F8B500 #A3E4D7
    #D3D3D3
  ].freeze

  desc "Step 0: Import 전 development 데이터베이스 snapshot 생성"
  task backup: :environment do
    puts "=" * 50
    puts "Step 0: 데이터베이스 백업 시작..."
    puts "=" * 50

    backup_service = DatabaseBackupService.new
    path = backup_service.backup("pre_import")
    puts "✓ 백업 완료: #{path}"
  end

  desc "Step 1: 카테고리 테이블 초기화 및 txt 파일에서 카테고리 생성"
  task setup_categories: :environment do
    puts "=" * 50
    puts "Step 1: 카테고리 설정 시작..."
    puts "=" * 50

    workspace = Workspace.first
    abort "워크스페이스가 없습니다. 먼저 워크스페이스를 생성해주세요." unless workspace

    puts "워크스페이스: #{workspace.name}"

    # 기존 카테고리 삭제
    puts "기존 카테고리 삭제 중..."
    workspace.category_mappings.destroy_all
    workspace.categories.destroy_all
    puts "✓ 기존 카테고리 삭제 완료"

    # txt 파일에서 카테고리 추출
    categories = Set.new
    files = [ "2024.txt", "2025.txt" ].map { |f| Rails.root.join(f) }

    files.each do |file_path|
      next unless File.exist?(file_path)

      puts "파일 분석 중: #{File.basename(file_path)}"
      is_2024 = file_path.to_s.include?("2024")

      File.foreach(file_path) do |line|
        fields = line.strip.split("\t")
        next if fields.length < 3

        # 2024.txt: 월 | 카테고리 | 내역 | 금액 (4컬럼)
        # 2025.txt: 월 | 날짜 | 카테고리 | 내역 | 금액 (5컬럼)
        category_name = if is_2024
                          fields[1]
        else
                          fields[2]
        end

        categories << category_name if category_name.present?
      end
    end

    # 카테고리 생성
    puts "#{categories.size}개 카테고리 생성 중..."
    categories.each_with_index do |name, index|
      color = CATEGORY_COLORS[index % CATEGORY_COLORS.length]
      workspace.categories.create!(name: name, color: color)
      puts "  - #{name}"
    end

    puts "✓ #{workspace.categories.count}개 카테고리 생성 완료"
  end

  desc "Step 2: txt 파일에서 카테고리 매핑 생성"
  task build_mappings: :environment do
    puts "=" * 50
    puts "Step 2: 카테고리 매핑 생성 시작..."
    puts "=" * 50

    workspace = Workspace.first
    abort "워크스페이스가 없습니다." unless workspace

    mappings_created = 0
    files = [ "2024.txt", "2025.txt" ].map { |f| Rails.root.join(f) }

    files.each do |file_path|
      next unless File.exist?(file_path)

      puts "파일 처리 중: #{File.basename(file_path)}"
      is_2024 = file_path.to_s.include?("2024")

      File.foreach(file_path) do |line|
        fields = line.strip.split("\t")
        next if fields.length < 4

        if is_2024
          # 2024.txt: 월 | 카테고리 | 내역 | 금액
          category_name = fields[1]
          merchant = fields[2]
        else
          # 2025.txt: 월 | 날짜 | 카테고리 | 내역 | 금액
          category_name = fields[2]
          merchant = fields[3]
        end

        next if merchant.blank?

        category = workspace.categories.find_by(name: category_name)
        next unless category

        # 이미 매핑이 있으면 스킵
        next if CategoryMapping.exists?(workspace: workspace, merchant_pattern: merchant)

        CategoryMapping.create!(
          workspace: workspace,
          merchant_pattern: merchant,
          category: category,
          source: "import"
        )
        mappings_created += 1
      end
    end

    puts "✓ #{mappings_created}개 카테고리 매핑 생성 완료"
    puts "총 매핑 수: #{workspace.category_mappings.count}"
  end

  desc "Step 3: txt 파일에서 거래 내역 Import"
  task transactions: :environment do
    puts "=" * 50
    puts "Step 3: 거래 내역 Import 시작..."
    puts "=" * 50

    workspace = Workspace.first
    user = User.first
    abort "워크스페이스가 없습니다." unless workspace
    abort "사용자가 없습니다." unless user

    # Gemini 서비스 초기화 (API 키가 없으면 nil)
    gemini_service = begin
      GeminiCategoryService.new
    rescue ArgumentError => e
      puts "⚠ Gemini API 비활성화: #{e.message}"
      nil
    end

    stats = { imported: 0, skipped: 0, errors: [], gemini_calls: 0 }
    files = [ "2024.txt", "2025.txt" ].map { |f| Rails.root.join(f) }

    files.each do |file_path|
      next unless File.exist?(file_path)

      puts "파일 처리 중: #{File.basename(file_path)}"
      is_2024 = file_path.to_s.include?("2024")
      year = is_2024 ? 2024 : 2025

      File.foreach(file_path).with_index do |line, line_num|
        begin
          fields = line.strip.split("\t")
          next if fields.length < 4

          if is_2024
            # 2024.txt: 월 | 카테고리 | 내역 | 금액
            month_str = fields[0]
            category_name = fields[1]
            merchant = fields[2]
            amount_str = fields[3]

            # 월 파싱: "9월" → 9
            month = month_str.gsub(/[월\s]/, "").to_i
            date = Date.new(year, month, 1) rescue nil
          else
            # 2025.txt: 월 | 날짜 | 카테고리 | 내역 | 금액
            month_str = fields[0]
            date_str = fields[1]
            category_name = fields[2]
            merchant = fields[3]
            amount_str = fields[4]

            # 날짜 파싱: "2025.01.01" → Date
            # 날짜가 비어있으면 해당 월 1일로 설정
            if date_str.present?
              date = Date.parse(date_str.gsub(".", "-")) rescue nil
            else
              month = month_str.to_i
              date = Date.new(year, month, 1) rescue nil
            end
          end

          # 금액 파싱: "₩29,000" → 29000
          amount = amount_str.to_s.gsub(/[₩,\s]/, "").to_i.abs

          # 금액 0원 스킵
          if amount == 0
            stats[:skipped] += 1
            next
          end

          # 날짜 없으면 스킵
          unless date
            stats[:errors] << { line: line_num + 1, error: "날짜 파싱 실패", content: line.strip }
            next
          end

          # 카테고리 찾기
          category = workspace.categories.find_by(name: category_name)

          # 카테고리가 없으면 매핑 테이블에서 찾기
          unless category
            mapping = CategoryMapping.find_for_merchant(workspace, merchant)
            category = mapping&.category
          end

          # 여전히 없으면 Gemini API 호출 또는 기타로 설정
          unless category
            if gemini_service && merchant.present?
              begin
                suggested_name = gemini_service.suggest_category(merchant, workspace.categories.to_a)
                category = workspace.categories.find_by(name: suggested_name)

                # 매핑 저장
                if category
                  CategoryMapping.create!(
                    workspace: workspace,
                    merchant_pattern: merchant,
                    category: category,
                    source: "gemini"
                  )
                  stats[:gemini_calls] += 1
                end
              rescue StandardError => e
                puts "  ⚠ Gemini API 오류: #{e.message}"
              end
            end

            # 최종 폴백: 기타 카테고리
            category ||= workspace.categories.find_by(name: "기타")
          end

          # 거래 생성
          workspace.transactions.create!(
            date: date,
            merchant: merchant,
            description: merchant,
            amount: amount,
            category: category,
            status: "committed",
            committed_at: Time.current,
            committed_by: user
          )

          stats[:imported] += 1

          # 진행 상황 출력 (100건마다)
          print "." if (stats[:imported] % 100).zero?
        rescue StandardError => e
          stats[:errors] << { line: line_num + 1, error: e.message, content: line.strip }
        end
      end
      puts # 줄바꿈
    end

    puts "\n✓ Import 완료!"
    puts "  - 성공: #{stats[:imported]}건"
    puts "  - 스킵 (금액 0원): #{stats[:skipped]}건"
    puts "  - Gemini API 호출: #{stats[:gemini_calls]}건"
    puts "  - 오류: #{stats[:errors].length}건"

    if stats[:errors].any?
      puts "\n오류 목록 (처음 10건):"
      stats[:errors].first(10).each do |err|
        puts "  Line #{err[:line]}: #{err[:error]}"
      end
    end
  end

  desc "Step 4: Import 후 development 데이터베이스 snapshot 생성"
  task post_backup: :environment do
    puts "=" * 50
    puts "Step 4: Import 후 백업 시작..."
    puts "=" * 50

    backup_service = DatabaseBackupService.new
    path = backup_service.backup("post_import")
    puts "✓ 백업 완료: #{path}"
  end

  desc "전체 Import 파이프라인 실행 (backup → setup_categories → build_mappings → transactions → post_backup)"
  task all: %i[backup setup_categories build_mappings transactions post_backup] do
    puts "=" * 50
    puts "🎉 전체 Import 파이프라인 완료!"
    puts "=" * 50

    workspace = Workspace.first
    if workspace
      puts "\n최종 통계:"
      puts "  - 카테고리: #{workspace.categories.count}개"
      puts "  - 매핑: #{workspace.category_mappings.count}개"
      puts "  - 거래 내역: #{workspace.transactions.count}건"
    end
  end

  desc "백업 목록 확인"
  task list_backups: :environment do
    backup_service = DatabaseBackupService.new
    backups = backup_service.list_backups

    if backups.empty?
      puts "백업이 없습니다."
    else
      puts "백업 목록:"
      backups.each do |path|
        size = File.size(path) / 1024.0
        puts "  - #{File.basename(path)} (#{size.round(1)} KB)"
      end
    end
  end
end
