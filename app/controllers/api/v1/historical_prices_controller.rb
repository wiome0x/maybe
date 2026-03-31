# frozen_string_literal: true

class Api::V1::HistoricalPricesController < Api::V1::BaseController
  include Pagy::Backend

  before_action :ensure_read_scope, only: [ :index ]

  def index
    query = current_resource_owner.family.historical_prices
    query = query.by_ticker(params[:ticker]) if params[:ticker].present?
    query = query.by_date_range(params[:start_date], params[:end_date])
    query = query.ordered_by_date

    @pagy, @historical_prices = pagy(
      query,
      page: safe_page_param,
      limit: safe_per_page_param
    )

    render :index
  end

  private

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def safe_page_param
      page = params[:page].to_i
      page > 0 ? page : 1
    end

    def safe_per_page_param
      per_page = params[:per_page].to_i
      case per_page
      when 1..1000
        per_page
      else
        100
      end
    end
end
