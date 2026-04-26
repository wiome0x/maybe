class SecurityDetailsJob < ApplicationJob
  queue_as :low_priority

  def perform(security_id)
    security = Security.find_by(id: security_id)
    return unless security

    security.import_provider_details
  end
end
