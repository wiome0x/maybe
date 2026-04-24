class Settings::TransactionOrganizationsController < ApplicationController
  layout "settings"

  def show
    @categories_count = Current.family.categories.count
    @merchants_count = Current.family.merchants.count
    @rules_count = Current.family.rules.count
    @tags_count = Current.family.tags.count
  end
end
