# frozen_string_literal: true

Rails.application.configure do
  config.solid_queue.connects_to = { database: { writing: :queue } }
end
