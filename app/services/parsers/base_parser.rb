module Parsers
  class BaseParser
    attr_reader :processed_file

    def initialize(processed_file)
      @processed_file = processed_file
    end

    def parse
      raise NotImplementedError, "Subclass must implement #parse"
    end

    protected

    def institution_identifier
      raise NotImplementedError, "Subclass must define institution_identifier"
    end

    def download_file
      blob_filename = processed_file.file.blob.filename.to_s
      extension = File.extname(blob_filename)
      basename = File.basename(blob_filename, extension)
      basename = "statement" if basename.blank?
      tempfile = Tempfile.new([ basename, extension ])
      tempfile.binmode
      tempfile.write(processed_file.file.download)
      tempfile.rewind
      tempfile
    end

    def open_spreadsheet(tempfile)
      content_type = processed_file.file.blob.content_type
      extension = case content_type
      when "application/vnd.ms-excel" then :xls
      when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" then :xlsx
      else :xls
      end
      Roo::Spreadsheet.open(tempfile.path, extension: extension)
    end

    def parse_date(date_string)
      return nil if date_string.blank?

      # Common date formats
      formats = [
        "%Y.%m.%d",
        "%Y-%m-%d",
        "%Y/%m/%d",
        "%y.%m.%d",
        "%y-%m-%d",
        "%y/%m/%d",
        "%m/%d/%Y",
        "%d/%m/%Y"
      ]

      formats.each do |fmt|
        begin
          date = Date.strptime(date_string.to_s.strip, fmt)
          # Handle 2-digit years
          date = Date.new(2000 + date.year, date.month, date.day) if date.year < 100
          return date
        rescue ArgumentError
          next
        end
      end

      nil
    end

    def parse_amount(amount_string)
      return 0 if amount_string.blank?

      # Remove currency symbols, commas, spaces
      cleaned = amount_string.to_s.gsub(/[^\d.-]/, "")
      cleaned.to_i.abs
    end

    def build_transaction(date:, merchant:, amount:, description: nil, installment_month: nil, installment_total: nil, payment_type: nil, benefit_type: nil, benefit_amount: nil)
      {
        date: date,
        merchant: merchant.to_s.strip,
        description: description.to_s.strip,
        amount: amount,
        institution_identifier: institution_identifier,
        installment_month: installment_month,
        installment_total: installment_total,
        payment_type: payment_type,
        benefit_type: benefit_type,
        benefit_amount: benefit_amount
      }
    end
  end
end
