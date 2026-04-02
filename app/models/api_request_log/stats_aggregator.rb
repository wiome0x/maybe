module ApiRequestLog::StatsAggregator
  extend ActiveSupport::Concern

  class_methods do
    def daily_totals(start_date:, end_date:)
      in_period(start_date, end_date)
        .group("DATE(requested_at)")
        .select("DATE(requested_at) AS date, COUNT(*) AS total,
                 COUNT(*) FILTER (WHERE request_status = 'success') AS success_count,
                 COUNT(*) FILTER (WHERE request_status = 'error') AS error_count")
        .order("date")
    end

    def provider_summary(start_date:, end_date:)
      in_period(start_date, end_date)
        .group(:provider_name)
        .select("provider_name, COUNT(*) AS total,
                 COUNT(*) FILTER (WHERE request_status = 'error') AS error_count")
        .order("total DESC")
    end

    def overview_stats(start_date:, end_date:)
      scope = in_period(start_date, end_date)
      total = scope.count
      errors = scope.errors.count
      avg_response_time = scope.average(:response_time_ms)&.round(1) || 0

      {
        total_requests: total,
        total_errors: errors,
        error_rate: total > 0 ? (errors.to_f / total * 100).round(1) : 0,
        avg_response_time_ms: avg_response_time
      }
    end

    def default_period
      30
    end
  end
end
