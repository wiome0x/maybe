class Crypto < ApplicationRecord
  include Accountable

  class << self
    def color
      "#737373"
    end

    def classification
      "asset"
    end

    def icon
      "bitcoin"
    end

    def display_name
      I18n.t("accountable.crypto", default: "Crypto")
    end
  end
end
