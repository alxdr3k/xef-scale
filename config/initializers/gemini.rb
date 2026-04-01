Rails.application.config.after_initialize do
  if ENV["GEMINI_API_KEY"].present?
    Gemini.configure do |config|
      config.api_key = ENV["GEMINI_API_KEY"]
    end
  end
end
