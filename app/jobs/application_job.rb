class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked
  discard_on ActiveJob::DeserializationError
  queue_as :low_priority # default queue

  private

    # Wraps a block in a ScheduledJobRun record.
    # Yields a run object so callers can set extra fields (records_written, etc.).
    #
    # Usage:
    #   track_run("my_job_name") do |run|
    #     # do work
    #     run.records_written = 42
    #   end
    def track_run(job_name, date: Date.current)
      run = ScheduledJobRun.find_or_initialize_by(job_name: job_name, run_date: date)
      run.assign_attributes(status: "running", started_at: Time.current, error_message: nil, finished_at: nil)
      run.save!

      yield run

      run.update!(status: "completed", finished_at: Time.current)
    rescue => e
      run&.update!(status: "failed", finished_at: Time.current, error_message: e.message.truncate(500))
      raise
    end
end
