# frozen_string_literal: true

# Service class for parsing Excel files using Python subprocess
# This provides reliable parsing for Korean financial statements
# including old .xls formats that Ruby's roo gem struggles with
class PythonExcelParser
  class ParseError < StandardError; end

  PYTHON_SCRIPT = Rails.root.join("scripts", "parse_excel.py").to_s.freeze

  # Parse an Excel file and return transactions
  # @param file_path [String] Path to the Excel file
  # @return [Hash] Parsed result with :institution, :transactions, :count
  def self.parse(file_path)
    new(file_path).parse
  end

  def initialize(file_path)
    @file_path = file_path
  end

  def parse
    validate_file!
    result = execute_python_parser
    process_result(result)
  end

  private

  def validate_file!
    raise ParseError, "File not found: #{@file_path}" unless File.exist?(@file_path)
    raise ParseError, "File is empty: #{@file_path}" if File.empty?(@file_path)
  end

  def execute_python_parser
    stdout, stderr, status = Open3.capture3("python3", PYTHON_SCRIPT, @file_path)

    unless status.success?
      Rails.logger.error "Python parser failed: #{stderr}"
      raise ParseError, "Python parser failed: #{stderr}"
    end

    # Parse JSON output (ignore warnings on stderr)
    begin
      JSON.parse(stdout)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse Python output: #{stdout}"
      raise ParseError, "Invalid JSON from parser: #{e.message}"
    end
  end

  def process_result(result)
    if result["error"]
      raise ParseError, result["error"]
    end

    # Convert date strings to Date objects
    transactions = result["transactions"].map do |tx|
      {
        date: Date.parse(tx["date"]),
        merchant: tx["merchant"],
        amount: tx["amount"],
        description: tx["description"],
        institution_identifier: tx["institution_identifier"]
      }
    end

    {
      institution: result["institution"],
      transactions: transactions,
      count: result["count"]
    }
  end
end
