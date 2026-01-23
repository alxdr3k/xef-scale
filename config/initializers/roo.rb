# Load roo-xls extension for old .xls file support
# Note: Excel parsing is now handled by Python subprocess (scripts/parse_excel.py)
# This is kept for any Ruby code that might still use Roo directly
require "roo"
require "roo-xls"
