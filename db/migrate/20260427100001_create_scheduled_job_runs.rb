class CreateScheduledJobRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduled_job_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :job_name,          null: false
      t.date     :run_date,          null: false
      t.string   :status,            null: false, default: "pending"
      t.datetime :started_at
      t.datetime :finished_at
      t.integer  :records_written
      t.integer  :symbols_requested
      t.integer  :symbols_succeeded
      t.string   :error_message
      t.string   :source
      t.timestamps
    end

    add_index :scheduled_job_runs, [ :job_name, :run_date ], unique: true
    add_index :scheduled_job_runs, :status
    add_index :scheduled_job_runs, :run_date
  end
end
