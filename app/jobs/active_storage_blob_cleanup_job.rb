class ActiveStorageBlobCleanupJob < ApplicationJob
  queue_as :default

  # ADR-0002: walk every ProcessedFile that still has its blob attached and ask
  # the model whether the linked ParsingSession has been in a terminal state
  # long enough to release the file. The actual file.purge_later is fanned out
  # inside ProcessedFile#purge_blob! so a slow storage backend cannot block this
  # daily sweep.
  def perform
    purged = 0
    scanned = 0

    ProcessedFile.blob_retained.find_each do |processed_file|
      scanned += 1
      next unless processed_file.blob_eligible_for_purge?

      purged += 1 if processed_file.purge_blob!
    rescue StandardError => e
      Rails.logger.error(
        "[ActiveStorageBlobCleanupJob] processed_file=#{processed_file.id} " \
        "failed: #{e.class} #{e.message}"
      )
    end

    Rails.logger.info(
      "[ActiveStorageBlobCleanupJob] scanned=#{scanned} purged=#{purged}"
    )
  end
end
