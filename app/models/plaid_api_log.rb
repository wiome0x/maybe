class PlaidApiLog < ApplicationRecord
  belongs_to :plaid_item, optional: true

  validates :region, :source, :endpoint, :requested_at, presence: true
end
