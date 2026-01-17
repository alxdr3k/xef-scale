ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Load dotenv early to ensure ENV vars are available for initializers
begin
  require "dotenv/load"
rescue LoadError
  # dotenv not available (production)
end
