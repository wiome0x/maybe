class SecurityHealthCheckJob < ApplicationJob
  queue_as :scheduled

  def perform
    return if Rails.env.development?

    track_run("run_security_health_checks") do
      Security::HealthChecker.check_all
    end
  end
end
