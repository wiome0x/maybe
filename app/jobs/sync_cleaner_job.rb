class SyncCleanerJob < ApplicationJob
  queue_as :scheduled

  def perform
    track_run("clean_syncs") do
      Sync.clean
    end
  end
end
