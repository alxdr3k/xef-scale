# frozen_string_literal: true

# Service class for parsing Excel files using Python subprocess
# This provides reliable parsing for Korean financial statements
# including old .xls formats that Ruby's roo gem struggles with
class PythonExcelParser
  class ParseError < StandardError; end

  PYTHON_SCRIPT = Rails.root.join("scripts", "parse_excel.py").to_s.freeze
  PYTHON_BIN = Rails.root.join(".venv", "bin", "python3").to_s.freeze

  # Parse an Excel file and return transactions
  # @param file_path [String] Path to the Excel file
  # @param password [String, nil] Password for encrypted files
  # @return [Hash] Parsed result with :institution, :transactions, :count
  def self.parse(file_path, password: nil)
    new(file_path, password: password).parse
  end

  def initialize(file_path, password: nil)
    @file_path = file_path
    @password = password
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
    cmd = [ PYTHON_BIN, PYTHON_SCRIPT, @file_path ]
    cmd.push("--password", @password) if @password.present?

    stdout, stderr, status = Open3.capture3(*cmd)

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
      parsed = {
        date: Date.parse(tx["date"]),
        merchant: tx["merchant"],
        amount: tx["amount"],
        description: tx["description"],
        institution_identifier: tx["institution_identifier"]
      }

      # Optional fields (installment, benefit, payment type)
      parsed[:payment_type] = tx["payment_type"] if tx["payment_type"]
      parsed[:original_amount] = tx["original_amount"] if tx["original_amount"]
      parsed[:installment_month] = tx["installment_month"] if tx["installment_month"]
      parsed[:installment_total] = tx["installment_total"] if tx["installment_total"]
      parsed[:benefit_type] = tx["benefit_type"] if tx["benefit_type"]
      parsed[:benefit_amount] = tx["benefit_amount"] if tx["benefit_amount"]

      parsed
    end

    {
      institution: result["institution"],
      transactions: transactions,
      count: result["count"]
    }
  end
end
