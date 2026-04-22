require "tempfile"

class ImageStatementParser
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .heic].freeze
  MIME_TYPES = {
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp",
    ".heic" => "image/heic"
  }.freeze
  DATE_FORMATS = %w[%Y.%m.%d %Y-%m-%d %Y/%m/%d %y.%m.%d %y-%m-%d %y/%m/%d %m/%d/%Y %d/%m/%Y].freeze
  DEFAULT_INSTITUTION = "shinhan_card"

  class UnsupportedFormatError < StandardError; end

  def initialize(processed_file, institution_identifier: nil)
    @processed_file = processed_file
    @institution_identifier = institution_identifier.presence || DEFAULT_INSTITUTION
  end

  def parse
    ext = File.extname(@processed_file.filename.to_s).downcase
    unless IMAGE_EXTENSIONS.include?(ext)
      raise UnsupportedFormatError, "이미지 파일만 지원됩니다 (jpg, jpeg, png, webp, heic)"
    end

    mime_type = MIME_TYPES[ext] || "image/jpeg"
    tempfile = download_to_tempfile

    begin
      service = GeminiVisionParserService.new
      result = service.parse_image(tempfile, mime_type: mime_type)
      normalize(result)
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  private

  def normalize(result)
    raw = if result.is_a?(Hash)
      result[:transactions] || result["transactions"] || []
    else
      Array(result)
    end

    raw.filter_map do |tx|
      date = parse_date(tx[:date] || tx["date"])
      next unless date

      {
        date: date,
        merchant: (tx[:merchant] || tx["merchant"]).to_s.strip,
        description: "",
        amount: (tx[:amount] || tx["amount"]).to_i.abs,
        payment_type: tx[:payment_type] || tx["payment_type"] || "lump_sum",
        installment_month: tx[:installment_month] || tx["installment_month"],
        installment_total: tx[:installment_total] || tx["installment_total"],
        institution_identifier: @institution_identifier
      }
    end
  end

  def parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    DATE_FORMATS.each do |fmt|
      begin
        date = Date.strptime(value.to_s.strip, fmt)
        date = Date.new(2000 + date.year, date.month, date.day) if date.year < 100
        return date
      rescue ArgumentError
        next
      end
    end
    nil
  end

  def download_to_tempfile
    blob_filename = @processed_file.file.blob.filename.to_s
    extension = File.extname(blob_filename)
    basename = File.basename(blob_filename, extension)
    basename = "statement" if basename.blank?

    tempfile = Tempfile.new([ basename, extension ])
    tempfile.binmode
    tempfile.write(@processed_file.file.download)
    tempfile.rewind
    tempfile
  end
end
