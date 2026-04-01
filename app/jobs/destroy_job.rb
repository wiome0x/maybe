class DestroyJob < ApplicationJob
  queue_as :low_priority

  def perform(model)
    Rails.logger.info("[DestroyJob] Starting destruction of #{model.class.name}##{model.id}")

    model.destroy!

    Rails.logger.info("[DestroyJob] Successfully destroyed #{model.class.name}##{model.id}")
  rescue => e
    Rails.logger.error("[DestroyJob] Failed to destroy #{model.class.name}##{model.id}: #{e.class} - #{e.message}")
    Rails.logger.error("[DestroyJob] Backtrace: #{e.backtrace.first(10).join("\n")}")

    begin
      if model.respond_to?(:scheduled_for_deletion)
        model.update!(scheduled_for_deletion: false)
        Rails.logger.info("[DestroyJob] Reset scheduled_for_deletion for #{model.class.name}##{model.id}")
      elsif model.respond_to?(:may_disable?) && model.may_disable?
        model.disable!
        Rails.logger.info("[DestroyJob] Disabled #{model.class.name}##{model.id} after failed deletion")
      end
    rescue => recovery_error
      Rails.logger.error("[DestroyJob] Recovery also failed for #{model.class.name}##{model.id}: #{recovery_error.message}")
    end
  end
end
